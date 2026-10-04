import { PerformanceTestDefinition } from "../../sports/performance";
import { SessionStep, SportDefinition } from "../../sports/types";
import { daysBetween, MacroPhase } from "../macro";
import { Intensity } from "../plan";
import { SnapshotV2 } from "../snapshot";
import { addDays } from "../week";
import { goalDayOf, MULTI_RULES, SportLimitsNow, sportLimits } from "./limits";
import { isFitnessGoal } from "./schedule";
import { TestSettings } from "./schemas";
import { emphasisOf, formatAmount, isConfirmed, plannedSports, stateOf } from "./sports";

/**
 * Leistungstests im Plan (T3). Die Module bringen Tests und deren Schritte mit; hier steht, wann ein Test in Frage
 * kommt und welcher. Regeln: ein Test mit Vollbelastung ist eine harte Einheit und braucht eine laengste Einheit
 * mindestens so lang wie die Testbelastung; die ganze Testeinheit muss in die Grenze der Sportart passen; kein Test in
 * den letzten 14 Tagen vor dem Ziel. Den Termin im Gesamtplan setzt der Code (`scheduleMacroTests`), nicht Claude.
 */
export interface TestPlan {
  sport: SportDefinition;
  test: PerformanceTestDefinition;
  steps: readonly SessionStep[];
  /** Umfang der ganzen Testeinheit in der Einheit der Sportart. */
  amount: number;
  minutes: number;
  meters: number;
  intensity: Intensity;
}

/** Umfang, Dauer und Strecke einer Folge von Schritten; Strecke und Dauer werden mit dem Trainingstempo umgerechnet. */
export function stepsTotals(sport: SportDefinition, steps: readonly SessionStep[], speed: number): { amount: number; minutes: number; meters: number } {
  let meters = 0;
  let seconds = 0;
  for (const step of steps) {
    const perRepSeconds = step.measure === "duration" ? (step.duration_seconds ?? 0) : (step.distance_meters ?? 0) / speed;
    const perRepMeters = step.measure === "distance" ? (step.distance_meters ?? 0) : (step.duration_seconds ?? 0) * speed;
    meters += step.repetitions * perRepMeters;
    seconds += step.repetitions * (perRepSeconds + step.rest_seconds);
  }
  const minutes = seconds / 60;
  return { amount: sport.planning.limitUnit === "meters" ? meters : minutes, minutes, meters };
}

export function testOf(sport: SportDefinition, testId: string | null | undefined): PerformanceTestDefinition | undefined {
  return testId === null || testId === undefined ? undefined : sport.performanceTests.find((test) => test.id === testId);
}

/** Der bevorzugte Test einer Sportart: aus den Einstellungen, sonst der erste des Moduls. */
export function preferredTest(sport: SportDefinition, settings?: TestSettings): PerformanceTestDefinition | undefined {
  const chosen = settings?.preferred?.find((entry) => entry.sport === sport.id)?.test_id;
  return testOf(sport, chosen) ?? sport.performanceTests[0];
}

export interface TestOptions {
  requested?: string | null;
  settings?: TestSettings;
  /** Hoechstens so viel Umfang (Einheit der Sportart) fuer die ganze Testeinheit. */
  maxAmount: number;
  /** Hoechstens so viele Minuten fuer die ganze Testeinheit (Tagesgrenze), ohne Angabe unbegrenzt. */
  maxMinutes?: number;
  maxIntensity: Intensity;
  /** Warum die Intensitaet begrenzt ist, fuer den Grund ohne Test. */
  intensityReason?: string;
}

/**
 * Waehlt den Test einer Sportart: der angefragte, sonst der bevorzugte, sonst die anderen in der Reihenfolge des
 * Moduls; der erste, der passt. Ohne passenden Test `plan: null` und der Grund fuer den ersten Kandidaten.
 */
