import { NextFunction, Request, Response, Router } from "express";
import { z } from "zod";
import { PlanUnavailableError } from "../errors";
import { isRealDate, weekdayIndex } from "../week";
import { asV2, DayRequestV2Schema, MacroRequestV2Schema, MacroWeekTargetV2, ReviseRequestSchema, WeekRequestV2Schema } from "./schemas";
import { DayResultV2, MacroResultV2, MultiPlanService, ReviseResult, WeekResultV2 } from "./service";

/**
 * Plan v2 auf den bisherigen Pfaden: Eine Anfrage mit `plan_version: 2` landet hier, jede andere geht unveraendert an
 * die Routen von v1 weiter (`next()`), so bekommt die alte App weiter ihre Antworten. Deshalb muessen diese Routen vor
 * denen von v1 haengen. Dazu `POST /v1/plan/macro/revise` (Feedback zum Gesamtplan), nur v2.
 */
interface Detail {
  path: string;
  message: string;
}

function invalid(res: Response, details: Detail[]): void {
  res.status(400).json({ error: "invalid_request", details: details.slice(0, 10) });
}

function issues(error: z.ZodError): Detail[] {
  return error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message }));
}

function dateProblems(entries: Array<[string, string]>): Detail[] {
  return entries.filter(([, value]) => !isRealDate(value)).map(([path]) => ({ path, message: "kein gültiger Kalendertag" }));
}

function recentDates(recent: Array<{ date: string }> | undefined): Array<[string, string]> {
  return (recent ?? []).map((entry, index): [string, string] => [`recent_training.${index}.date`, entry.date]);
}

function macroWeekProblems(weeks: MacroWeekTargetV2[] | undefined, prefix: string): Detail[] {
  const problems = dateProblems((weeks ?? []).map((week, index): [string, string] => [`${prefix}.${index}.week_start`, week.week_start]));
  if (problems.length > 0) return problems;
  return (weeks ?? []).flatMap((week, index) => (weekdayIndex(week.week_start) === 0 ? [] : [{ path: `${prefix}.${index}.week_start`, message: "muss ein Montag sein" }]));
}

const isV2 = (req: Request) => typeof req.body === "object" && req.body !== null && (req.body as { plan_version?: unknown }).plan_version === 2;

async function answer<T>(res: Response, work: () => Promise<T>, toJson: (result: T) => unknown): Promise<void> {
  try {
    res.json(toJson(await work()));
  } catch (error) {
    if (error instanceof PlanUnavailableError) {
      res.status(503).json({ error: "plan_unavailable", reason: error.reason });
      return;
    }
    throw error;
  }
}

export function multiRoutes(service: MultiPlanService): (router: Router) => void {
  return (router) => {
    router.post("/plan/today", async (req: Request, res: Response, next: NextFunction) => {
      if (!isV2(req)) return next();
      const parsed = DayRequestV2Schema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = dateProblems(recentDates(data.recent_training));
      if (problems.length > 0) return invalid(res, problems);
      await answer(
        res,
        () =>
          service.planDay({
            snapshot: asV2(data.snapshot),
            regenerate: data.regenerate === true,
            wishes: data.wishes,
            dayTarget: data.day_plan,
            equipment: data.equipment,
            recent: data.recent_training,
            testSettings: data.test_settings
          }),
        dayResponse
      );
    });

    router.post("/plan/week", async (req: Request, res: Response, next: NextFunction) => {
      if (!isV2(req)) return next();
      const parsed = WeekRequestV2Schema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = [
        ...dateProblems([
          ["from_date", data.from_date],
          ["today", data.today],
          ...(data.unavailable_dates ?? []).map((date, index): [string, string] => [`unavailable_dates.${index}`, date]),
          ...recentDates(data.recent_training)
        ]),
        ...macroWeekProblems(data.macro_weeks, "macro_weeks")
      ];
      if (problems.length > 0) return invalid(res, problems);
      await answer(
        res,
        () =>
          service.planWeek({
            snapshot: asV2(data.snapshot),
            fromDate: data.from_date,
            today: data.today,
            unavailable: data.unavailable_dates ?? [],
            recent: data.recent_training ?? [],
            macroWeeks: data.macro_weeks,
            wishes: data.wishes,
            equipment: data.equipment,
            testSettings: data.test_settings
          }),
        weekResponse
      );
    });

    router.post("/plan/macro", async (req: Request, res: Response, next: NextFunction) => {
      if (!isV2(req)) return next();
      const parsed = MacroRequestV2Schema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = dateProblems([["today", data.today]]);
      if (problems.length > 0) return invalid(res, problems);
      await answer(res, () => service.planMacro({ snapshot: asV2(data.snapshot), today: data.today, testSettings: data.test_settings }), macroResponse);
    });

    router.post("/plan/macro/revise", async (req: Request, res: Response) => {
      const parsed = ReviseRequestSchema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = [...dateProblems([["today", data.today]]), ...macroWeekProblems(data.plan.weeks, "plan.weeks")];
      if (problems.length > 0) return invalid(res, problems);
      await answer(
        res,
        () =>
          service.reviseMacro({
            snapshot: asV2(data.snapshot),
            today: data.today,
            plan: data.plan,
            feedback: data.feedback,
            history: data.history ?? [],
            testSettings: data.test_settings
          }),
        reviseResponse
      );
    });
  };
}

function dayResponse(result: DayResultV2) {
  return {
    plan_version: 2,
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

function weekResponse(result: WeekResultV2) {
  return {
    plan_version: 2,
    from_date: result.fromDate,
    generated_at: result.generatedAt,
    plan: result.plan,
    adjustments: result.adjustments,
    ...(result.wishes !== undefined ? { wishes: result.wishes } : {})
  };
}

function macroResponse(result: MacroResultV2) {
  return { plan_version: 2, goal_day: result.goalDay, generated_at: result.generatedAt, plan: result.plan, adjustments: result.adjustments };
}

function reviseResponse(result: ReviseResult) {
  return { ...macroResponse(result), changes: result.changes, feedback: result.feedback };
}
