import { createHash, timingSafeEqual } from "node:crypto";
import { RequestHandler } from "express";

/**
 * Prueft `Authorization: Bearer <token>` gegen den konfigurierten Token. Beide Seiten werden vor
 * dem Vergleich gehasht, damit `timingSafeEqual` gleich lange Puffer bekommt und die Laenge des
 * Tokens nicht ueber die Antwortzeit verraten wird.
 */
export function requireBearerToken(expectedToken: string): RequestHandler {
  const expectedDigest = sha256(expectedToken);

  return (req, res, next) => {
    const header = req.header("authorization");
    const match = header ? /^Bearer\s+(\S+)\s*$/i.exec(header) : null;

    if (!match || !timingSafeEqual(sha256(match[1]), expectedDigest)) {
      res.set("WWW-Authenticate", "Bearer").status(401).json({ error: "unauthorized" });
      return;
    }
    next();
  };
}

function sha256(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}
