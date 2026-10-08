import { readFileSync } from "node:fs";
import path from "node:path";
import { MacroWeeksRaw, MultiDayPlanRaw, MultiMacroPlanRaw, MultiWeekPlanRaw, StepRaw } from "../../../src/plan/multi/schemas";
import { SnapshotSchema, SnapshotV2, SportState } from "../../../src/plan/snapshot";

/**
 * Bausteine fuer die Tests der Planung fuer mehrere Sportarten. Grundlage ist der Snapshot v2 mit Profil aus
 * contracts/ (Olympische Distanz, Schwerpunkt Schwimmen 40 / Rad 35 / Laufen 25, Laufen ohne Verlauf).
 */
const CONTRACTS = path.join(__dirname, "../../../../contracts");

export const TODAY = "2026-09-30";

export function contractSnapshot(file = "wire/snapshot-v2-profile.json"): SnapshotV2 {
  return SnapshotSchema.parse(JSON.parse(readFileSync(path.join(CONTRACTS, file), "utf8"))) as SnapshotV2;
}

export interface SnapshotPatch {
  sports?: Record<string, Partial<SportState>>;
  recovery?: Partial<SnapshotV2["recovery"]>;
  flags?: SnapshotV2["flags"];
  load?: Partial<SnapshotV2["load"]>;
  goal?: Partial<SnapshotV2["training_goal"]>;
  /** Tage bis zum Ziel: setzt Zieltag und Tage im Gesamtziel (ab 2026-09-30). */
  daysUntilGoal?: number;
  performance?: SnapshotV2["performance"] | null;
  startingLevels?: SnapshotV2["starting_levels"];
}

