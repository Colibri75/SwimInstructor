import { createPublicKey, generateKeyPairSync, KeyObject, sign, verify } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import request from "supertest";
import { accountRoutes, AccountDeps, authRoutes } from "../../src/account";
import { adminRoutes } from "../../src/admin";
import { createApp } from "../../src/app";
import { AppleIdentityVerifier, Jwk } from "../../src/apple";
import {
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  AppleFormPoster,
  AppleRevokeError,
  AppleRevoker,
  normalizePem,
  parseSiwaPrivateKey
} from "../../src/appleRevoke";
import { run } from "../../src/cli/users";
import { loadConfig } from "../../src/config";
import { createLogger } from "../../src/logger";
import { FileUsageLog } from "../../src/usage";
import { FileUserDirectory, readUsers, USERS_FILE } from "../../src/users";
import { TEST_TOKEN, testConfig } from "../helpers";

const BUNDLE_ID = "com.kellner.SwimInstructor";
const NOW = Date.parse("2026-10-09T10:00:00Z");
const TEAM_ID = "TTLJUNRA3R";
const KEY_ID = "ABC123DEFG";
const REFRESH_TOKEN = "r.geheimer-refresh-token";

/** Ein lokal erzeugter EC-P-256-Schluessel spielt den .p8-Schluessel aus dem Apple-Developer-Konto. */
const siwa = (() => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return { pem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(), publicKey };
})();

/** Ein lokal erzeugter RSA-Schluessel spielt Apples Identitaetstoken-Schluessel. */
const appleIdentity = (() => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = { ...(publicKey.export({ format: "jwk" }) as Jwk), kid: "test-kid", alg: "RS256", use: "sig" };
  return { privateKey, jwk };
})();

function identityToken(sub = "001234.abcdef.1234"): string {
  const header = Buffer.from(JSON.stringify({ alg: "RS256", kid: "test-kid" })).toString("base64url");
  const body = Buffer.from(
    JSON.stringify({ iss: "https://appleid.apple.com", aud: BUNDLE_ID, sub, iat: Math.floor(NOW / 1000) - 10, exp: Math.floor(NOW / 1000) + 600 })
  ).toString("base64url");
  const signature = sign("RSA-SHA256", Buffer.from(`${header}.${body}`), appleIdentity.privateKey).toString("base64url");
  return `${header}.${body}.${signature}`;
}

interface Call {
  url: string;
  form: Record<string, string>;
}

/** Spielt Apples Token- und Widerrufs-Schnittstelle und merkt sich jede Anfrage. */
function fakeApple(responses: Partial<Record<string, () => Promise<{ status: number; body: unknown }>>> = {}) {
  const calls: Call[] = [];
  const post: AppleFormPoster = async (url, form) => {
    calls.push({ url, form: Object.fromEntries(form.entries()) });
    const respond = responses[url];
    if (respond !== undefined) return respond();
    if (url === APPLE_TOKEN_URL) return { status: 200, body: { access_token: "a", token_type: "Bearer", expires_in: 3600, refresh_token: REFRESH_TOKEN, id_token: "x" } };
    return { status: 200, body: null };
  };
  return { calls, post };
}

function revoker(post: AppleFormPoster): AppleRevoker {
  return new AppleRevoker({ teamId: TEAM_ID, keyId: KEY_ID, privateKey: siwa.pem, post, now: () => NOW });
}

function decode(part: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as Record<string, unknown>;
}