export function chooseTest(limits: SportLimitsNow, options: TestOptions): { plan: TestPlan | null; reason: string | null } {
  const sport = limits.sport;
  const candidates: PerformanceTestDefinition[] = [];
  for (const test of [testOf(sport, options.requested), preferredTest(sport, options.settings), ...sport.performanceTests]) {
    if (test !== undefined && !candidates.includes(test)) candidates.push(test);
  }
  let reason: string | null = candidates.length === 0 ? "kein Test für diese Sportart" : null;
  const remember = (why: string) => {
    reason ??= why;
  };
  for (const test of candidates) {
    if (test.maximalEffort) {
      if (options.maxIntensity !== "hard") {
        remember(`${test.displayName}: keine Vollbelastung (${options.intensityReason ?? `höchstens "${options.maxIntensity}"`})`);
        continue;
      }
      if (limits.state.longest_session_minutes < test.durationMinutes) {
        remember(`${test.displayName}: längste Einheit der letzten 4 Wochen unter ${test.durationMinutes} min`);
        continue;
      }
    }
    const steps = sport.planning.testSessions[test.id] ?? [];
    const totals = stepsTotals(sport, steps, limits.speed);
    if (totals.amount > options.maxAmount) {
      remember(`${test.displayName}: Testeinheit (${formatAmount(sport, totals.amount)}) über der Grenze (${formatAmount(sport, options.maxAmount)})`);
      continue;
    }
    if (options.maxMinutes !== undefined && totals.minutes > options.maxMinutes) {
      remember(`${test.displayName}: Testeinheit (${Math.round(totals.minutes)} min) über der Tagesgrenze (${Math.round(options.maxMinutes)} min)`);
      continue;
    }
    return { plan: { sport, test, steps, ...totals, intensity: test.maximalEffort ? "hard" : "easy" }, reason: null };
  }
  return { plan: null, reason };
}

// --- Termine im Gesamtplan ---

export interface ScheduledTest {
  sport: string;
  test_id: string;
  display_name: string;
}

export interface TestWeek {
  week_start: string;
  phase: MacroPhase;
  deload: boolean;
  /** Umfang je Sportart in dieser Woche. */
  amounts: ReadonlyMap<string, number>;
}

/** Der Tag des juengsten bestaetigten Werts, den ein Test der Sportart ermittelt (`yyyy-MM-dd`), sonst `undefined`. */
export function lastConfirmedTest(snapshot: SnapshotV2, sport: SportDefinition): string | undefined {
  const produced = new Set(sport.performanceTests.flatMap((test) => test.produces));
  const values = snapshot.performance?.sports.find((entry) => entry.sport === sport.id)?.values ?? [];
  const dates = values.filter((value) => produced.has(value.metric) && isConfirmed(value.source)).map((value) => value.measured_at.slice(0, 10));
  return dates.length === 0 ? undefined : dates.sort().at(-1);
}

/**
 * Der erste Test im Plan: der bevorzugte, wenn der Athlet seine Vollbelastung schon tragen kann (kein Wiedereinstieg,
 * laengste Einheit mindestens so lang wie die Testbelastung), sonst der erste Test des Moduls ohne Vollbelastung.
 */
export function entryTest(sport: SportDefinition, snapshot: SnapshotV2, settings?: TestSettings): PerformanceTestDefinition | undefined {
  const preferred = preferredTest(sport, settings);
  if (preferred === undefined || !preferred.maximalEffort) return preferred;
  if (!sportLimits(snapshot, sport).pause && stateOf(snapshot, sport.id).longest_session_minutes >= preferred.durationMinutes) return preferred;
  return sport.performanceTests.find((test) => !test.maximalEffort) ?? preferred;
}

/**
 * Ob der Athlet den Test nach seinem heutigen Stand machen koennte: Vollbelastung nicht im Wiedereinstieg und nur mit
 * einer laengsten Einheit so lang wie die Testbelastung, die ganze Testeinheit in der Grenze je Einheit.
 */
export function fitsToday(snapshot: SnapshotV2, sport: SportDefinition, test: PerformanceTestDefinition): boolean {
  const limits = sportLimits(snapshot, sport);
  if (test.maximalEffort && (limits.pause || limits.state.longest_session_minutes < test.durationMinutes)) return false;
  return stepsTotals(sport, sport.planning.testSessions[test.id] ?? [], limits.speed).amount <= limits.sessionCap;
}

