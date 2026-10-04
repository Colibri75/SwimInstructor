import { LimitUnit } from "../../sports/types";
import { MacroPhase } from "../macro";
import { SnapshotV2 } from "../snapshot";
import { addDays } from "../week";
import { multiPhase, MULTI_RULES, sportLimits, SportLimitsNow, taperFactors, taperWeeks, weeksToGoal } from "./limits";
import { MacroBlockRaw, MacroWeekRawV2, MacroWeeksRaw, TestSettings } from "./schemas";
import { amountToMeters, amountToMinutes, floorAmount, formatAmount, plannedSports, raceAmount, roundAmount, sportName } from "./sports";
import { scheduleMacroTests, ScheduledTest } from "./tests";

/**
 * Sicherheitsschicht fuer den Gesamtplan ueber mehrere Sportarten. Wie bei v1 reiner Code: korrigiert Claudes Plan
 * deterministisch oder blockt ihn.
 *
 * Je Sportart: die erste Woche in der Wochengrenze von heute, danach hoechstens der Wachstumsfaktor des Moduls (etwa
 * 10 %) ueber der letzten Woche ohne Entlastung; Entlastungswochen hoechstens 70 % davon, spaetestens nach drei
 * Belastungswochen; Zuspitzen und Zielwoche gegenueber dem Hoehepunkt der Sportart. Ueber alle Sportarten: hoechstens
 * die Wochenstunden des Ziels. Die Phase und die Termine der Leistungstests setzt der Code.
 */
export interface MacroContextV2 {
  today: string;
  goalDay: string;
  /** Die Wochen (Montage), aufsteigend. */
  weeks: string[];
  testSettings?: TestSettings;
}

export interface MacroSportWeek {
  sport: string;
  unit: LimitUnit;
  /** Wochenumfang in der Einheit der Sportart. */
  amount: number;
  minutes: number;
  distance_meters: number;
  sessions: number;
}

export interface MacroWeekV2 {
  week_start: string;
  phase: MacroPhase;
  deload: boolean;
  focus: string;
  total_minutes: number;
  /** Minuten mal Lastfaktor der Sportart, ueber alle Sportarten. */
  load: number;
  sports: MacroSportWeek[];
  tests: ScheduledTest[];
}

export interface MacroPlanV2 {
  rationale: string;
  weeks: MacroWeekV2[];
}

export interface MacroSanityResultV2 {
  plan: MacroPlanV2;
  adjustments: string[];
  blocked: string | null;
}

/** Die Grenzen je Sportart fuer den Gesamtplan, wie sie auch an Claude gehen. */
export interface MacroSportLimits {
  limits: SportLimitsNow;
  firstWeekCap: number;
  /** Untergrenze der Bezugswoche fuer das Wachstum (Einsteiger ohne Verlauf). */
  floor: number;
  growthFactor: number;
  /**
   * Rueckkehr nach einer Pause: der angegebene Wochenumfang vor der Pause (0 ohne Angabe oder wenn er schon gilt). Bis
   * dahin darf eine Woche um `returnGrowthFactor` wachsen statt um `growthFactor`.
   */
  returnTarget: number;
  returnGrowthFactor: number;
  /** Umfang der Disziplin im Wettkampf, 0 wenn die Sportart keine ist. */
  race: number;
  absoluteWeekly: number;
}

export function macroSportLimits(snapshot: SnapshotV2): MacroSportLimits[] {
  return plannedSports(snapshot).map((sport) => {
    const limits = sportLimits(snapshot, sport);
    const planning = sport.planning.limits;
    return {
      limits,
      firstWeekCap: limits.weeklyCap,
      floor: Math.min(planning.minWeeklyCap, limits.weeklyCap),
      growthFactor: planning.macroGrowthFactor,
      returnTarget: limits.declared !== null && limits.declared.reportedWeekly > limits.average ? floorAmount(sport, limits.declared.reportedWeekly) : 0,
      returnGrowthFactor: sport.planning.startingLevel.returnGrowthFactor,
      race: raceAmount(snapshot, sport),
      absoluteWeekly: planning.absoluteMaxSession * planning.maxSessionsPerWeek
    };
  });
}

function label(weekStart: string): string {
  return `Woche ab ${weekStart.slice(8, 10)}.${weekStart.slice(5, 7)}.`;
}

