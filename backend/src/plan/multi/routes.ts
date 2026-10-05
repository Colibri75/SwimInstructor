import { Request, Response, Router } from "express";
import { currentUser } from "../../auth";
import { OWNER_ID } from "../../users";
import { z } from "zod";
import { PlanUnavailableError } from "../errors";
import { isRealDate, weekdayIndex } from "../calendar";
import { DayRequestV2Schema, MacroRequestV2Schema, MacroWeekTargetV2, ReviewRequestSchema, ReviseRequestSchema, WeekRequestV2Schema } from "./schemas";
import { DayResultV2, MacroResultV2, MultiPlanService, RaceResult, ReviewResult, ReviseResult, WeekResultV2 } from "./service";
import { raceBlockedReason, RaceRequestSchema } from "./race";

/**
 * Die Routen der Planung (Plan v2, siehe docs/multisport-planning.md): `POST /v1/plan/today`, `/plan/week`, `/plan/macro`
 * (der Pfad `/v1` ist die Version der HTTP-Schnittstelle) sowie `/plan/macro/revise` (Feedback zum Gesamtplan) und
 * `/plan/macro/review` (Fortschreibung alle zwei Wochen). Jede Anfrage nennt `plan_version: 2`.
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

function userOf(res: Response): string {
  return currentUser(res.locals)?.id ?? OWNER_ID;
}

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
    router.post("/plan/today", async (req: Request, res: Response) => {
      const parsed = DayRequestV2Schema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = dateProblems(recentDates(data.recent_training));
      if (problems.length > 0) return invalid(res, problems);
      await answer(
        res,
        () =>
          service.planDay({
            user: userOf(res),
            snapshot: data.snapshot,
            regenerate: data.regenerate === true,
            wishes: data.wishes,
            dayTarget: data.day_plan,
            equipment: data.equipment,
            recent: data.recent_training,
            testSettings: data.test_settings,
            supplements: data.supplements,
            location: data.location,
            availableMinutes: data.available_minutes
          }),
        dayResponse
      );
    });

    router.post("/plan/week", async (req: Request, res: Response) => {
      const parsed = WeekRequestV2Schema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = [
        ...dateProblems([
          ["from_date", data.from_date],
          ["today", data.today],
          ...(data.unavailable_dates ?? []).map((date, index): [string, string] => [`unavailable_dates.${index}`, date]),
          ...recentDates(data.recent_training),
          ...(data.availability ?? []).map((entry, index): [string, string] => [`availability.${index}.date`, entry.date]),
          ...(data.missed_sessions ?? []).map((entry, index): [string, string] => [`missed_sessions.${index}.date`, entry.date])
        ]),
        ...macroWeekProblems(data.macro_weeks, "macro_weeks")
      ];
      if (problems.length > 0) return invalid(res, problems);
      await answer(
        res,
        () =>
          service.planWeek({
            user: userOf(res),
            snapshot: data.snapshot,
            fromDate: data.from_date,
            today: data.today,
            unavailable: data.unavailable_dates ?? [],
            recent: data.recent_training ?? [],
            missed: data.missed_sessions,
            reason: data.reason,
            macroWeeks: data.macro_weeks,
            wishes: data.wishes,
            equipment: data.equipment,
            testSettings: data.test_settings,
            supplements: data.supplements,
            location: data.location,
            availability: data.availability
          }),
        weekResponse
      );
    });

    router.post("/plan/macro", async (req: Request, res: Response) => {
      const parsed = MacroRequestV2Schema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = dateProblems([["today", data.today]]);
      if (problems.length > 0) return invalid(res, problems);
      await answer(res, () => service.planMacro({ user: userOf(res), snapshot: data.snapshot, today: data.today, testSettings: data.test_settings }), macroResponse);
    });

    router.post("/plan/race", async (req: Request, res: Response) => {
      const parsed = RaceRequestSchema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = dateProblems([["today", data.today]]);
      if (problems.length > 0) return invalid(res, problems);
      const blocked = raceBlockedReason(data.snapshot);
      if (blocked !== null) return invalid(res, [{ path: "snapshot.training_goal", message: blocked }]);
      await answer(
        res,
        () =>
          service.planRace({
            user: userOf(res),
            snapshot: data.snapshot,
            today: data.today,
            startTime: data.start_time,
            location: data.location,
            bodyWeightKg: data.body_weight_kg,
            notes: data.notes
          }),
        raceResponse
      );
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
            user: userOf(res),
            snapshot: data.snapshot,
            today: data.today,
            plan: data.plan,
            feedback: data.feedback,
            history: data.history ?? [],
            testSettings: data.test_settings
          }),
        reviseResponse
      );
    });

    router.post("/plan/macro/review", async (req: Request, res: Response) => {
      const parsed = ReviewRequestSchema.safeParse(req.body);
      if (!parsed.success) return invalid(res, issues(parsed.error));
      const data = parsed.data;
      const problems = [
        ...dateProblems([["today", data.today]]),
        ...dateProblems(data.pause ? [["pause.from", data.pause.from], ...(data.pause.to ? ([["pause.to", data.pause.to]] as Array<[string, string]>) : [])] : []),
        ...macroWeekProblems(data.plan.weeks, "plan.weeks"),
        ...dateProblems(data.actual.map((week, index): [string, string] => [`actual.${index}.week_start`, week.week_start]))
      ];
      if (problems.length > 0) return invalid(res, problems);
      await answer(
        res,
        () =>
          service.reviewMacro({
            user: userOf(res),
            snapshot: data.snapshot,
            today: data.today,
            plan: data.plan,
            actual: data.actual,
            reason: data.reason,
            pause: data.pause,
            feedback: data.feedback,
            performanceChanges: data.performance_changes,
            testSettings: data.test_settings
          }),
        reviewResponse
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

function raceResponse(result: RaceResult) {
  return {
    plan_version: 2,
    race_day: result.raceDay,
    generated_at: result.generatedAt,
    plan: result.plan,
    adjustments: result.adjustments,
    ...(result.weather !== undefined ? { weather: result.weather } : {})
  };
}

function reviseResponse(result: ReviseResult) {
  return { ...macroResponse(result), changes: result.changes, feedback: result.feedback };
}

function reviewResponse(result: ReviewResult) {
  return {
    ...macroResponse(result),
    summary: result.summary,
    changes: result.changes,
    reason: result.reason,
    ...(result.feedback !== undefined ? { feedback: result.feedback } : {})
  };
}
