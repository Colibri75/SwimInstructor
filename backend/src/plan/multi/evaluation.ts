import { EvalCheck } from "../evaluation";
import { mondayOf } from "../macro";
import { SnapshotV2 } from "../snapshot";
import { addDays } from "../week";
import { DayPlanV2 } from "./daySanity";
import { realismGaps } from "./limits";
import { MacroPlanV2 } from "./macroSanity";
import { DayTargetV2, MacroWeekTargetV2 } from "./schemas";
import { emphasisOf, plannedSports, sportName } from "./sports";
import { lastConfirmedTest } from "./tests";
import { WeekPlanV2 } from "./weekSanity";

/**
 * Automatische Pruefungen fuer die Bewertung der Szenarien mit mehreren Sportarten (npm run eval:multisport). Wie bei
 * v1 (src/plan/evaluation.ts) Heuristiken, die zeigen, wo man hinschauen sollte: Verteilen die Plaene die Zeit nach den
 * Schwerpunkten, kommen die Leistungstests, nennt die Begruendung das Ziel und ist sie ehrlich? Die harten Grenzen
 * prueft die Sicherheitsschicht.
 */
const GOAL_WORDS = /ziel|wettkampf|triathlon|marathon/i;
const HONEST_WORDS = /nicht (ganz |sicher |mehr )?(erreich|schaff)|unrealistisch|knapp|zu kurz|reicht (die|nicht)|schwierig|ehrlich|nicht sicher/i;
/** Abweichung vom Schwerpunkt in Prozentpunkten, die noch als verteilt gilt (Gesamtplan, Woche). */
const MACRO_SHARE_TOLERANCE = 15;
const WEEK_SHARE_TOLERANCE = 20;

function shareCheck(snapshot: SnapshotV2, minutes: Map<string, number>, tolerance: number): EvalCheck {
  const total = [...minutes.values()].reduce((sum, value) => sum + value, 0);
  if (total <= 0) return { name: "Schwerpunkte verteilt", ok: false, detail: "kein Training geplant" };
  const parts = plannedSports(snapshot).map((sport) => {
    const share = Math.round(((minutes.get(sport.id) ?? 0) / total) * 100);
    const target = emphasisOf(snapshot, sport.id);
    return { text: `${sport.displayName} ${share} % (Schwerpunkt ${target} %)`, ok: Math.abs(share - target) <= tolerance };
  });
  return { name: "Schwerpunkte verteilt", ok: parts.every((part) => part.ok), detail: parts.map((part) => part.text).join(", ") };
}

function goalCheck(text: string): EvalCheck {
  const ok = GOAL_WORDS.test(text);
  return { name: "Begründung nennt das Ziel", ok, detail: ok ? "ja" : 'kein Wort wie "Ziel" oder "Wettkampf" in der Begründung' };
}

function honestyCheck(snapshot: SnapshotV2, today: string, text: string): EvalCheck[] {
  const gaps = realismGaps(snapshot, today);
  if (gaps.length === 0) return [];
  const ok = HONEST_WORDS.test(text);
  const names = gaps.map((gap) => gap.sport.displayName).join(", ");
  return [{ name: "Ehrlich bei knapper Zeit", ok, detail: ok ? `sagt es (${names})` : `${names} lässt sich nicht sicher aufbauen, die Begründung sagt das nicht` }];
}

/** Gesamtplan: Verteilung in den Belastungswochen, Hoehepunkt vor dem Zuspitzen, fruehe Einstiegstests, Ziel, Ehrlichkeit. */
export function checkMacroPlanV2(snapshot: SnapshotV2, plan: MacroPlanV2, today: string): EvalCheck[] {
  const loading = plan.weeks.filter((week) => (week.phase === "base" || week.phase === "specific") && !week.deload);
  const minutes = new Map<string, number>();
  for (const week of loading) for (const entry of week.sports) minutes.set(entry.sport, (minutes.get(entry.sport) ?? 0) + entry.minutes);
  const checks: EvalCheck[] = loading.length > 0 ? [shareCheck(snapshot, minutes, MACRO_SHARE_TOLERANCE)] : [];

  const firstTaper = plan.weeks.findIndex((week) => week.phase === "taper");
  if (firstTaper > 0) {
    const peak = plan.weeks.reduce((best, week, index) => (week.total_minutes > plan.weeks[best].total_minutes ? index : best), 0);
    checks.push({
      name: "Höhepunkt vor dem Zuspitzen",
      ok: peak < firstTaper,
      detail: `höchste Woche ab ${plan.weeks[peak].week_start} (${plan.weeks[peak].total_minutes} min), Zuspitzen ab ${plan.weeks[firstTaper].week_start}`
    });
  }

  const needEntry = plannedSports(snapshot).filter((sport) => sport.performanceTests.length > 0 && lastConfirmedTest(snapshot, sport) === undefined);
  if (needEntry.length > 0) {
    const early = new Set(plan.weeks.slice(0, 2).flatMap((week) => week.tests.map((test) => test.sport)));
    const missing = needEntry.filter((sport) => !early.has(sport.id));
    checks.push({
      name: "Einstiegstests in den ersten zwei Wochen",
      ok: missing.length === 0,
      detail: missing.length === 0 ? needEntry.map((sport) => sport.displayName).join(", ") : `fehlt: ${missing.map((sport) => sport.displayName).join(", ")}`
    });
  }
  const tests = plan.weeks.flatMap((week) => week.tests.map((test) => `${sportName(test.sport)} ab ${week.week_start}`));
  checks.push({ name: "Leistungstests im Plan", ok: true, detail: tests.length > 0 ? tests.join("; ") : "keine" });
  checks.push(goalCheck(plan.rationale), ...honestyCheck(snapshot, today, plan.rationale));
  return checks;
}