/** Ohne Angabe hat eine Entlastungswoche so viel der letzten Woche davor (etwas unter der Grenze `deloadFactor`). */
export const DEFAULT_DELOAD_SHARE = 0.65;

/**
 * Rechnet Claudes Abschnitte in Wochen um, in der Reihenfolge der Wochen des Plans. In einem Abschnitt steigt (oder
 * sinkt) der Umfang jeder Sportart gleichmaessig von `start_amount` bis `end_amount`; mit `deload_last` ist die letzte
 * Woche eine Entlastungswoche mit `deload_amount` (ohne Angabe 65 % von `end_amount`). Ueberzaehlige Wochen bekommen
 * fortlaufende Montage, damit die Sicherheitsschicht zu lange Plaene erkennt; mehr als doppelt so viele wie geplant
 * werden gar nicht erst erzeugt.
 */
export function expandMacroBlocks(blocks: readonly MacroBlockRaw[], weeks: readonly string[]): MacroWeekRawV2[] {
  const limit = weeks.length * 2 + 1;
  const result: MacroWeekRawV2[] = [];
  for (const block of blocks) {
    const count = Number.isFinite(block.weeks) ? Math.max(Math.round(block.weeks), 1) : 1;
    const loadingWeeks = block.deload_last ? count - 1 : count;
    for (let index = 0; index < count && result.length < limit; index += 1) {
      const deload = block.deload_last && index === count - 1;
      const share = loadingWeeks > 1 ? index / (loadingWeeks - 1) : 0;
      const position = result.length;
      const weekStart = weeks[position] ?? addDays(weeks[weeks.length - 1] ?? "2000-01-03", (position - weeks.length + 1) * 7);
      result.push({
        week_start: weekStart,
        deload,
        focus: block.focus,
        sports: block.sports.map((entry) => ({
          sport: entry.sport,
          amount: deload
            ? (entry.deload_amount ?? entry.end_amount * DEFAULT_DELOAD_SHARE)
            : entry.start_amount + (entry.end_amount - entry.start_amount) * share,
          sessions: entry.sessions
        }))
      });
    }
  }
  return result;
}

