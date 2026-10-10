import { generateKeyPairSync, KeyObject, sign } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import request from "supertest";
import { accountRoutes, AccountDeps, authRoutes, RateLimiter } from "../../src/account";
import { AppleIdentityVerifier, AppleKeysUnavailableError, AppleTokenError, Jwk } from "../../src/apple";
import { run } from "../../src/cli/users";
import { createApp } from "../../src/app";
import { createLogger } from "../../src/logger";
import {
  addUser,
  appleUserId,
  FileUserDirectory,
  MAX_SESSIONS,
  OWNER_ID,
  readUsers,
  rotateUser,
  setUserDisabled,
  sha256Hex,
  signInWithApple,
  USER_ID_PATTERN,
  userDataDir,
  USERS_FILE
} from "../../src/users";
import { TEST_TOKEN, testConfig } from "../helpers";

const BUNDLE_ID = "com.kellner.SwimInstructor";
const NOW = Date.parse("2026-10-09T10:00:00Z");

function tempDir(): string {
  return mkdtempSync(path.join(tmpdir(), "account-"));
}

/** Ein lokal erzeugter RSA-Schluessel spielt Apple. */
const apple = (() => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = { ...(publicKey.export({ format: "jwk" }) as Jwk), kid: "test-kid", alg: "RS256", use: "sig" };
  return { privateKey, jwk };
})();

function jwt(payload: Record<string, unknown>, options: { kid?: string; alg?: string; key?: KeyObject } = {}): string {
  const header = Buffer.from(JSON.stringify({ alg: options.alg ?? "RS256", kid: options.kid ?? "test-kid" })).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = sign("RSA-SHA256", Buffer.from(`${header}.${body}`), options.key ?? apple.privateKey).toString("base64url");
  return `${header}.${body}.${signature}`;
}

function identityToken(overrides: Record<string, unknown> = {}): string {
  return jwt({
    iss: "https://appleid.apple.com",
    aud: BUNDLE_ID,
    sub: "001234.abcdef.1234",
    email: "x@privaterelay.appleid.com",
    iat: Math.floor(NOW / 1000) - 10,
    exp: Math.floor(NOW / 1000) + 600,
    ...overrides
  });
}

function verifier(fetchJwks = async () => ({ keys: [apple.jwk] }), now = () => NOW): AppleIdentityVerifier {
  return new AppleIdentityVerifier({ bundleIds: [BUNDLE_ID], fetchJwks, now });
}

describe("Apple-Identitaetstoken", () => {
  it("nimmt ein gueltiges Token an und liefert sub und E-Mail", async () => {
    await expect(verifier().verify(identityToken())).resolves.toEqual({ sub: "001234.abcdef.1234", email: "x@privaterelay.appleid.com" });
  });

  it("nimmt auch aud als Liste an", async () => {
    await expect(verifier().verify(identityToken({ aud: ["andere.app", BUNDLE_ID] }))).resolves.toMatchObject({ sub: "001234.abcdef.1234" });
  });

  it.each([
    ["falscher Aussteller", { iss: "https://evil.example" }],
    ["falsche Bundle-ID", { aud: "com.example.other" }],
    ["abgelaufen", { exp: Math.floor(NOW / 1000) - 3600 }],
    ["ohne sub", { sub: undefined }],
    ["leeres sub", { sub: "" }],
    ["aus der Zukunft", { iat: Math.floor(NOW / 1000) + 3600 }]
  ])("lehnt ab: %s", async (_name, overrides) => {
    await expect(verifier().verify(identityToken(overrides))).rejects.toBeInstanceOf(AppleTokenError);
  });

  it("lehnt fremde Signatur, anderen Algorithmus, unbekannte kid und Unsinn ab", async () => {
    const other = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
    const payload = { iss: "https://appleid.apple.com", aud: BUNDLE_ID, sub: "s", exp: Math.floor(NOW / 1000) + 600 };
    const v = verifier();

    await expect(v.verify(jwt(payload, { key: other }))).rejects.toBeInstanceOf(AppleTokenError);
    await expect(v.verify(jwt(payload, { alg: "HS256" }))).rejects.toBeInstanceOf(AppleTokenError);
    await expect(v.verify(jwt(payload, { kid: "unbekannt" }))).rejects.toBeInstanceOf(AppleTokenError);
    await expect(v.verify("kein.jwt")).rejects.toBeInstanceOf(AppleTokenError);
    await expect(v.verify("a.b.c")).rejects.toBeInstanceOf(AppleTokenError);
    // Manipulierter Inhalt mit alter Signatur.
    const [header, , signature] = identityToken().split(".");
    const forged = Buffer.from(JSON.stringify({ ...payload, sub: "jemand-anders" })).toString("base64url");
    await expect(v.verify(`${header}.${forged}.${signature}`)).rejects.toBeInstanceOf(AppleTokenError);
  });

  it("laedt die Schluessel einmal und erst nach Ablauf oder bei neuer kid wieder", async () => {
    let now = NOW;
    const fetchJwks = jest.fn(async () => ({ keys: [apple.jwk] }));
    const v = verifier(fetchJwks, () => now);

    await v.verify(identityToken());
    await v.verify(identityToken());
    expect(fetchJwks).toHaveBeenCalledTimes(1);

    // Unbekannte kid: neu laden, aber hoechstens einmal je Minute.
    await expect(v.verify(jwt({}, { kid: "neu" }))).rejects.toBeInstanceOf(AppleTokenError);
    expect(fetchJwks).toHaveBeenCalledTimes(1);
    now += 2 * 60_000;
    await expect(v.verify(jwt({}, { kid: "neu" }))).rejects.toBeInstanceOf(AppleTokenError);
    expect(fetchJwks).toHaveBeenCalledTimes(2);
  });

  it("meldet nicht erreichbares Apple als eigenen Fehler, behaelt aber geladene Schluessel", async () => {
    let fail = true;
    let now = NOW;
    const v = verifier(async () => {
      if (fail) throw new Error("offline");
      return { keys: [apple.jwk] };
    }, () => now);

    await expect(v.verify(identityToken())).rejects.toBeInstanceOf(AppleKeysUnavailableError);
    fail = false;
    now += 2 * 60_000;
    await expect(v.verify(identityToken({ exp: Math.floor(now / 1000) + 600 }))).resolves.toBeDefined();
    fail = true;
    now += 2 * 24 * 60 * 60_000;
    await expect(v.verify(identityToken({ exp: Math.floor(now / 1000) + 600, iat: Math.floor(now / 1000) }))).resolves.toBeDefined();
  });
});