/**
 * Setzt die Leistungstests in die Wochen des Gesamtplans: ohne bestaetigten Wert so frueh wie moeglich (die erste
 * Woche, in der noch mindestens drei Tage bleiben), sonst nach dem Intervall. Der erste Test ist ohne tragfaehige
 * Grundlage oder im Wiedereinstieg der ohne Vollbelastung; koennte der Athlet ihn heute nicht machen, fruehestens in
 * der naechsten Woche. Danach alle `interval_weeks` Wochen den bevorzugten Test, bevorzugt in einer Entlastungswoche.
 * Nie beim Zuspitzen, in der Zielwoche oder in den letzten 14 Tagen davor, nur in Wochen mit
 * Training in der Sportart, hoechstens zwei Tests je Woche (Sportarten mit groesserem Schwerpunkt zuerst).
 */
export function scheduleMacroTests(snapshot: SnapshotV2, weeks: readonly TestWeek[], today: string, settings?: TestSettings): Map<string, ScheduledTest[]> {
  const result = new Map<string, ScheduledTest[]>(weeks.map((week) => [week.week_start, []]));
  if (settings?.offer === false) return result;
  const interval = (settings?.interval_weeks ?? MULTI_RULES.defaultTestIntervalWeeks) * 7;
  const goalDay = goalDayOf(snapshot);
  const fitness = isFitnessGoal(snapshot);
  const sports = plannedSports(snapshot)
    .filter((sport) => sport.performanceTests.length > 0)
    .sort((a, b) => emphasisOf(snapshot, b.id) - emphasisOf(snapshot, a.id));

  for (const sport of sports) {
    const allowed = (week: TestWeek): boolean => {
      const end = addDays(week.week_start, 6);
      const phaseOk = week.phase === "base" || week.phase === "specific" || week.phase === "maintain";
      const beforeBlackout = week.phase === "maintain" || fitness || daysBetween(end, goalDay) > MULTI_RULES.testBlackoutDays;
      return (
        phaseOk &&
        beforeBlackout &&
        end >= addDays(today, 2) &&
        (week.amounts.get(sport.id) ?? 0) > 0 &&
        (result.get(week.week_start)?.length ?? 0) < MULTI_RULES.maxTestsPerWeek
      );
    };
    const last = lastConfirmedTest(snapshot, sport);
    // Der erste Test im Plan kommt nach `entryTest`. Koennte der Athlet ihn heute nicht machen (Wiedereinstieg: kurze,
    // lockere Einheiten), fruehestens in der Woche danach; Wochen- und Tagesplan pruefen dann mit dem Stand von dann.
    const first = entryTest(sport, snapshot, settings);
    let due = last === undefined ? today : addDays(last, interval);
    if (first !== undefined && !fitsToday(snapshot, sport, first) && due < addDays(today, 7)) due = addDays(today, 7);
    let entry = last === undefined;
    let firstSlot = true;
    let from = 0;
    while (from < weeks.length) {
      const dueIndex = weeks.findIndex((week, index) => index >= from && addDays(week.week_start, 6) >= due);
      if (dueIndex < 0) break;
      let chosen = -1;
      if (!entry) {
        // Wiederholung: bevorzugt die erste Entlastungswoche in den zwei Wochen nach der faelligen.
        for (let index = dueIndex; index <= Math.min(dueIndex + 2, weeks.length - 1); index += 1) {
          if (weeks[index].deload && allowed(weeks[index])) {
            chosen = index;
            break;
          }
        }
      }
      if (chosen < 0) chosen = weeks.findIndex((week, index) => index >= dueIndex && allowed(week));
      const test = firstSlot ? first : preferredTest(sport, settings);
      if (chosen < 0 || test === undefined) break;
      result.get(weeks[chosen].week_start)?.push({ sport: sport.id, test_id: test.id, display_name: test.displayName });
      due = addDays(weeks[chosen].week_start, interval);
      entry = false;
      firstSlot = false;
      from = chosen + 1;
    }
  }
  return result;
}

/** Wie ein Test in der Antwort steht: die App weiss damit, welche Werte sie danach auswerten soll. */
export interface TestRef {
  id: string;
  display_name: string;
  maximal_effort: boolean;
  produces: string[];
}

export function testRef(test: PerformanceTestDefinition): TestRef {
  return { id: test.id, display_name: test.displayName, maximal_effort: test.maximalEffort, produces: [...test.produces] };
}
