import express, { Request, Response, Router } from "express";
import { rmSync } from "node:fs";
import { z } from "zod";
import { AppleIdentityClaims, AppleKeysUnavailableError, AppleTokenError } from "./apple";
import { currentUser } from "./auth";
import { OWNER_ID, readUsers, removeUser, signInWithApple, userDataDir } from "./users";

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
}

const AppleSignInSchema = z.object({
  identityToken: z.string().min(1).max(8_000),
  name: z.string().max(200).optional()
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
    });
  };
}

/** Routen hinter der Token-Pruefung. */
export function accountRoutes(deps: AccountDeps): (router: Router) => void {
  return (router) => {
    router.delete("/account", (req: Request, res: Response) => {
      const user = currentUser(res.locals);
      if (user === undefined) {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
      if (user.id === OWNER_ID) {
        res.status(409).json({ error: "owner_cannot_be_deleted" });
        return;
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
