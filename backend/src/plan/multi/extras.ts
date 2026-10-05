import { daysBetween } from "../calendar";
import { SnapshotV2 } from "../snapshot";
import { goalDayOf, MULTI_RULES } from "./limits";
import { isFitnessGoal } from "./schedule";
import { DayExtraRaw, ExerciseRaw, ExtraKind, Supplements, WeekExtraRaw } from "./schemas";

/**
 * Ergaenzungstraining neben den Sportarten: Kraft und Mobilitaet. Wie oft, legt der Athlet in der App fest
 * (`supplements`); Claude legt die Bloecke in die Woche, die Sicherheitsschicht haelt diese Regeln ein.
 *
 * Kraft hilft Ausdauersportlern bei Oekonomie und Verletzungsvorbeugung (Ronnestad und Mujika 2014), zwei Einheiten pro
 * Woche reichen; nicht am Tag vor einer harten Einheit und nicht in der Woche vor dem Wettkampf. Mobilitaet ist kurz und
 * locker und geht jeden Tag.
 */
export const EXTRA_RULES: Record<ExtraKind, { displayName: string; minMinutes: number; maxMinutes: number }> = {
  strength: { displayName: "Kraft", minMinutes: 15, maxMinutes: 45 },
  mobility: { displayName: "Mobilität", minMinutes: 5, maxMinutes: 30 }
};

export const EXERCISE_RULES = {
  maxExercises: 10,
  maxSets: 5,
  maxReps: 30,
  minSeconds: 10,
  maxSeconds: 180,
  maxRestSeconds: 180,
  /** Keine Kraft in so vielen Tagen vor dem Ziel (der Zieltag zaehlt mit). */
  noStrengthDaysBeforeGoal: 7
};

export interface WeekExtra {
  kind: ExtraKind;
  minutes: number;
  focus: string;
}

export interface Exercise {
  name: string;
  sets: number;
  reps: number | null;
  seconds: number | null;
  rest_seconds: number;
  cue: string;
  instructions: string;
}

export interface DayExtra extends WeekExtra {
  exercises: Exercise[];
}

export function perWeek(supplements: Supplements | undefined, kind: ExtraKind): number {
  if (supplements === undefined) return 0;
  return kind === "strength" ? supplements.strength_per_week : supplements.mobility_per_week;
}

/** Kraft so kurz vor dem Ziel? Dann `true` (kein Krafttraining mehr). */
export function strengthBlackout(snapshot: SnapshotV2, date: string): boolean {
  if (isFitnessGoal(snapshot)) return false;
  const days = daysBetween(date, goalDayOf(snapshot));
  return days >= 0 && days < EXERCISE_RULES.noStrengthDaysBeforeGoal;
}

function clampMinutes(kind: ExtraKind, minutes: number): number {
  const rules = EXTRA_RULES[kind];
  return Math.round(Math.min(Math.max(Number.isFinite(minutes) ? minutes : rules.minMinutes, rules.minMinutes), rules.maxMinutes) / 5) * 5;
}

function cleanFocus(kind: ExtraKind, focus: string): string {
  return focus.trim().slice(0, MULTI_RULES.maxFocusLength) || EXTRA_RULES[kind].displayName;
}

/** Je Art hoechstens ein Block am Tag, Minuten im Bereich der Art, nur gewuenschte Arten. */
export function normalizeWeekExtras(raw: readonly WeekExtraRaw[] | undefined, supplements: Supplements | undefined): WeekExtra[] {
  const seen = new Set<ExtraKind>();
  return (raw ?? []).flatMap((extra) => {
    if (perWeek(supplements, extra.kind) <= 0 || seen.has(extra.kind)) return [];
    seen.add(extra.kind);
    return [{ kind: extra.kind, minutes: clampMinutes(extra.kind, extra.minutes), focus: cleanFocus(extra.kind, extra.focus) }];
  });
}

function cleanExercise(raw: ExerciseRaw): Exercise | null {
  const name = raw.name.trim().slice(0, 80);
  if (name === "" || !Number.isFinite(raw.sets)) return null;
  const sets = Math.min(Math.max(Math.round(raw.sets), 1), EXERCISE_RULES.maxSets);
  const byTime = raw.seconds !== null && Number.isFinite(raw.seconds) && raw.seconds > 0;
  const reps = byTime ? null : Math.min(Math.max(Math.round(raw.reps ?? 10), 1), EXERCISE_RULES.maxReps);
  const seconds = byTime ? Math.min(Math.max(Math.round(raw.seconds as number), EXERCISE_RULES.minSeconds), EXERCISE_RULES.maxSeconds) : null;
  return {
    name,
    sets,
    reps,
    seconds,
    rest_seconds: Math.min(Math.max(Math.round(Number.isFinite(raw.rest_seconds) ? raw.rest_seconds : 0), 0), EXERCISE_RULES.maxRestSeconds),
    cue: raw.cue.trim().slice(0, MULTI_RULES.maxCueLength) || name.slice(0, MULTI_RULES.maxCueLength),
    instructions: raw.instructions.trim().slice(0, MULTI_RULES.maxInstructionLength)
  };
}

/** Wie `normalizeWeekExtras`, dazu die Uebungen (gekuerzt und in Bereichen). Ein Block ohne Uebung faellt weg. */
export function normalizeDayExtras(raw: readonly DayExtraRaw[] | undefined, allowed: ReadonlySet<ExtraKind>): DayExtra[] {
  const seen = new Set<ExtraKind>();
  return (raw ?? []).flatMap((extra) => {
    if (!allowed.has(extra.kind) || seen.has(extra.kind)) return [];
    const exercises = extra.exercises.flatMap((exercise) => cleanExercise(exercise) ?? []).slice(0, EXERCISE_RULES.maxExercises);
    if (exercises.length === 0) return [];
    seen.add(extra.kind);
    return [{ kind: extra.kind, minutes: clampMinutes(extra.kind, extra.minutes), focus: cleanFocus(extra.kind, extra.focus), exercises }];
  });
}