export function sanitizeMacroV2(input: MacroWeeksRaw, snapshot: SnapshotV2, context: MacroContextV2): MacroSanityResultV2 {
  const problem = findProblem(input, context);
  if (problem !== null) return { plan: { rationale: input.rationale, weeks: [] }, adjustments: [], blocked: problem };

  const sportLimitsList = macroSportLimits(snapshot);
  const planned = new Set(sportLimitsList.map((entry) => entry.limits.sport.id));
  const byWeek = new Map<string, MacroWeekRawV2>();
  for (const week of input.weeks) {
    if (context.weeks.includes(week.week_start) && !byWeek.has(week.week_start)) byWeek.set(week.week_start, week);
  }
  const unplanned = new Set(input.weeks.flatMap((week) => week.sports.map((entry) => entry.sport)).filter((id) => !planned.has(id)));

  const taper = taperWeeks(snapshot);
  const factors = taperFactors(snapshot);
  const goal = snapshot.training_goal;
  const weeklyMinutesCap = goal.weekly_hours * 60;
  const maxSessions = goal.training_days_per_week * MULTI_RULES.maxSessionsPerDay;

  const reference = new Map<string, number>(sportLimitsList.map((entry) => [entry.limits.sport.id, entry.limits.average]));
  const peak = new Map<string, number>();
  const notes: string[] = [];
  const weeks: MacroWeekV2[] = [];
  let missing = 0;
  let loadingStreak = 0;

  context.weeks.forEach((weekStart, index) => {
    const phase = multiPhase(weekStart, context.goalDay, context.today, taper);
    const toGoal = weeksToGoal(weekStart, context.goalDay);
    const previous = weeks[index - 1];
    const found = byWeek.get(weekStart);
    if (found === undefined) missing += 1;
    const raw: MacroWeekRawV2 = found ?? {
      week_start: weekStart,
      deload: false,
      focus: previous?.focus ?? "Training fortführen",
      sports: sportLimitsList.map(({ limits }) => ({
        sport: limits.sport.id,
        amount: previous?.sports.find((entry) => entry.sport === limits.sport.id)?.amount ?? floorAmount(limits.sport, limits.average),
        sessions: previous?.sports.find((entry) => entry.sport === limits.sport.id)?.sessions ?? 2
      }))
    };

    const loading = phase === "base" || phase === "specific";
    let deload = raw.deload && index > 0 && loading;
    if (!deload && index > 0 && loading && loadingStreak >= MULTI_RULES.maxLoadingWeeks) {
      deload = true;
      notes.push(`${label(weekStart)}: als Entlastungswoche gesetzt (spätestens nach ${MULTI_RULES.maxLoadingWeeks} Belastungswochen)`);
    }

    let sports: MacroSportWeek[] = sportLimitsList.map((entry) => {
      const sport = entry.limits.sport;
      const limits = sport.planning.limits;
      const requested = raw.sports.find((item) => item.sport === sport.id);
      let amount = roundAmount(sport, Math.max(requested?.amount ?? 0, 0));
      const ref = reference.get(sport.id) ?? 0;
      const sportPeak = peak.get(sport.id) ?? 0;
      let cap: number;
      let why: string;
      if (index === 0) {
        cap = entry.firstWeekCap;
        why = "Grenze für die erste Woche";
      } else if (deload) {
        cap = floorAmount(sport, ref * MULTI_RULES.deloadFactor);
        why = "Entlastungswoche";
      } else {
        const base = Math.max(ref, entry.floor);
        cap = floorAmount(sport, base * entry.growthFactor);
        why = `höchstens ${Math.round((entry.growthFactor - 1) * 100)} % mehr als die letzte Woche ohne Entlastung`;
        // Zurueck zum Niveau vor der Pause geht es schneller, aber nie darueber hinaus.
        const back = floorAmount(sport, Math.min(base * entry.returnGrowthFactor, entry.returnTarget));
        if (back > cap) {
          cap = back;
          why = `Rückkehr zum Niveau vor der Pause: höchstens ${Math.round((entry.returnGrowthFactor - 1) * 100)} % mehr als die letzte Woche ohne Entlastung`;
        }
      }
      if (phase === "taper" && sportPeak > 0) {
        const factor = factors[Math.min(Math.max(taper - toGoal, 0), factors.length - 1)];
        if (floorAmount(sport, sportPeak * factor) < cap) {
          cap = floorAmount(sport, sportPeak * factor);
          why = "Zuspitzen";
        }
      } else if (phase === "goal_week") {
        const goalCap = Math.max(sportPeak > 0 ? floorAmount(sport, sportPeak * MULTI_RULES.goalWeekFactor) : 0, floorAmount(sport, entry.race * MULTI_RULES.goalWeekRaceFactor));
        if (sportPeak > 0 || goalCap > cap) {
          cap = goalCap;
          why = "Zielwoche";
        }
      }
      cap = Math.min(cap, entry.absoluteWeekly);
      if (amount > cap) {
        notes.push(`${label(weekStart)}: ${sport.displayName} von ${formatAmount(sport, amount)} auf ${formatAmount(sport, cap)} begrenzt (${why})`);
        amount = cap;
      }
      if (amount > 0 && amount < limits.minSession) amount = cap >= limits.minSession ? limits.minSession : 0;
      const sessions = clampSessions(Math.round(requested?.sessions ?? 0), amount, limits.minSession, limits.maxSessionsPerWeek);
      return toSportWeek(entry.limits, amount, sessions);
    });

    // Ueber alle Sportarten: hoechstens die Wochenstunden des Ziels.
    const total = sports.reduce((sum, entry) => sum + entry.minutes, 0);
    if (total > weeklyMinutesCap) {
      const factor = weeklyMinutesCap / total;
      sports = sports.map((entry, sportIndex) => {
        const limits = sportLimitsList[sportIndex].limits;
        const minimum = limits.sport.planning.limits.minSession;
        let amount = floorAmount(limits.sport, entry.amount * factor);
        if (amount < minimum) amount = 0;
        return toSportWeek(limits, amount, clampSessions(entry.sessions, amount, minimum, limits.sport.planning.limits.maxSessionsPerWeek));
      });
      notes.push(`${label(weekStart)}: Gesamtumfang von ${Math.round(total)} min auf höchstens ${Math.round(weeklyMinutesCap)} min gekürzt (Wochenstunden des Ziels)`);
    }
    // Hoechstens zwei Einheiten an jedem Trainingstag.
    while (sports.reduce((sum, entry) => sum + entry.sessions, 0) > maxSessions) {
      const most = sports.reduce((best, entry) => (entry.sessions > best.sessions ? entry : best));
      if (most.sessions <= 1) break;
      most.sessions -= 1;
    }

    for (const entry of sports) {
      if (!deload) reference.set(entry.sport, index === 0 ? Math.max(entry.amount, reference.get(entry.sport) ?? 0) : entry.amount);
      if (!deload && loading) peak.set(entry.sport, Math.max(peak.get(entry.sport) ?? 0, entry.amount));
    }
    loadingStreak = deload ? 0 : loading ? loadingStreak + 1 : loadingStreak;

    const totalMinutes = Math.round(sports.reduce((sum, entry) => sum + entry.minutes, 0));
    const load = Math.round(sports.reduce((sum, entry, sportIndex) => sum + entry.minutes * sportLimitsList[sportIndex].limits.sport.loadFactor, 0));
    weeks.push({
      week_start: weekStart,
      phase,
      deload,
      focus: raw.focus.trim().slice(0, MULTI_RULES.maxFocusLength) || "Training",
      total_minutes: totalMinutes,
      load,
      sports,
      tests: []
    });
  });

  const scheduled = scheduleMacroTests(
    snapshot,
    weeks.map((week) => ({ week_start: week.week_start, phase: week.phase, deload: week.deload, amounts: new Map(week.sports.map((entry) => [entry.sport, entry.amount])) })),
    context.today,
    context.testSettings
  );
  for (const week of weeks) week.tests = scheduled.get(week.week_start) ?? [];

  const adjustments: string[] = [];
  if (missing > 0) adjustments.push(`${missing} fehlende Wochen mit dem Umfang der Vorwoche ergänzt`);
  if (unplanned.size > 0) adjustments.push(`Sportarten ohne Schwerpunkt entfernt: ${[...unplanned].map(sportName).join(", ")}`);
  adjustments.push(...notes.slice(0, MULTI_RULES.maxAdjustmentLines));
  if (notes.length > MULTI_RULES.maxAdjustmentLines) adjustments.push(`… und ${notes.length - MULTI_RULES.maxAdjustmentLines} weitere Korrekturen am Umfang`);

  let rationale = input.rationale.trim().slice(0, MULTI_RULES.maxRationaleLength);
  if (notes.length > 0) {
    const note = `Hinweis: Zur Sicherheit an ${notes.length} ${notes.length === 1 ? "Stelle" : "Stellen"} angepasst, die Wochen zeigen die geprüften Umfänge.`;
    const room = Math.max(MULTI_RULES.maxRationaleLength - note.length - 1, 0);
    rationale = `${rationale.slice(0, room).trimEnd()} ${note}`.trim();
  }
  return { plan: { rationale, weeks }, adjustments, blocked: null };
}

