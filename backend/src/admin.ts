import { Request, Response, Router } from "express";
import { requireAdmin } from "./auth";
import { localDate } from "./plan/calendar";
import { FileUsageLog, lastDays, summarizeUsage } from "./usage";
import { OWNER_ID, readUsers } from "./users";

/**
 * Routen fuer den Betrieb, nur fuer Admins: `GET /v1/admin/usage?days=7` (Anfragen, Ausfaelle, Token, Kosten und Dauer je
 * Tag und Nutzer) und `GET /v1/admin/users` (die Nutzer ohne Token).
 */
export interface AdminDeps {
  usage: FileUsageLog;
  usersFile: string;
  timezone: string;
  now?: () => Date;
}

export const MAX_USAGE_DAYS = 90;

export function adminRoutes(deps: AdminDeps): (router: Router) => void {
  const now = deps.now ?? (() => new Date());
  return (router) => {
    router.get("/admin/usage", requireAdmin, async (req: Request, res: Response) => {
      const raw = typeof req.query.days === "string" ? Number(req.query.days) : 7;
      if (!Number.isInteger(raw) || raw < 1 || raw > MAX_USAGE_DAYS) {
        res.status(400).json({ error: "invalid_request", details: [{ path: "days", message: `ganze Zahl von 1 bis ${MAX_USAGE_DAYS}` }] });
        return;
      }
      const today = localDate(now(), deps.timezone);
      const events = await deps.usage.events(raw);
      res.json({ today, ...summarizeUsage(events, deps.timezone, lastDays(today, raw)) });
    });

    router.get("/admin/users", requireAdmin, (_req: Request, res: Response) => {
      let users;
      try {
        users = readUsers(deps.usersFile);
      } catch {
        res.status(500).json({ error: "users_unreadable" });
        return;
      }
      res.json({
        users: [
          { id: OWNER_ID, name: "Besitzer", admin: true, disabled: false, created_at: null },
          ...users.map((user) => ({ id: user.id, name: user.name, admin: user.admin === true, disabled: user.disabled === true, created_at: user.created_at }))
        ]
      });
    });
  };
}
