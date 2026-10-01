import { Router } from "express";
import { z } from "zod";
import { PlanUnavailableError } from "./errors";
import { EquipmentListSchema } from "./plan";
import { PlanResult, PlanService } from "./service";
import { SnapshotSchema } from "./snapshot";
import { DayTargetSchema } from "./week";

export const MAX_WISH_LENGTH = 500;

/**
 * `regenerate`: Claude auch dann neu fragen, wenn fuer denselben Zustand heute schon ein Plan vorliegt
 * (Ziehen in der App). `wishes`: Freitext des Athleten fuer heute, hoechstens 500 Zeichen. Leer oder
 * nur Leerraum zaehlt als kein Wunsch.
 */
const PlanRequestSchema = z.object({
  snapshot: SnapshotSchema,
  regenerate: z.boolean().optional(),
  wishes: z.string().max(MAX_WISH_LENGTH).optional(),
  /** Vorgabe des Wochenplans fuer heute (Typ, Intensitaet, Umfang, Schwerpunkt). */
  day_plan: DayTargetSchema.optional(),
  /** Das Equipment, das der Athlet hat. Fehlt das Feld, ist jedes erlaubt; leer heisst: keins. */
  equipment: EquipmentListSchema.optional()
});

/** Haengt `POST /v1/plan/today` ein (die Token-Pruefung sitzt schon davor, siehe app.ts). */
export function planRoutes(service: PlanService): (router: Router) => void {
  return (router) => {
    router.post("/plan/today", async (req, res) => {
      const parsed = PlanRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: "invalid_request",
          details: parsed.error.issues.slice(0, 10).map((issue) => ({ path: issue.path.join("."), message: issue.message }))
        });
        return;
      }

      try {
        res.json(toResponse(await service.planForToday(parsed.data.snapshot, { regenerate: parsed.data.regenerate === true, wishes: parsed.data.wishes, dayTarget: parsed.data.day_plan, equipment: parsed.data.equipment })));
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

function toResponse(result: PlanResult) {
  return {
    source: result.source,
    date: result.date,
    generated_at: result.generatedAt,
    stale: result.stale,
    plan: result.plan,
    adjustments: result.adjustments,
    ...(result.fallbackReason !== undefined ? { fallback_reason: result.fallbackReason } : {}),
    ...(result.wishes !== undefined ? { wishes: result.wishes } : {})
  };
}