function shiftDate(iso: string, days: number): string {
  const date = new Date(`${iso}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function multiSnapshot(patch: SnapshotPatch = {}): SnapshotV2 {
  const base = contractSnapshot();
  const sports = base.sports.map((state) => ({ ...state, ...(patch.sports?.[state.sport] ?? {}) }));
  for (const [sport, values] of Object.entries(patch.sports ?? {})) {
    if (!sports.some((state) => state.sport === sport)) sports.push({ ...emptyState(sport), ...values });
  }
  let goal = { ...base.training_goal, ...patch.goal };
  if (patch.daysUntilGoal !== undefined) {
    const day = shiftDate(TODAY, patch.daysUntilGoal);
    goal = { ...goal, target_date: `${day}T10:00:00Z`, days_until_goal: Math.max(patch.daysUntilGoal, 0) };
  }
  const result: SnapshotV2 = {
    ...base,
    recovery: { ...base.recovery, ...patch.recovery },
    flags: patch.flags ?? base.flags,
    load: { ...base.load, ...patch.load },
    training_goal: goal,
    sports
  };
  if (patch.performance === null) delete result.performance;
  else if (patch.performance !== undefined) result.performance = patch.performance;
  if (patch.startingLevels !== undefined) result.starting_levels = patch.startingLevels;
  return result;
}

export function emptyState(sport: string): SportState {
  return {
    sport,
    sessions_last_seven_days: 0,
    sessions_last_four_weeks: 0,
    minutes_last_seven_days: 0,
    average_weekly_minutes: 0,
    meters_last_seven_days: 0,
    average_weekly_meters: 0,
    longest_session_meters: 0,
    longest_session_minutes: 0,
    load_last_seven_days: 0,
    average_weekly_load: 0
  };
}

/** Ein trainierter Laeufer: 4 Laeufe pro Woche, laengster 60 min. */
export const RUNNER: Partial<SportState> = {
  sessions_last_seven_days: 3,
  sessions_last_four_weeks: 12,
  minutes_last_seven_days: 150,
  average_weekly_minutes: 160,
  meters_last_seven_days: 28_000,
  average_weekly_meters: 30_000,
  longest_session_meters: 11_000,
  longest_session_minutes: 60,
  load_last_seven_days: 150,
  average_weekly_load: 160,
  days_since_last_session: 1
};

export function step(patch: Partial<StepRaw> = {}): StepRaw {
  return {
    name: "Hauptteil",
    repetitions: 1,
    measure: "duration",
    distance_meters: null,
    duration_seconds: 1200,
    target_type: "perceived_effort",
    target_value: 3,
    rest_seconds: 0,
    instructions: "Locker und gleichmäßig.",
    cue: "Locker",
    equipment: [],
    ...patch
  };
}

export function swimStep(meters: number, patch: Partial<StepRaw> = {}): StepRaw {
  return step({ measure: "distance", distance_meters: meters, duration_seconds: null, ...patch });
}

export function dayPlan(sessions: MultiDayPlanRaw["sessions"], rationale = "Lockerer Tag mit Bezug zum Ziel, 3500 m in 7 Tagen."): MultiDayPlanRaw {
  return { rationale, sessions, coach_notes: ["Viel trinken."] };
}

export function session(sport: string, patch: Partial<MultiDayPlanRaw["sessions"][number]> = {}): MultiDayPlanRaw["sessions"][number] {
  return {
    sport,
    session_type: "endurance",
    intensity: "easy",
    focus: "Grundlage",
    test_id: null,
    steps: [step({ name: "Einlaufen", duration_seconds: 600 }), step({ duration_seconds: 1200 }), step({ name: "Auslaufen", duration_seconds: 300 })],
    ...patch
  };
}

export function weekDates(from = TODAY, count = 7): string[] {
  return Array.from({ length: count }, (_, index) => shiftDate(from, index));
}

export function weekPlan(days: Array<MultiWeekPlanRaw["days"][number]["sessions"]>, from = TODAY): MultiWeekPlanRaw {
  return {
    rationale: "Woche mit Grundlage in allen drei Sportarten, Ziel im Blick.",
    days: weekDates(from, Math.max(7, days.length)).map((date, index) => ({ date, focus: (days[index] ?? []).length > 0 ? "Training" : "Ruhetag", sessions: days[index] ?? [] }))
  };
}

export function weekSession(sport: string, amount: number, patch: Partial<MultiWeekPlanRaw["days"][number]["sessions"][number]> = {}): MultiWeekPlanRaw["days"][number]["sessions"][number] {
  return { sport, session_type: "endurance", intensity: "easy", amount, focus: "Grundlage", test_id: null, ...patch };
}

export function macroPlan(weeks: string[], amounts: (index: number) => Record<string, number>, deload: (index: number) => boolean = () => false): MacroWeeksRaw {
  return {
    rationale: "Aufbau bis zum Ziel in 40 Wochen, Höhepunkt vor dem Zuspitzen.",
    weeks: weeks.map((week_start, index) => ({
      week_start,
      deload: deload(index),
      focus: "Grundlage",
      sports: Object.entries(amounts(index)).map(([sport, amount]) => ({ sport, amount, sessions: 3 }))
    }))
  };
}

/** Derselbe Plan, wie Claude ihn liefert: jede Woche ein eigener Abschnitt, mit genau ihren Umfaengen. */
export function asBlocks(plan: MacroWeeksRaw): MultiMacroPlanRaw {
  return {
    rationale: plan.rationale,
    blocks: plan.weeks.map((week) => ({
      weeks: 1,
      deload_last: week.deload,
      focus: week.focus,
      sports: week.sports.map((entry) => ({
        sport: entry.sport,
        start_amount: entry.amount,
        end_amount: entry.amount,
        deload_amount: week.deload ? entry.amount : null,
        sessions: entry.sessions
      }))
    }))
  };
}

/** Ein selbst angegebenes Startniveau, angegeben am Tag des Snapshots (oder `daysAgo` davor). */
export function startingLevel(
  sport: string,
  weekly: number,
  longest: number,
  status: NonNullable<SnapshotV2["starting_levels"]>[number]["status"],
  daysAgo = 0
): NonNullable<SnapshotV2["starting_levels"]>[number] {
  const reported = new Date(Date.parse("2026-09-30T12:00:00Z") - daysAgo * 86_400_000).toISOString();
  return { sport, weekly_amount: weekly, longest_session: longest, status, reported_at: reported };
}
