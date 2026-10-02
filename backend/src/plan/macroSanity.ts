import { daysBetween, macroPhase, MacroPlanRaw, MacroWeek, MacroWeekRaw, mondayOf } from "./macro";
import { DEFAULT_LIMITS, SanityLimits } from "./sanity";
import { Snapshot } from "./snapshot";
import { windowDates } from "./week";
import { weekLimits } from "./weekSanity";

/**
 * Sicherheitsschicht fuer den Gesamtplan. Wie bei Tages- und Wochenplan: reiner Code, korrigiert Claudes
 * Plan deterministisch oder blockt ihn. Die Zahlen aus `macroLimits` gehen vorab auch an Claude (Prompt).
 *
 * Regeln: genau die angefragten Wochen, die Phase kommt vom Code, die erste Woche haelt die Grenzen von
 * heute ein (Erholung, Pause, Wochenschnitt), danach hoechstens etwa 10 % mehr als die letzte Woche ohne
 * Entlastung, Entlastungswochen liegen deutlich darunter, beim Zuspitzen und in der Zielwoche sinkt der
 * Umfang gegenueber dem Hoehepunkt.
 */
export interface MacroContext {
  today: string;
  /** Zieltag `yyyy-MM-dd`. */
  goalDay: string;
  /** Die Wochen (Montage), aufsteigend. */
  weeks: string[];
}

export interface MacroLimits {
  /** Hoechstens so viele Meter in der ersten Woche (aus dem Zustand von heute). */
  firstWeekCapMeters: number;
  /** Eine Woche darf hoechstens so viel mehr haben als die letzte Woche ohne Entlastung. */
  growthFactor: number;
  /** Eine Entlastungswoche liegt hoechstens so hoch wie dieser Anteil der letzten normalen Woche. */
  deloadFactor: number;
  /** Anteil des bisherigen Hoehepunkts, den die Wochen beim Zuspitzen hoechstens haben (zwei und eine Woche vor der Zielwoche). */
  taperFactors: [number, number];
  /** Zielwoche: hoechstens dieser Anteil des Hoehepunkts, mindestens aber 1,2 mal die Zieldistanz. */
  goalWeekFactor: number;
  absoluteMaxWeeklyMeters: number;
}

const STEP = 50;
const MIN_SESSIONS = 2;
const MAX_SESSIONS = 5;
const MAX_FOCUS_LENGTH = 80;
const MAX_ADJUSTMENT_LINES = 10;

export function macroLimits(snapshot: Snapshot, context: MacroContext, limits: SanityLimits = DEFAULT_LIMITS): MacroLimits {
  const firstWeek = weekLimits(snapshot, { today: context.today, dates: windowDates(context.today, 7), unavailable: [], swumBefore: [] }, limits);
  return {
    firstWeekCapMeters: Math.floor(firstWeek.weeklyRemainingMeters / STEP) * STEP,
    growthFactor: 1.1,
    deloadFactor: 0.85,
    taperFactors: [0.85, 0.7],
    goalWeekFactor: 0.5,
    absoluteMaxWeeklyMeters: 20_000
  };
}

export interface MacroSanityResult {
  plan: { rationale: string; weeks: MacroWeek[] };
  adjustments: string[];
  blocked: string | null;
}

function floorStep(value: number): number {
  return Math.floor(value / STEP) * STEP;
}

function label(weekStart: string): string {
  return `Woche ab ${weekStart.slice(8, 10)}.${weekStart.slice(5, 7)}.`;
}

