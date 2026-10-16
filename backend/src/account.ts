import express, { Request, Response, Router } from "express";
import { rmSync } from "node:fs";
import { z } from "zod";
import { AppleIdentityClaims, AppleKeysUnavailableError, AppleTokenError } from "./apple";
import { currentUser } from "./auth";
import { OWNER_ID, readUsers, removeUser, setAppleRefreshToken, signInWithApple, userDataDir } from "./users";

/**
 * Konto: Anmeldung mit Apple (`POST /v1/auth/apple`, oeffentlich) und Loeschen des eigenen Kontos
 * (`DELETE /v1/account`, mit Token; Apple verlangt die Loeschung in der App).
 */
export interface AccountDeps {
  usersFile: string;
  dataDir: string;
  verifier: { verify(token: string): Promise<AppleIdentityClaims> };
  signupOpen: boolean;
  /** Nach jeder Aenderung von `users.json`, damit der neue Token sofort gilt (`UserDirectory.invalidate`). */
  onUsersChanged?: () => void;
  /** Anmeldeversuche je IP und Minute. */
  rateLimitPerMinute?: number;
  now?: () => number;
  /**
   * Widerruf der Apple-Anmeldung beim Loeschen (`AppleRevoker`); ohne ihn (kein Schluessel konfiguriert) wird nur
   * geloescht und eine Warnung geloggt.
   */
  appleRevoker?: {
    exchangeCode(code: string, clientId: string): Promise<string>;
    revoke(refreshToken: string, clientId: string): Promise<void>;
  };
  /** client_id fuer Apple, wenn das Identitaetstoken keine Bundle-ID nennt: die erste aus `APPLE_BUNDLE_IDS`. */
  appleClientId?: string;
}

const AppleSignInSchema = z.object({
  identityToken: z.string().min(1).max(8_000),
  name: z.string().max(200).optional(),
  /** Einmal-Code von Apple, nur fuer den spaeteren Widerruf beim Loeschen. */
  authorizationCode: z.string().min(1).max(2_000).optional()
});

/** Oeffentliche Routen unter /v1, vor der Token-Pruefung. */
export function authRoutes(deps: AccountDeps): (router: Router) => void {
  const limiter = new RateLimiter(deps.rateLimitPerMinute ?? 20, 60_000, deps.now ?? Date.now);
  return (router) => {
    router.post("/auth/apple", (req, res, next) => {
      const retryAfter = limiter.hit(req.ip ?? "unknown");
      if (retryAfter > 0) {
        res.set("Retry-After", String(retryAfter)).status(429).json({ error: "rate_limited" });
        return;
      }
      next();
    }, express.json({ limit: "16kb" }), async (req: Request, res: Response) => {
      const parsed = AppleSignInSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: "invalid_request" });
        return;
      }
      let identity: AppleIdentityClaims;
      try {
        identity = await deps.verifier.verify(parsed.data.identityToken);
      } catch (error) {
        if (error instanceof AppleKeysUnavailableError) {
          req.log.warn({ err: error }, "apple keys unavailable");
          res.status(503).json({ error: "apple_unavailable" });
          return;
        }
        if (error instanceof AppleTokenError) {
          req.log.warn({ reason: error.message }, "apple identity token rejected");
          res.status(401).json({ error: "invalid_identity_token" });
          return;
        }
        throw error;
      }

      const result = signInWithApple(deps.usersFile, identity, { name: parsed.data.name, signupOpen: deps.signupOpen });
      deps.onUsersChanged?.();
      req.log.info({ user: result.user.id, created: result.created, status: result.status }, "apple sign in");
      if (result.status === "disabled") {
        res.status(403).json({ error: "signup_closed" });
        return;
      }
      res.json({ token: result.token, user: { id: result.user.id, name: result.user.name } });

      // Erst nach der Antwort, damit die Anmeldung schnell bleibt; ein Fehler bei Apple stoert sie nicht.
      const code = parsed.data.authorizationCode;
      const clientId = identity.audience ?? deps.appleClientId;
      if (code !== undefined && deps.appleRevoker !== undefined && clientId !== undefined) {
        void storeAppleRefreshToken(deps, deps.appleRevoker, result.user.id, code, clientId, req.log);
      }
    });
  };
}

