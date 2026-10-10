import { createPublicKey, KeyObject, verify } from "node:crypto";

/**
 * Prueft das Identitaetstoken aus "Mit Apple anmelden" (ein JWT, RS256) gegen Apples oeffentliche Schluessel (JWKS):
 * Signatur, Aussteller, Empfaenger (unsere Bundle-ID), Ablauf und Apple-Kennung (`sub`). Nur `node:crypto`, keine
 * weitere Abhaengigkeit: Apple signiert immer mit RS256, mehr JWT-Formen braucht es nicht.
 */
export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

export interface Jwk {
  kty: string;
  kid?: string;
  alg?: string;
  use?: string;
  n?: string;
  e?: string;
}

export type JwksFetcher = () => Promise<{ keys: Jwk[] }>;

export interface AppleIdentityClaims {
  sub: string;
  email?: string;
}

/** Das Token ist ungueltig (Format, Signatur, Aussteller, Empfaenger, Ablauf). */
export class AppleTokenError extends Error {}

/** Apples Schluessel waren nicht zu bekommen: kein Fehler des Nutzers, spaeter erneut versuchen. */
export class AppleKeysUnavailableError extends Error {}

export interface AppleVerifierOptions {
  bundleIds: string[];
  fetchJwks?: JwksFetcher;
  now?: () => number;
  /** So lange gelten die geladenen Schluessel (Apple wechselt sie selten). */
  cacheMs?: number;
  /** Bei unbekannter `kid` hoechstens so oft neu laden, damit gefaelschte Tokens Apple nicht fluten. */
  refetchMinIntervalMs?: number;
}

const CLOCK_SKEW_SECONDS = 60;

export class AppleIdentityVerifier {
  private keys = new Map<string, KeyObject>();
  private fetchedAt = -Infinity;
  private attemptedAt = -Infinity;
  private pending: Promise<void> | undefined;
  private readonly fetchJwks: JwksFetcher;
  private readonly now: () => number;
  private readonly cacheMs: number;
  private readonly refetchMinIntervalMs: number;

  constructor(private readonly options: AppleVerifierOptions) {
    this.fetchJwks = options.fetchJwks ?? fetchAppleJwks;
    this.now = options.now ?? Date.now;
    this.cacheMs = options.cacheMs ?? 24 * 60 * 60 * 1000;
    this.refetchMinIntervalMs = options.refetchMinIntervalMs ?? 60 * 1000;
  }

  async verify(token: string): Promise<AppleIdentityClaims> {
    const parts = token.split(".");
    if (parts.length !== 3 || parts.some((part) => !/^[A-Za-z0-9_-]+$/.test(part))) throw new AppleTokenError("kein JWT");
    const header = decodeJson(parts[0]);
    const payload = decodeJson(parts[1]);
    if (header.alg !== "RS256") throw new AppleTokenError("Algorithmus nicht RS256");
    if (typeof header.kid !== "string" || header.kid === "") throw new AppleTokenError("kid fehlt");

    const key = await this.key(header.kid);
    const signature = Buffer.from(parts[2], "base64url");
    if (!verify("RSA-SHA256", Buffer.from(`${parts[0]}.${parts[1]}`), key, signature)) throw new AppleTokenError("Signatur falsch");

    if (payload.iss !== APPLE_ISSUER) throw new AppleTokenError("Aussteller falsch");
    const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (!audiences.some((aud) => typeof aud === "string" && this.options.bundleIds.includes(aud))) throw new AppleTokenError("Empfaenger falsch");
    const nowSeconds = Math.floor(this.now() / 1000);
    if (typeof payload.exp !== "number" || payload.exp + CLOCK_SKEW_SECONDS < nowSeconds) throw new AppleTokenError("abgelaufen");
    if (typeof payload.iat === "number" && payload.iat - CLOCK_SKEW_SECONDS > nowSeconds) throw new AppleTokenError("aus der Zukunft");
    if (typeof payload.sub !== "string" || payload.sub === "" || payload.sub.length > 255) throw new AppleTokenError("sub fehlt");

    const email = typeof payload.email === "string" && payload.email.length <= 320 ? payload.email : undefined;
    return { sub: payload.sub, ...(email === undefined ? {} : { email }) };
  }

  private async key(kid: string): Promise<KeyObject> {
    const now = this.now();
    const expired = now - this.fetchedAt > this.cacheMs;
    const unknownKid = !this.keys.has(kid);
    if ((expired || unknownKid) && (this.pending !== undefined || now - this.attemptedAt > this.refetchMinIntervalMs)) {
      try {
        await this.refresh();
      } catch (error) {
        // Abgelaufener Cache, aber Apple nicht erreichbar: mit den bekannten Schluesseln weiter.
        if (!this.keys.has(kid)) throw new AppleKeysUnavailableError((error as Error).message);
      }
    }
    const key = this.keys.get(kid);
    if (key === undefined) {
      if (this.keys.size === 0) throw new AppleKeysUnavailableError("noch keine Schluessel von Apple");
      throw new AppleTokenError("Schluessel unbekannt");
    }
    return key;
  }

  private refresh(): Promise<void> {
    // Gleichzeitige Anmeldungen teilen sich einen Abruf.
    this.pending ??= (async () => {
      this.attemptedAt = this.now();
      try {
        const jwks = await this.fetchJwks();
        const keys = new Map<string, KeyObject>();
        for (const jwk of jwks.keys ?? []) {
          if (jwk.kty !== "RSA" || typeof jwk.kid !== "string" || (jwk.alg !== undefined && jwk.alg !== "RS256")) continue;
          try {
            keys.set(jwk.kid, createPublicKey({ key: { kty: jwk.kty, n: jwk.n, e: jwk.e }, format: "jwk" }));
          } catch {
            // Kaputter Schluessel: ueberspringen.
          }
        }
        if (keys.size === 0) throw new Error("JWKS ohne brauchbare Schluessel");
        this.keys = keys;
        this.fetchedAt = this.now();
      } finally {
        this.pending = undefined;
      }
    })();
    return this.pending;
  }
}

function decodeJson(part: string): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
    if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("kein Objekt");
    return value as Record<string, unknown>;
  } catch {
    throw new AppleTokenError("JWT nicht lesbar");
  }
}

/** Laedt Apples Schluessel (fetch aus Node 20, mit Zeitlimit). */
export const fetchAppleJwks: JwksFetcher = async () => {
  const response = await fetch(APPLE_JWKS_URL, { signal: AbortSignal.timeout(5_000) });
  if (!response.ok) throw new Error(`Apple JWKS: Status ${response.status}`);
  return (await response.json()) as { keys: Jwk[] };
};