function verifyEs256(jwt: string, publicKey: KeyObject): boolean {
  const [header, payload, signature] = jwt.split(".");
  return verify("sha256", Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url"));
}

async function waitFor(condition: () => boolean): Promise<void> {
  for (let i = 0; i < 100 && !condition(); i++) await new Promise((resolve) => setTimeout(resolve, 5));
  expect(condition()).toBe(true);
}

describe("client_secret fuer Apple", () => {
  it("ist ein ES256-JWT, das sich mit dem passenden oeffentlichen Schluessel pruefen laesst", () => {
    const secret = revoker(fakeApple().post).clientSecret(BUNDLE_ID);
    const [header, payload, signature] = secret.split(".");

    expect(decode(header)).toEqual({ alg: "ES256", kid: KEY_ID });
    expect(decode(payload)).toEqual({
      iss: TEAM_ID,
      iat: NOW / 1000,
      exp: NOW / 1000 + 300,
      aud: "https://appleid.apple.com",
      sub: BUNDLE_ID
    });
    // r||s: genau 64 Bytes, nicht DER.
    expect(Buffer.from(signature, "base64url")).toHaveLength(64);
    expect(verifyEs256(secret, siwa.publicKey)).toBe(true);
    expect(verifyEs256(secret, generateKeyPairSync("ec", { namedCurve: "prime256v1" }).publicKey)).toBe(false);
  });

  it("liest den Schluessel auch mit \\n statt Zeilenumbruechen und in Anfuehrungszeichen", () => {
    const escaped = siwa.pem.trim().replace(/\n/g, "\\n");
    expect(normalizePem(`"${escaped}"`)).toBe(siwa.pem);
    const secret = new AppleRevoker({ teamId: TEAM_ID, keyId: KEY_ID, privateKey: escaped, post: fakeApple().post }).clientSecret(BUNDLE_ID);
    expect(verifyEs256(secret, createPublicKey(siwa.pem))).toBe(true);
  });

  it("lehnt Schluessel ab, die kein EC P-256 sind", () => {
    const rsa = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();
    expect(() => parseSiwaPrivateKey(rsa)).toThrow("EC-P-256");
    expect(() => parseSiwaPrivateKey("kein Schluessel")).toThrow();
  });
});

describe("AppleRevoker", () => {
  it("tauscht den Code gegen den Refresh-Token und widerruft ihn mit den richtigen Formularfeldern", async () => {
    const apple = fakeApple();
    const r = revoker(apple.post);

    await expect(r.exchangeCode("einmal-code", BUNDLE_ID)).resolves.toBe(REFRESH_TOKEN);
    await r.revoke(REFRESH_TOKEN, BUNDLE_ID);

    expect(apple.calls).toEqual([
      {
        url: APPLE_TOKEN_URL,
        form: { client_id: BUNDLE_ID, client_secret: expect.any(String), code: "einmal-code", grant_type: "authorization_code" }
      },
      {
        url: APPLE_REVOKE_URL,
        form: { client_id: BUNDLE_ID, client_secret: expect.any(String), token: REFRESH_TOKEN, token_type_hint: "refresh_token" }
      }
    ]);
    expect(verifyEs256(apple.calls[1].form.client_secret, siwa.publicKey)).toBe(true);
  });

  it("meldet Apples Fehler als AppleRevokeError, ohne Tokens in der Meldung", async () => {
    const apple = fakeApple({
      [APPLE_TOKEN_URL]: async () => ({ status: 400, body: { error: "invalid_grant" } }),
      [APPLE_REVOKE_URL]: async () => Promise.reject(new Error("offline"))
    });
    const r = revoker(apple.post);

    await expect(r.exchangeCode("code", BUNDLE_ID)).rejects.toThrow(/Status 400 \(invalid_grant\)/);
    const error = await r.revoke(REFRESH_TOKEN, BUNDLE_ID).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AppleRevokeError);
    expect((error as Error).message).not.toContain(REFRESH_TOKEN);
    await expect(revoker(fakeApple({ [APPLE_TOKEN_URL]: async () => ({ status: 200, body: {} }) }).post).exchangeCode("c", BUNDLE_ID)).rejects.toBeInstanceOf(AppleRevokeError);
  });
});