/** Routen hinter der Token-Pruefung. */
export function accountRoutes(deps: AccountDeps): (router: Router) => void {
  return (router) => {
    router.delete("/account", async (req: Request, res: Response) => {
      const user = currentUser(res.locals);
      if (user === undefined) {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
      if (user.id === OWNER_ID) {
        res.status(409).json({ error: "owner_cannot_be_deleted" });
        return;
      }
      const record = readUsers(deps.usersFile).find((entry) => entry.id === user.id);
      if (record?.apple_sub !== undefined) {
        // Apple verlangt, die Anmeldung mit Apple beim Loeschen zu widerrufen (TN3194). Scheitert das, wird trotzdem geloescht.
        if (deps.appleRevoker === undefined) {
          req.log.warn({ user: user.id }, "apple revoke skipped: no key");
        } else if (record.apple_refresh_token === undefined) {
          req.log.warn({ user: user.id }, "apple revoke skipped: no refresh token");
        } else {
          const clientId = record.apple_client_id ?? deps.appleClientId;
          try {
            if (clientId === undefined) throw new Error("keine client_id");
            await deps.appleRevoker.revoke(record.apple_refresh_token, clientId);
            req.log.info({ user: user.id }, "apple sign in revoked");
          } catch (error) {
            req.log.warn({ user: user.id, reason: (error as Error).message }, "apple revoke failed");
          }
        }
      }
      if (readUsers(deps.usersFile).some((entry) => entry.id === user.id)) {
        removeUser(deps.usersFile, user.id);
      }
      deps.onUsersChanged?.();
      // Die Kennung passt zu USER_ID_PATTERN und ist nicht der Besitzer: der Ordner liegt sicher unter users/.
      rmSync(userDataDir(deps.dataDir, user.id), { recursive: true, force: true });
      req.log.info({ user: user.id }, "account deleted");
      res.status(204).end();
    });
  };
}

/**
 * Tauscht den Einmal-Code gegen Apples Refresh-Token und legt ihn beim Nutzer ab. Gibt es den Nutzer inzwischen nicht
 * mehr, wird der Token gleich widerrufen. Wirft nie; der Token selbst landet in keinem Log.
 */
export async function storeAppleRefreshToken(
  deps: Pick<AccountDeps, "usersFile">,
  revoker: NonNullable<AccountDeps["appleRevoker"]>,
  userId: string,
  code: string,
  clientId: string,
  log: { info(obj: object, msg: string): void; warn(obj: object, msg: string): void }
): Promise<void> {
  try {
    const refreshToken = await revoker.exchangeCode(code, clientId);
    if (setAppleRefreshToken(deps.usersFile, userId, refreshToken, clientId)) {
      log.info({ user: userId }, "apple refresh token stored");
    } else {
      await revoker.revoke(refreshToken, clientId);
      log.info({ user: userId }, "apple sign in revoked (account already deleted)");
    }
  } catch (error) {
    log.warn({ user: userId, reason: (error as Error).message }, "apple token exchange failed");
  }
}

/** Einfaches festes Fenster je Schluessel (IP), nur im Speicher. */
export class RateLimiter {
  private readonly windows = new Map<string, { start: number; count: number }>();

  constructor(
    private readonly max: number,
    private readonly windowMs: number,
    private readonly now: () => number = Date.now
  ) {}

  /** 0, wenn erlaubt; sonst Sekunden bis zum naechsten Versuch. */
  hit(key: string): number {
    const now = this.now();
    if (this.windows.size > 10_000) this.prune(now);
    const window = this.windows.get(key);
    if (window === undefined || now - window.start >= this.windowMs) {
      this.windows.set(key, { start: now, count: 1 });
      return 0;
    }
    window.count += 1;
    if (window.count <= this.max) return 0;
    return Math.max(1, Math.ceil((window.start + this.windowMs - now) / 1000));
  }

  private prune(now: number): void {
    for (const [key, window] of this.windows) {
      if (now - window.start >= this.windowMs) this.windows.delete(key);
    }
  }
}