describe("Mit Apple anmelden: users.json", () => {
  it("legt den Nutzer mit abgeleiteter Kennung an und findet ihn wieder, eine Sitzung je Anmeldung", () => {
    const file = path.join(tempDir(), USERS_FILE);
    const first = signInWithApple(file, { sub: "sub-1", email: "a@example.test" }, { name: "Anna", signupOpen: true });
    const second = signInWithApple(file, { sub: "sub-1" }, { signupOpen: true });

    expect(first.status).toBe("ok");
    expect(first.created).toBe(true);
    expect(second.created).toBe(false);
    expect(first.user.id).toMatch(USER_ID_PATTERN);
    expect(first.user.id).toMatch(/^a-[0-9a-f]{12}$/);
    expect(second.user.id).toBe(first.user.id);
    const [record] = readUsers(file);
    expect(record).toMatchObject({ name: "Anna", apple_sub: "sub-1", email: "a@example.test" });
    expect(record.token_sha256).toBeUndefined();
    expect(record.token_sha256s).toHaveLength(2);
    if (first.status === "ok" && second.status === "ok") {
      expect(record.token_sha256s).toEqual([sha256Hex(first.token), sha256Hex(second.token)]);
    }
  });

  it("behaelt hoechstens MAX_SESSIONS Sitzungen", () => {
    const file = path.join(tempDir(), USERS_FILE);
    for (let i = 0; i < MAX_SESSIONS + 3; i++) signInWithApple(file, { sub: "s" }, { signupOpen: true });
    expect(readUsers(file)[0].token_sha256s).toHaveLength(MAX_SESSIONS);
  });

  it("legt bei geschlossener Anmeldung gesperrt an und gibt keinen Token", () => {
    const file = path.join(tempDir(), USERS_FILE);
    const result = signInWithApple(file, { sub: "s" }, { signupOpen: false });

    expect(result.status).toBe("disabled");
    expect(readUsers(file)[0]).toMatchObject({ disabled: true });
    expect(readUsers(file)[0].token_sha256s).toBeUndefined();

    setUserDisabled(file, result.user.id, false);
    expect(signInWithApple(file, { sub: "s" }, { signupOpen: false }).status).toBe("ok");
  });

  it("weicht bei vergebener Kennung auf eine laengere aus", () => {
    const short = appleUserId("x", () => false);
    expect(appleUserId("x", (id) => id === short)).not.toBe(short);
    expect(appleUserId("x", (id) => id === short)).toMatch(USER_ID_PATTERN);
  });

  it("vertraegt alte Eintraege mit token_sha256 und rotate beendet alle Sitzungen", () => {
    const dir = tempDir();
    const file = path.join(dir, USERS_FILE);
    const { token: manual } = addUser(file, "anna");
    const apple = signInWithApple(file, { sub: "s" }, { signupOpen: true });
    const directory = new FileUserDirectory(TEST_TOKEN, dir, () => {}, 0);

    expect(directory.authenticate(manual)?.id).toBe("anna");
    expect(apple.status === "ok" && directory.authenticate(apple.token)?.id).toBe(apple.user.id);

    const rotated = rotateUser(file, apple.user.id);
    directory.invalidate();
    expect(apple.status === "ok" && directory.authenticate(apple.token)).toBeNull();
    expect(directory.authenticate(rotated)?.id).toBe(apple.user.id);
  });
});

