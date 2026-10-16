import { createPrivateKey, KeyObject, sign } from "node:crypto";
import { APPLE_ISSUER } from "./apple";

/**
 * Widerruf von "Mit Apple anmelden" beim Loeschen eines Kontos (App Store Richtlinie 5.1.1(v), Apple TN3194):
 * Bei der Anmeldung tauscht der Server den Einmal-Code der App (`authorizationCode`) bei Apple gegen einen
 * Refresh-Token und merkt ihn sich; beim Loeschen widerruft er ihn ueber `/auth/revoke`. Dafuer braucht es einen
 * Schluessel "Sign in with Apple" aus dem Apple-Developer-Konto (`APPLE_SIWA_KEY_ID`, `APPLE_SIWA_PRIVATE_KEY`).
 * Nur `node:crypto` und `fetch`, keine weitere Abhaengigkeit.
 */
export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

export interface AppleRevokeConfig {
  teamId: string;
  keyId: string;
  /** Inhalt der .p8-Datei (PEM, PKCS#8, EC P-256). */
  privateKey: string;
}

export interface AppleFormResponse {
  status: number;
  body: unknown;
}

/** Schickt ein Formular (application/x-www-form-urlencoded) an Apple; in Tests ersetzt. */
export type AppleFormPoster = (url: string, form: URLSearchParams) => Promise<AppleFormResponse>;

/** Apple hat die Anfrage abgelehnt oder war nicht erreichbar. Die Meldung enthaelt nie Tokens. */
export class AppleRevokeError extends Error {}

/** Liest den privaten Schluessel; wirft, wenn er kein EC-P-256-Schluessel ist. */
export function parseSiwaPrivateKey(pem: string): KeyObject {
  const key = createPrivateKey(normalizePem(pem));
  if (key.asymmetricKeyType !== "ec" || key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
    throw new Error("kein EC-P-256-Schluessel");
  }
  return key;
}

/** Aus der Umgebung: `\n` als zwei Zeichen wird zum Zeilenumbruch, umschliessende Anfuehrungszeichen fallen weg. */
export function normalizePem(value: string): string {
  let pem = value.trim();
  if ((pem.startsWith('"') && pem.endsWith('"')) || (pem.startsWith("'") && pem.endsWith("'"))) pem = pem.slice(1, -1);
  return `${pem.replace(/\\r/g, "").replace(/\\n/g, "\n").replace(/\r/g, "").trim()}\n`;
}

export interface AppleRevokerOptions extends AppleRevokeConfig {
  post?: AppleFormPoster;
  now?: () => number;
}

export class AppleRevoker {
  private readonly key: KeyObject;
  private readonly post: AppleFormPoster;
  private readonly now: () => number;

  constructor(private readonly options: AppleRevokerOptions) {
    this.key = parseSiwaPrivateKey(options.privateKey);
    this.post = options.post ?? postAppleForm;
    this.now = options.now ?? Date.now;
  }

  /** client_secret fuer Apple: ein mit dem Schluessel signiertes ES256-JWT, 5 Minuten gueltig. */
  clientSecret(clientId: string): string {
    const iat = Math.floor(this.now() / 1000);
    const header = base64urlJson({ alg: "ES256", kid: this.options.keyId });
    const payload = base64urlJson({ iss: this.options.teamId, iat, exp: iat + 300, aud: APPLE_ISSUER, sub: clientId });
    // JWT verlangt die Signatur als r||s (je 32 Bytes), nicht DER.
    const signature = sign("sha256", Buffer.from(`${header}.${payload}`), { key: this.key, dsaEncoding: "ieee-p1363" });
    return `${header}.${payload}.${signature.toString("base64url")}`;
  }

  /** Tauscht den Einmal-Code der App gegen einen Refresh-Token. */
  async exchangeCode(code: string, clientId: string): Promise<string> {
    const response = await this.send(APPLE_TOKEN_URL, {
      client_id: clientId,
      client_secret: this.clientSecret(clientId),
      code,
      grant_type: "authorization_code"
    });
    const refreshToken = (response.body as { refresh_token?: unknown } | null)?.refresh_token;
    if (typeof refreshToken !== "string" || refreshToken === "" || refreshToken.length > 2_000) {
      throw new AppleRevokeError("Apple token: kein refresh_token in der Antwort");
    }
    return refreshToken;
  }

  /** Widerruft den Refresh-Token und damit die Anmeldung mit Apple fuer diese App. */
  async revoke(refreshToken: string, clientId: string): Promise<void> {
    await this.send(APPLE_REVOKE_URL, {
      client_id: clientId,
      client_secret: this.clientSecret(clientId),
      token: refreshToken,
      token_type_hint: "refresh_token"
    });
  }

  private async send(url: string, fields: Record<string, string>): Promise<AppleFormResponse> {
    let response: AppleFormResponse;
    try {
      response = await this.post(url, new URLSearchParams(fields));
    } catch (error) {
      throw new AppleRevokeError(`${url}: nicht erreichbar (${(error as Error).message})`);
    }
    if (response.status < 200 || response.status > 299) {
      const reason = (response.body as { error?: unknown } | null)?.error;
      throw new AppleRevokeError(`${url}: Status ${response.status}${typeof reason === "string" ? ` (${reason.slice(0, 100)})` : ""}`);
    }
    return response;
  }
}

function base64urlJson(value: Record<string, unknown>): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

/** Formular per fetch (Node 20), mit Zeitlimit. Die Antwort ist JSON oder leer (revoke). */
export const postAppleForm: AppleFormPoster = async (url, form) => {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: form.toString(),
    signal: AbortSignal.timeout(5_000)
  });
  const text = await response.text();
  let body: unknown = null;
  try {
    body = text === "" ? null : JSON.parse(text);
  } catch {
    body = null;
  }
  return { status: response.status, body };
};
