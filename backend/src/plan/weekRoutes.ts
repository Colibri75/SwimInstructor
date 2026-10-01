import { Router } from "express";
import { z } from "zod";
import { PlanUnavailableError } from "./errors";
import { SnapshotSchema } from "./snapshot";
import { addDays, DATE_PATTERN, isRealDate, weekdayIndex } from "./week";
import { MAX_WISH_LENGTH } from "./routes";
import { WeekPlanService, WeekResult } from "./weekService";

const DateString = z.string().regex(DATE_PATTERN);

const WeekRequestSchema = z.object({
  snapshot: SnapshotSchema,
  /** Montag der Woche. */
  week_start: DateString,
  /** Erster zu planender Tag: heute oder der Montag einer kommenden Woche. */
  from_date: DateString,
  /** Heute beim Athleten. */
  today: DateString,
  unavailable_dates: z.array(DateString).max(7).optional(),
  swum_this_week: z.array(z.object({ date: DateString, meters: z.number().min(0).max(100_000) })).max(7).optional(),
  wishes: z.string().max(MAX_WISH_LENGTH).optional()
});

interface Detail {
  path: string;
  message: string;
}

/** Inhaltliche Pruefungen, die ein Schema nicht kann: echte Kalendertage, Montag, from_date in der Woche. */
function checkDates(data: z.infer<typeof WeekRequestSchema>): Detail[] {
  const problems: Detail[] = [];
  const dates: [string, string][] = [
    ["week_start", data.week_start],
    ["from_date", data.from_date],
    ["today", data.today],
    ...(data.unavailable_dates ?? []).map((date, index): [string, string] => [`unavailable_dates.${index}`, date]),
    ...(data.swum_this_week ?? []).map((day, index): [string, string] => [`swum_this_week.${index}.date`, day.date])
  ];
  for (const [path, value] of dates) {
    if (!isRealDate(value)) problems.push({ path, message: "kein gültiger Kalendertag" });
  }
  if (problems.length > 0) return problems;

  if (weekdayIndex(data.week_start) !== 0) problems.push({ path: "week_start", message: "muss ein Montag sein" });
  if (data.from_date < data.week_start || data.from_date > addDays(data.week_start, 6)) {
    problems.push({ path: "from_date", message: "muss in der Woche liegen" });
  }
  return problems;
}

/** Haengt `POST /v1/plan/week` ein (die Token-Pruefung sitzt schon davor, siehe app.ts). */
export function weekRoutes(service: WeekPlanService): (router: Router) => void {
  return (router) => {
    router.post("/plan/week", async (req, res) => {
      const parsed = WeekRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: "invalid_request",
          details: parsed.error.issues.slice(0, 10).map((issue) => ({ path: issue.path.join("."), message: issue.message }))
        });
        return;
      }
      const problems = checkDates(parsed.data);
      if (problems.length > 0) {
        res.status(400).json({ error: "invalid_request", details: problems.slice(0, 10) });
        return;
      }

      const data = parsed.data;
      try {
        const result = await service.planWeek({
          snapshot: data.snapshot,
          weekStart: data.week_start,
          fromDate: data.from_date,
          today: data.today,
          unavailableDates: data.unavailable_dates ?? [],
          swumThisWeek: data.swum_this_week ?? [],
          wishes: data.wishes
        });
        res.json(toResponse(result));
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

function toResponse(result: WeekResult) {
  return {
    week_start: result.weekStart,
    generated_at: result.generatedAt,
    plan: result.plan,
    adjustments: result.adjustments,
    ...(result.wishes !== undefined ? { wishes: result.wishes } : {})
  };
}