describe("Konfiguration des Widerrufs", () => {
  const token = "a".repeat(40);

  it("ist ohne Schluessel aus, mit Key-ID und Schluessel an (Team-ID mit Standardwert)", () => {
    expect(loadConfig({ API_TOKEN: token }).appleRevoke).toBeUndefined();
    const config = loadConfig({ API_TOKEN: token, APPLE_SIWA_KEY_ID: KEY_ID, APPLE_SIWA_PRIVATE_KEY: siwa.pem.replace(/\n/g, "\\n") });
    expect(config.appleRevoke).toMatchObject({ teamId: "TTLJUNRA3R", keyId: KEY_ID });
    expect(loadConfig({ API_TOKEN: token, APPLE_TEAM_ID: "AAAAABBBBB", APPLE_SIWA_KEY_ID: KEY_ID, APPLE_SIWA_PRIVATE_KEY: siwa.pem }).appleRevoke?.teamId).toBe("AAAAABBBBB");
  });

  it("verweigert den Start bei halber oder kaputter Angabe", () => {
    expect(() => loadConfig({ API_TOKEN: token, APPLE_SIWA_KEY_ID: KEY_ID })).toThrow("APPLE_SIWA_PRIVATE_KEY");
    expect(() => loadConfig({ API_TOKEN: token, APPLE_SIWA_PRIVATE_KEY: siwa.pem })).toThrow("APPLE_SIWA_KEY_ID");
    expect(() => loadConfig({ API_TOKEN: token, APPLE_SIWA_KEY_ID: KEY_ID, APPLE_SIWA_PRIVATE_KEY: "kaputt" })).toThrow("APPLE_SIWA_PRIVATE_KEY nicht lesbar");
    expect(() => loadConfig({ API_TOKEN: token, APPLE_SIWA_KEY_ID: "x", APPLE_SIWA_PRIVATE_KEY: siwa.pem })).toThrow("APPLE_SIWA_KEY_ID ungueltig");
  });
});

