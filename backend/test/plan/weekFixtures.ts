import { WeekDay, WeekPlan } from "../../src/plan/week";
import { WeekContext } from "../../src/plan/weekSanity";

/** Mittwoch 30.09.2026: Die Woche Mo 28.09. bis So 04.10. */
export const WEEK_START = "2026-09-28";
export const TODAY = "2026-09-30";
export const ALL_DATES = ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"];
/** Ab heute: Mi bis So. */
export const OPEN_DATES = ALL_DATES.slice(2);

export function day(date: string, overrides: Partial<WeekDay> = {}): WeekDay {
  return {
    date,
    session_type: "endurance",
    intensity: "moderate",
    target_distance_meters: 1500,
    estimated_duration_minutes: 40,
    focus: "Ausdauer",
    ...overrides
  };
}

export function rest(date: string): WeekDay {
  return day(date, { session_type: "rest", intensity: "rest", target_distance_meters: 0, estimated_duration_minutes: 0, focus: "Ruhetag" });
}

/** Sinnvolle Woche ab Mittwoch (3600 m, unter der Wochengrenze von 3900 m): Mi 1200, Do Ruhe, Fr 800 Technik, Sa 1600 hart, So Ruhe. */
export function goodWeek(overrides: Partial<WeekPlan> = {}): WeekPlan {
  return {
    rationale: "Solide Woche, passend zum Wochenschnitt von 3000 m.",
    days: [
      day("2026-09-30", { target_distance_meters: 1200 }),
      rest("2026-10-01"),
      day("2026-10-02", { session_type: "technique", intensity: "easy", target_distance_meters: 800, focus: "Technik" }),
      day("2026-10-03", { session_type: "threshold", intensity: "hard", target_distance_meters: 1600, estimated_duration_minutes: 50, focus: "Schwelle" }),
      rest("2026-10-04")
    ],
    ...overrides
  };
}

export function context(overrides: Partial<WeekContext> = {}): WeekContext {
  return { today: TODAY, dates: OPEN_DATES, unavailable: [], swumBefore: [], ...overrides };
}