export function sanitizeMacro(input: MacroPlanRaw, snapshot: Snapshot, context: MacroContext, limits: SanityLimits = DEFAULT_LIMITS): MacroSanityResult {
  if (input.rationale.trim() === "") return blocked(input, "Begründung fehlt");
  if (input.weeks.length === 0) return blocked(input, "Gesamtplan ohne Wochen");
  if (input.weeks.length > context.weeks.length * 2) return blocked(input, `zu viele Wochen (${input.weeks.length})`);
  for (const week of input.weeks) {
    if (![week.target_meters, week.sessions].every(Number.isFinite)) return blocked(input, "Zahlenwert in einer Woche ungültig");
  }

  const limitsNow = macroLimits(snapshot, context, limits);
  const byWeek = new Map<string, MacroWeekRaw>();
  for (const week of input.weeks) {
    if (context.weeks.includes(week.week_start) && !byWeek.has(week.week_start)) byWeek.set(week.week_start, week);
  }

  const notes: string[] = [];
  const weeks: MacroWeek[] = [];
  const goalDistance = snapshot.goal.distance_meters;
  // Letzte Woche ohne Entlastung (Bezug fuer das Wachstum) und bisheriger Hoehepunkt.
  let reference = Math.max(snapshot.volume.average_weekly_meters, 0);
  let peak = 0;
  let missing = 0;

  context.weeks.forEach((weekStart, index) => {
    const phase = macroPhase(weekStart, context.goalDay, context.today);
    const weeksToGoal = Math.round(daysBetween(weekStart, mondayOf(context.goalDay)) / 7);
    const found = byWeek.get(weekStart);
    const previous = weeks[index - 1];
    const raw: MacroWeekRaw =
      found ?? {
        week_start: weekStart,
        target_meters: previous?.target_meters ?? limitsNow.firstWeekCapMeters,
        sessions: previous?.sessions ?? 3,
        deload: false,
        focus: previous?.focus ?? "Training fortführen"
      };
    if (found === undefined) missing += 1;

    let sessions = Math.min(Math.max(Math.round(raw.sessions), MIN_SESSIONS), MAX_SESSIONS);
    let target = Math.max(floorStep(raw.target_meters), 0);
    // Entlastung gibt es nicht in der ersten Woche, nicht beim Zuspitzen und nicht in der Zielwoche.
    const deload = raw.deload && index > 0 && (phase === "base" || phase === "specific");

    const reasons: string[] = [];
    let cap = limitsNow.absoluteMaxWeeklyMeters;
    if (index === 0) {
      cap = Math.min(cap, limitsNow.firstWeekCapMeters);
    } else if (deload) {
      cap = Math.min(cap, floorStep(reference * limitsNow.deloadFactor));
    } else {
      cap = Math.min(cap, floorStep(Math.max(reference, STEP * 10) * limitsNow.growthFactor));
    }
    // Zuspitzen und Zielwoche gegenueber dem Hoehepunkt.
    if (phase === "taper") {
      const factor = weeksToGoal >= 2 ? limitsNow.taperFactors[0] : limitsNow.taperFactors[1];
      if (peak > 0) cap = Math.min(cap, floorStep(peak * factor));
    } else if (phase === "goal_week" && peak > 0) {
      cap = Math.min(cap, Math.max(floorStep(peak * limitsNow.goalWeekFactor), floorStep(goalDistance * 1.2)));
    }
    if (target > cap) {
      reasons.push(index === 0 ? "Grenze für die erste Woche" : deload ? "Entlastungswoche" : phase === "taper" || phase === "goal_week" ? "Zuspitzen" : "höchstens etwa 10 % mehr als die Woche davor");
      notes.push(`${label(weekStart)}: Umfang von ${target} m auf ${cap} m begrenzt (${reasons[0]})`);
      target = cap;
    }
    // Eine Woche mit Training hat mindestens zwei Einheiten zur Mindestlaenge.
    const minWeek = limits.minMeaningfulSessionMeters * MIN_SESSIONS;
    if (target > 0 && target < minWeek && cap >= minWeek) {
      notes.push(`${label(weekStart)}: Umfang von ${target} m auf ${minWeek} m angehoben (mindestens zwei Einheiten zu je ${limits.minMeaningfulSessionMeters} m)`);
      target = minWeek;
    }
    // Pro Einheit mindestens die Mindestlaenge, sonst weniger Tage.
    sessions = Math.max(Math.min(sessions, Math.floor(target / limits.minMeaningfulSessionMeters)), target > 0 ? 1 : 0);

    weeks.push({
      week_start: weekStart,
      target_meters: target,
      sessions,
      deload,
      focus: raw.focus.trim().slice(0, MAX_FOCUS_LENGTH) || "Training",
      phase
    });
    if (!deload) reference = target;
    if (!deload && (phase === "base" || phase === "specific")) peak = Math.max(peak, target);
  });

  const adjustments: string[] = [];
  if (missing > 0) adjustments.push(`${missing} fehlende Wochen mit dem Umfang der Vorwoche ergänzt`);
  adjustments.push(...notes.slice(0, MAX_ADJUSTMENT_LINES));
  if (notes.length > MAX_ADJUSTMENT_LINES) adjustments.push(`… und ${notes.length - MAX_ADJUSTMENT_LINES} weitere Korrekturen am Umfang`);

  const rationale = input.rationale.trim().slice(0, limits.maxRationaleLength);
  return { plan: { rationale, weeks }, adjustments, blocked: null };
}

function blocked(input: MacroPlanRaw, reason: string): MacroSanityResult {
  return { plan: { rationale: input.rationale, weeks: [] }, adjustments: [], blocked: reason };
}