describe("Widerruf beim Anmelden und Loeschen", () => {
  function setup(overrides: Partial<AccountDeps> = {}) {
    const dir = mkdtempSync(path.join(tmpdir(), "revoke-"));
    const users = new FileUserDirectory(TEST_TOKEN, dir, () => {}, 0);
    const deps: AccountDeps = {
      usersFile: path.join(dir, USERS_FILE),
      dataDir: dir,
      verifier: new AppleIdentityVerifier({ bundleIds: [BUNDLE_ID], fetchJwks: async () => ({ keys: [appleIdentity.jwk] }), now: () => NOW }),
      signupOpen: true,
      appleClientId: BUNDLE_ID,
      onUsersChanged: () => users.invalidate(),
      ...overrides
    };
    const usage = new FileUsageLog({ dataDir: dir, timezone: "Europe/Berlin" });
    const app = createApp(testConfig, createLogger(testConfig), {
      users,
      registerPublicV1Routes: authRoutes(deps),
      registerV1Routes: (router) => {
        accountRoutes(deps)(router);
        adminRoutes({ usage, usersFile: deps.usersFile, timezone: "Europe/Berlin" })(router);
      }
    });
    return { app, dir, deps };
  }

  const record = (deps: AccountDeps) => readUsers(deps.usersFile)[0];

  it("speichert den Refresh-Token nach der Anmeldung und widerruft ihn beim Loeschen", async () => {
    const apple = fakeApple();
    const { app, deps } = setup({ appleRevoker: revoker(apple.post) });

    const signIn = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "einmal-code" });
    expect(signIn.status).toBe(200);
    await waitFor(() => record(deps)?.apple_refresh_token !== undefined);
    expect(record(deps)).toMatchObject({ apple_refresh_token: REFRESH_TOKEN, apple_client_id: BUNDLE_ID });
    expect(apple.calls[0]).toMatchObject({ url: APPLE_TOKEN_URL, form: { code: "einmal-code", client_id: BUNDLE_ID } });

    const deleted = await request(app).delete("/v1/account").set("Authorization", `Bearer ${signIn.body.token}`);

    expect(deleted.status).toBe(204);
    expect(apple.calls[1]).toEqual({
      url: APPLE_REVOKE_URL,
      form: { client_id: BUNDLE_ID, client_secret: expect.any(String), token: REFRESH_TOKEN, token_type_hint: "refresh_token" }
    });
    expect(readUsers(deps.usersFile)).toEqual([]);
  });

  it("behaelt den neuesten Refresh-Token", async () => {
    let n = 0;
    const apple = fakeApple({ [APPLE_TOKEN_URL]: async () => ({ status: 200, body: { refresh_token: `r-${++n}` } }) });
    const { app, deps } = setup({ appleRevoker: revoker(apple.post) });

    await request(app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "c1" });
    await waitFor(() => record(deps)?.apple_refresh_token === "r-1");
    await request(app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "c2" });
    await waitFor(() => record(deps)?.apple_refresh_token === "r-2");
  });

  it("ohne Schluessel: kein Aufruf bei Apple, Anmelden und Loeschen wie bisher", async () => {
    const { app, deps } = setup();

    const signIn = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "einmal-code" });
    expect(signIn.status).toBe(200);
    expect(record(deps).apple_refresh_token).toBeUndefined();

    const deleted = await request(app).delete("/v1/account").set("Authorization", `Bearer ${signIn.body.token}`);
    expect(deleted.status).toBe(204);
    expect(readUsers(deps.usersFile)).toEqual([]);
  });

  it("ohne Code oder ohne gespeicherten Token: kein Aufruf bei Apple", async () => {
    const apple = fakeApple();
    const { app, deps } = setup({ appleRevoker: revoker(apple.post) });

    const signIn = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken() });
    const deleted = await request(app).delete("/v1/account").set("Authorization", `Bearer ${signIn.body.token}`);

    expect(deleted.status).toBe(204);
    expect(apple.calls).toEqual([]);
    expect(readUsers(deps.usersFile)).toEqual([]);
  });

  it("Fehler bei Apple stoeren weder Anmelden noch Loeschen", async () => {
    let tokenCalls = 0;
    const failing = fakeApple({
      [APPLE_TOKEN_URL]: async () => {
        tokenCalls += 1;
        return { status: 400, body: { error: "invalid_grant" } };
      }
    });
    const first = setup({ appleRevoker: revoker(failing.post) });
    const signIn = await request(first.app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "c" });
    expect(signIn.status).toBe(200);
    await waitFor(() => tokenCalls === 1);
    expect(record(first.deps).apple_refresh_token).toBeUndefined();

    const revokeFails = fakeApple({ [APPLE_REVOKE_URL]: async () => Promise.reject(new Error("offline")) });
    const second = setup({ appleRevoker: revoker(revokeFails.post) });
    const session = await request(second.app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "c" });
    await waitFor(() => record(second.deps)?.apple_refresh_token !== undefined);
    const deleted = await request(second.app).delete("/v1/account").set("Authorization", `Bearer ${session.body.token}`);

    expect(deleted.status).toBe(204);
    expect(revokeFails.calls.map((call) => call.url)).toEqual([APPLE_TOKEN_URL, APPLE_REVOKE_URL]);
    expect(readUsers(second.deps.usersFile)).toEqual([]);
  });

  it("widerruft sofort, wenn das Konto vor dem Tausch schon geloescht ist", async () => {
    let releaseExchange: () => void = () => {};
    const exchangeGate = new Promise<void>((resolve) => (releaseExchange = resolve));
    const apple = fakeApple({
      [APPLE_TOKEN_URL]: async () => {
        await exchangeGate;
        return { status: 200, body: { refresh_token: REFRESH_TOKEN } };
      }
    });
    const { app, deps } = setup({ appleRevoker: revoker(apple.post) });

    const signIn = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "c" });
    await request(app).delete("/v1/account").set("Authorization", `Bearer ${signIn.body.token}`);
    releaseExchange();

    await waitFor(() => apple.calls.some((call) => call.url === APPLE_REVOKE_URL));
    expect(apple.calls.find((call) => call.url === APPLE_REVOKE_URL)?.form.token).toBe(REFRESH_TOKEN);
    expect(readUsers(deps.usersFile)).toEqual([]);
  });

  it("zeigt den Refresh-Token weder in der CLI noch in der Admin-Route", async () => {
    const { app, dir, deps } = setup({ appleRevoker: revoker(fakeApple().post) });
    await request(app).post("/v1/auth/apple").send({ identityToken: identityToken(), authorizationCode: "c" });
    await waitFor(() => record(deps)?.apple_refresh_token !== undefined);

    const lines: string[] = [];
    expect(run(["list"], dir, (line) => lines.push(line))).toBe(0);
    expect(run(["pending"], dir, (line) => lines.push(line))).toBe(0);
    const admin = await request(app).get("/v1/admin/users").set("Authorization", `Bearer ${TEST_TOKEN}`);

    expect(lines.join("\n")).not.toContain(REFRESH_TOKEN);
    expect(admin.status).toBe(200);
    expect(JSON.stringify(admin.body)).not.toContain(REFRESH_TOKEN);
  });
});