/**
 * Sieben Tage: Verteilung, Tests aus dem Gesamtplan, Ziel. Ein Test zaehlt nur fuer eine Woche, deren Rest ganz in den
 * sieben Tagen liegt; faellt nur ihr Anfang hinein, kann ihn der naechste Wochenplan noch setzen.
 */
export function checkWeekPlanV2(snapshot: SnapshotV2, plan: WeekPlanV2, macroWeeks: readonly MacroWeekTargetV2[] = []): EvalCheck[] {
  const minutes = new Map<string, number>();
  for (const day of plan.days) for (const session of day.sessions) minutes.set(session.sport, (minutes.get(session.sport) ?? 0) + session.minutes);
  const checks = [shareCheck(snapshot, minutes, WEEK_SHARE_TOLERANCE)];

  const dates = plan.days.map((day) => day.date);
  const last = dates.at(-1) ?? "";
  const covered = (week: MacroWeekTargetV2) => dates.some((date) => mondayOf(date) === week.week_start) && addDays(week.week_start, 6) <= last;
  const wanted = macroWeeks.flatMap((week) => (covered(week) ? (week.tests ?? []) : []).map((test) => ({ test, week })));
  if (wanted.length > 0) {
    const placed = plan.days.flatMap((day) => day.sessions.filter((session) => session.test !== null).map((session) => ({ sport: session.sport, date: day.date })));
    const missing = wanted.filter(({ test, week }) => !placed.some((entry) => entry.sport === test.sport && mondayOf(entry.date) === week.week_start));
    checks.push({
      name: "Tests aus dem Gesamtplan eingeplant",
      ok: missing.length === 0,
      detail:
        missing.length === 0
          ? placed.map((entry) => `${sportName(entry.sport)} am ${entry.date}`).join(", ")
          : `fehlt: ${missing.map(({ test, week }) => `${sportName(test.sport)} (Woche ab ${week.week_start})`).join(", ")}`
    });
  }
  checks.push(goalCheck(plan.rationale));
  return checks;
}

/** Ein Tag: Vorgabe aus dem Wochenplan eingehalten, Ziel genannt. */
export function checkDayPlanV2(plan: DayPlanV2, target?: DayTargetV2): EvalCheck[] {
  const checks: EvalCheck[] = [];
  if (target !== undefined) {
    const wanted = target.sessions.map((session) => session.sport).sort();
    const got = plan.sessions.map((session) => session.sport).sort();
    const ok = wanted.length === got.length && wanted.every((sport, index) => sport === got[index]);
    checks.push({
      name: "Vorgabe des Wochenplans",
      ok,
      detail: `geplant ${got.map(sportName).join(" + ") || "Ruhetag"}, Vorgabe ${wanted.map(sportName).join(" + ") || "Ruhetag"}`
    });
    const wantedTest = target.sessions.find((session) => session.session_type === "test");
    if (wantedTest !== undefined) {
      const test = plan.sessions.find((session) => session.test !== null);
      checks.push({
        name: "Leistungstest der Vorgabe",
        ok: test !== undefined,
        detail: test !== undefined ? `${test.test?.display_name} mit ${test.steps.length} Schritten` : "kein Test im Tagesplan"
      });
    }
  }
  if (plan.sessions.length > 0) checks.push(goalCheck(plan.rationale));
  return checks;
}

/** Feedback zum Gesamtplan: Aenderungen genannt und der Plan hat sich tatsaechlich geaendert. */
export function checkRevisionV2(before: readonly MacroWeekTargetV2[], after: MacroPlanV2, changes: readonly string[]): EvalCheck[] {
  const amounts = (weeks: readonly { week_start: string; sports: readonly { sport: string; amount: number }[] }[]) =>
    weeks.flatMap((week) => week.sports.map((entry) => `${week.week_start}:${entry.sport}:${entry.amount}`)).join("|");
  const changed = amounts(before) !== amounts(after.weeks);
  return [
    { name: "Änderungen genannt", ok: changes.length > 0, detail: changes.length > 0 ? `${changes.length}` : "keine" },
    { name: "Plan geändert", ok: changed, detail: changed ? `${after.weeks.filter((week, index) => amounts([week]) !== amounts(before.slice(index, index + 1))).length} Wochen anders` : "alle Umfänge gleich" }
  ];
}

