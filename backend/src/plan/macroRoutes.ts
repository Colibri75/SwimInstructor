import { Router } from "express";
import { z } from "zod";
import { PlanUnavailableError } from "./errors";
import { MacroPlanService, MacroResult } from "./macroService";
import { SnapshotSchema } from "./snapshot";
import { DATE_PATTERN, isRealDate } from "./week";

const MacroRequestSchema = z.object({
  snapshot: SnapshotSchema,
  /** Heute beim Athleten. */
  today: z.string().regex(DATE_PATTERN)
});

/** Haengt `POST /v1/plan/macro` ein (die Token-Pruefung sitzt schon davor, siehe app.ts). */
export function macroRoutes(service: MacroPlanService): (router: Router) => void {
  return (router) => {
    router.post("/plan/macro", async (req, res) => {
      const parsed = MacroRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: "invalid_request",
          details: parsed.error.issues.slice(0, 10).map((issue) => ({ path: issue.path.join("."), message: issue.message }))
        });
        return;
      }
      if (!isRealDate(parsed.data.today)) {
        res.status(400).json({ error: "invalid_request", details: [{ path: "today", message: "kein gültiger Kalendertag" }] });
        return;
      }

      try {
        res.json(toResponse(await service.planMacro({ snapshot: parsed.data.snapshot, today: parsed.data.today })));
      } catch (error) {
        if (error instanceof PlanUnavailableError) {
          res.status(503).json({ error: "plan_unavailable", reason: error.reason });
          return;
        }
        throw error;
      }
    });
  };
}

function toResponse(result: MacroResult) {
  return {
    goal_day: result.goalDay,
    generated_at: result.generatedAt,
    plan: result.plan,
    adjustments: result.adjustments
  };
}