describe("Konto-Routen", () => {
  function setup(overrides: Partial<AccountDeps> = {}) {
    const dir = tempDir();
    const users = new FileUserDirectory(TEST_TOKEN, dir, () => {}, 60_000);
    const deps: AccountDeps = {
      usersFile: path.join(dir, USERS_FILE),
      dataDir: dir,
      verifier: verifier(),
      signupOpen: true,
      onUsersChanged: () => users.invalidate(),
      ...overrides
    };
    const app = createApp(testConfig, createLogger(testConfig), {
      users,
      registerPublicV1Routes: authRoutes(deps),
      registerV1Routes: accountRoutes(deps)
    });
    return { app, dir, deps };
  }

  it("meldet mit Apple an, der Token gilt sofort fuer /v1", async () => {
    const { app } = setup();

    const response = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken(), name: "Anna" });

    expect(response.status).toBe(200);
    expect(response.body.token).toMatch(/^[0-9a-f]{64}$/);
    expect(response.body.user).toEqual({ id: expect.stringMatching(/^a-/), name: "Anna" });
    const status = await request(app).get("/v1/status").set("Authorization", `Bearer ${response.body.token}`);
    expect(status.body).toEqual({ status: "authenticated", user: response.body.user.id });
  });

  it("lehnt ungueltige Tokens mit 401 und kaputte Anfragen mit 400 ab", async () => {
    const { app } = setup();

    const invalid = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken({ aud: "fremd" }) });
    const missing = await request(app).post("/v1/auth/apple").send({});
    const broken = await request(app).post("/v1/auth/apple").set("Content-Type", "application/json").send("{kaputt");

    expect(invalid.status).toBe(401);
    expect(invalid.body).toEqual({ error: "invalid_identity_token" });
    expect(missing.status).toBe(400);
    expect(broken.status).toBe(400);
  });

  it("meldet 503, wenn Apples Schluessel fehlen", async () => {
    const { app } = setup({ verifier: verifier(async () => Promise.reject(new Error("offline"))) });

    const response = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken() });

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: "apple_unavailable" });
  });

  it("legt bei geschlossener Anmeldung gesperrt an (403), der Besitzer gibt per CLI frei", async () => {
    const { app, dir } = setup({ signupOpen: false });

    const closed = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken() });
    expect(closed.status).toBe(403);
    expect(closed.body).toEqual({ error: "signup_closed" });

    const lines: string[] = [];
    expect(run(["pending"], dir, (line) => lines.push(line))).toBe(0);
    const id = lines[0].split("\t")[0];
    expect(run(["enable", id], dir, () => {})).toBe(0);

    const open = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken() });
    expect(open.status).toBe(200);
    expect(open.body.user.id).toBe(id);
  });

  it("begrenzt Anmeldeversuche je IP", async () => {
    const { app } = setup({ rateLimitPerMinute: 2 });

    await request(app).post("/v1/auth/apple").send({});
    await request(app).post("/v1/auth/apple").send({});
    const third = await request(app).post("/v1/auth/apple").send({});

    expect(third.status).toBe(429);
    expect(third.body).toEqual({ error: "rate_limited" });
    expect(Number(third.headers["retry-after"])).toBeGreaterThan(0);
  });

  it("loescht das eigene Konto samt Daten, danach gilt der Token nicht mehr", async () => {
    const { app, dir, deps } = setup();
    const { token: otherToken } = addUser(deps.usersFile, "bert");
    const signIn = await request(app).post("/v1/auth/apple").send({ identityToken: identityToken() });
    const { token, user } = signIn.body as { token: string; user: { id: string } };
    const userDir = userDataDir(dir, user.id);
    mkdirSync(userDir, { recursive: true });
    writeFileSync(path.join(userDir, "plan.json"), "{}");

    const deleted = await request(app).delete("/v1/account").set("Authorization", `Bearer ${token}`);

    expect(deleted.status).toBe(204);
    expect(existsSync(userDir)).toBe(false);
    expect(readUsers(deps.usersFile).map((entry) => entry.id)).toEqual(["bert"]);
    expect((await request(app).get("/v1/status").set("Authorization", `Bearer ${token}`)).status).toBe(401);
    expect((await request(app).get("/v1/status").set("Authorization", `Bearer ${otherToken}`)).status).toBe(200);
    // Das Datenverzeichnis selbst bleibt.
    expect(existsSync(dir)).toBe(true);
  });

  it("laesst den Besitzer sich nicht loeschen (409) und verlangt einen Token", async () => {
    const { app, dir } = setup();

    const owner = await request(app).delete("/v1/account").set("Authorization", `Bearer ${TEST_TOKEN}`);
    const anonymous = await request(app).delete("/v1/account");

    expect(owner.status).toBe(409);
    expect(owner.body).toEqual({ error: "owner_cannot_be_deleted" });
    expect(anonymous.status).toBe(401);
    expect(existsSync(userDataDir(dir, OWNER_ID))).toBe(true);
  });
});

describe("RateLimiter", () => {
  it("erlaubt max Versuche je Fenster und danach wieder", () => {
    let now = 0;
    const limiter = new RateLimiter(2, 60_000, () => now);

    expect(limiter.hit("ip")).toBe(0);
    expect(limiter.hit("ip")).toBe(0);
    expect(limiter.hit("ip")).toBe(60);
    expect(limiter.hit("andere")).toBe(0);
    now = 60_000;
    expect(limiter.hit("ip")).toBe(0);
  });
});
