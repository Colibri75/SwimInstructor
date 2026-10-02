import { MacroPlanRaw, MacroWeekRaw } from "../../src/plan/macro";
import { MacroContext } from "../../src/plan/macroSanity";

/** Sechs Wochen bis zum Ziel am Donnerstag 12.11.2026: Zielwoche ab 09.11. */
export const MACRO_TODAY = "2026-09-30";
export const MACRO_GOAL_DAY = "2026-11-12";
export const MACRO_WEEKS = ["2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26", "2026-11-02", "2026-11-09"];

export function macroContext(overrides: Partial<MacroContext> = {}): MacroContext {
  return { today: MACRO_TODAY, goalDay: MACRO_GOAL_DAY, weeks: MACRO_WEEKS, ...overrides };
}

export function macroWeek(weekStart: string, overrides: Partial<MacroWeekRaw> = {}): MacroWeekRaw {
  return { week_start: weekStart, target_meters: 3500, sessions: 3, deload: false, focus: "Ausdauer", ...overrides };
}

/**
 * Sinnvoller Gesamtplan fuer den Standard-Snapshot (Wochenschnitt 3000 m, Grenze der ersten Woche 3900 m):
 * 3500, dann etwa 8 % mehr, am Ende Zuspitzen (Hoehepunkt 4400 m) und eine kurze Zielwoche.
 */
export function goodMacro(overrides: Partial<MacroPlanRaw> = {}): MacroPlanRaw {
  const targets = [3500, 3800, 4100, 4400, 3700, 3000, 2200];
  return {
    rationale: "Sechs Wochen bis zum Ziel: Umfang von 3500 m auf 4400 m steigern, dann zuspitzen.",
    weeks: MACRO_WEEKS.map((week, index) => macroWeek(week, { target_meters: targets[index], sessions: index >= 5 ? 2 : 3 })),
    ...overrides
  };
}