function findProblem(input: MacroWeeksRaw, context: MacroContextV2): string | null {
  if (input.rationale.trim() === "") return "Begründung fehlt";
  if (input.weeks.length === 0) return "Gesamtplan ohne Wochen";
  if (input.weeks.length > context.weeks.length * 2) return `zu viele Wochen (${input.weeks.length})`;
  for (const week of input.weeks) {
    if (week.sports.length > 32) return "zu viele Sportarten in einer Woche";
    for (const entry of week.sports) {
      if (![entry.amount, entry.sessions].every(Number.isFinite)) return "Zahlenwert in einer Woche ungültig";
    }
  }
  return null;
}

function clampSessions(sessions: number, amount: number, minSession: number, maxSessions: number): number {
  if (amount <= 0) return 0;
  return Math.max(Math.min(sessions, maxSessions, Math.floor(amount / minSession)), 1);
}

function toSportWeek(limits: SportLimitsNow, amount: number, sessions: number): MacroSportWeek {
  const sport = limits.sport;
  return {
    sport: sport.id,
    unit: sport.planning.limitUnit,
    amount,
    minutes: Math.round(amountToMinutes(sport, amount, limits.speed)),
    distance_meters: Math.round(amountToMeters(sport, amount, limits.speed) / 50) * 50,
    sessions
  };
}
