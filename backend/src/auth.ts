import { RequestHandler } from "express";
import { AuthUser, UserDirectory } from "./users";

/**
 * Prueft `Authorization: Bearer <token>` gegen die Nutzer des Servers (siehe `users.ts`) und legt den Nutzer unter
 * `res.locals.user` ab. Die Tokens werden vor dem Vergleich gehasht, damit `timingSafeEqual` gleich lange Puffer bekommt
 * und die Laenge des Tokens nicht ueber die Antwortzeit verraten wird.
 */
export function requireBearerToken(users: UserDirectory): RequestHandler {
  return (req, res, next) => {
    const header = req.header("authorization");
    const match = header ? /^Bearer\s+(\S+)\s*$/i.exec(header) : null;
    const user = match ? users.authenticate(match[1]) : null;

    if (user === null) {
      res.set("WWW-Authenticate", "Bearer").status(401).json({ error: "unauthorized" });
      return;
    }
    res.locals.user = user;
    next();
  };
}

/** Nur fuer Admins (der Besitzer und Nutzer mit `admin`), nach `requireBearerToken`. */
export const requireAdmin: RequestHandler = (_req, res, next) => {
  if (currentUser(res.locals)?.admin !== true) {
    res.status(403).json({ error: "forbidden" });
    return;
  }
  next();
};

export function currentUser(locals: Record<string, unknown>): AuthUser | undefined {
  return locals.user as AuthUser | undefined;
}
