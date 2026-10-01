import { PlanSet, TrainingPlan } from "../../src/plan/plan";
import { Snapshot } from "../../src/plan/snapshot";

/** Gesunder Durchschnittsschwimmer: Ziel 3,8 km unter 60 min, mittleres Volumen, gut erholt. */
export const baseSnapshot: Snapshot = {
  schema_version: 1,
  generated_at: "2026-09-30T12:00:00Z",
  goal: {
    distance_meters: 3800,
    target_duration_seconds: 3600,
    target_pace_seconds_per_hundred_meters: 94.7,
    target_date: "2027-07-04T10:00:00Z",
    days_until_goal: 277
  },
  volume: {
    last_seven_days_meters: 1500,
    average_weekly_meters: 3000,
    sessions_last_seven_days: 2,
    sessions_last_four_weeks: 8,
    longest_session_meters: 2000
  },
  pace: { recent_pace_seconds_per_hundred_meters: 120 },
  load: { days_since_last_workout: 2, days_since_last_hard_session: 4 },
  recovery: { status: "good", warning_signals: [] },
  flags: []
};

type SnapshotPatch = {
  volume?: Partial<Snapshot["volume"]>;
  pace?: Partial<Snapshot["pace"]>;
  load?: Partial<Snapshot["load"]>;
  recovery?: Partial<Snapshot["recovery"]>;
  goal?: Partial<Snapshot["goal"]>;
  flags?: Snapshot["flags"];
};

export function snapshot(patch: SnapshotPatch = {}): Snapshot {
  return {
    ...baseSnapshot,
    goal: { ...baseSnapshot.goal, ...patch.goal },
    volume: { ...baseSnapshot.volume, ...patch.volume },
    pace: { ...baseSnapshot.pace, ...patch.pace },
    load: { ...baseSnapshot.load, ...patch.load },
    recovery: { ...baseSnapshot.recovery, ...patch.recovery },
    flags: patch.flags ?? baseSnapshot.flags
  };
}

export function set(overrides: Partial<PlanSet> = {}): PlanSet {
  return {
    name: "Hauptsatz",
    repetitions: 1,
    distance_meters: 200,
    target_pace_seconds_per_hundred_meters: null,
    rest_seconds: 20,
    instructions: "gleichmäßig",
    equipment: [],
    ...overrides
  };
}

/** Sinnvoller Ausdauertag: 200 Einschwimmen + 6x200 + 200 Ausschwimmen = 1600 m. */
export const goodPlan: TrainingPlan = {
  session_type: "endurance",
  intensity: "moderate",
  rationale: "Solider Ausdauertag, passend zum Wochenumfang.",
  total_distance_meters: 1600,
  estimated_duration_minutes: 45,
  sets: [
    set({ name: "Einschwimmen", repetitions: 1, distance_meters: 200, rest_seconds: 0 }),
    set({ name: "Hauptsatz", repetitions: 6, distance_meters: 200, target_pace_seconds_per_hundred_meters: 140, rest_seconds: 30 }),
    set({ name: "Ausschwimmen", repetitions: 1, distance_meters: 200, rest_seconds: 0 })
  ],
  coach_notes: ["Auf lockere Atmung achten."]
};

export function plan(overrides: Partial<TrainingPlan> = {}): TrainingPlan {
  return { ...goodPlan, ...overrides };
}

export const sum = (sets: PlanSet[]): number => sets.reduce((total, s) => total + s.repetitions * s.distance_meters, 0);

/** Ein Plan, der in `meters` Metern aus Einschwimmen, Hauptsatz (200er) und Ausschwimmen besteht. */
export function planOfMeters(meters: number, overrides: Partial<TrainingPlan> = {}): TrainingPlan {
  const main = Math.round((meters - 400) / 200);
  const sets = [
    set({ name: "Einschwimmen", distance_meters: 200, rest_seconds: 0 }),
    set({ name: "Hauptsatz", repetitions: main, distance_meters: 200, target_pace_seconds_per_hundred_meters: 140, rest_seconds: 30 }),
    set({ name: "Ausschwimmen", distance_meters: 200, rest_seconds: 0 })
  ];
  return plan({ sets, total_distance_meters: sum(sets), ...overrides });
}
