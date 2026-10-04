import { z } from "zod";
import { PERFORMANCE_SOURCES } from "../sports/performance";
import { LEGACY_SPORT_ID, SPORTS } from "../sports/registry";
import { STEP_TARGETS } from "../sports/vocabulary";

/**
 * Eingabe-Schema des Zustands-Snapshots (v1 und v2, siehe docs/AthleteStateSnapshot.md). Spiegelt das
 * JSON, das `AthleteStateSnapshot` in der App erzeugt.
 *
 * Bewusst ohne Freitextfelder, nur Zahlen, Enums und Datumswerte: Was hier validiert durchkommt, geht
 * in den Prompt. Unbekannte Felder werden beim Parsen verworfen und erreichen Claude nie.
 *
 * v2 ist v1 plus Gesamtziel, Werte je Sportart und Gesamtlast. Ein v1-Snapshot bleibt unveraendert (gleicher
 * Prompt wie vor v2); was neuer Code aus v2 braucht, liefern `trainingGoalOf` und `sportStatesOf` auch fuer v1.
 * Optional dazu (T2b): Leistungswerte mit Herkunft und die Zonen, die die App daraus gerechnet hat (`performance`).
 */
const distance = z.number().min(0).max(1_000_000);
const count = z.number().int().min(0).max(10_000);
const pace = z.number().min(20).max(1_200); // Sekunden pro 100 m
const days = z.number().int().min(0).max(100_000);
const signed = z.number().min(-100_000).max(100_000);

const v1Fields = {
  generated_at: z.iso.datetime(),
  goal: z.object({
    distance_meters: z.number().min(25).max(100_000),
    target_duration_seconds: z.number().min(60).max(1_000_000),
    target_pace_seconds_per_hundred_meters: pace,
    target_date: z.iso.datetime(),
    days_until_goal: days
  }),
  volume: z.object({
    last_seven_days_meters: distance,
    average_weekly_meters: distance,
    weekly_change_percent: signed.optional(),
    sessions_last_seven_days: count,
    sessions_last_four_weeks: count,
    longest_session_meters: distance
  }),
  pace: z.object({
    recent_pace_seconds_per_hundred_meters: pace.optional(),
    previous_pace_seconds_per_hundred_meters: pace.optional(),
    trend_seconds_per_hundred_meters: signed.optional(),
    gap_to_target_seconds_per_hundred_meters: signed.optional()
  }),
  load: z.object({
    days_since_last_workout: days.optional(),
    days_since_last_hard_session: days.optional()
  }),
  recovery: z.object({
    status: z.enum(["good", "moderate", "poor", "unknown"]),
    resting_heart_rate_deviation_bpm: signed.optional(),
    hrv_deviation_percent: signed.optional(),
    recent_average_sleep_hours: z.number().min(0).max(24).optional(),
    warning_signals: z.array(
      z.enum(["elevated_resting_heart_rate", "low_heart_rate_variability", "short_sleep"])
    )
  }),
  flags: z.array(
    z.enum(["training_pause", "volume_spike", "recovery_poor", "overreaching_risk", "goal_within_four_weeks"])
  )
};

/** Eine Sportart, die dieser Server kennt. Unbekannte (neuere App) lehnt er ab, statt sie still zu verwerfen. */
const sportId = z.string().refine((id) => SPORTS.get(id) !== undefined, { message: "unbekannte Sportart" });
const minutes = z.number().min(0).max(100_000);
const load = z.number().min(0).max(1_000_000);

/** Zielarten (P2): Wettkampf, Zeit ueber eine Strecke, Strecke schaffen (beide ohne Wettkampf), fit werden ohne Zieltag. */
export const GOAL_KINDS = ["race", "time", "distance", "fitness"] as const;
export type GoalKind = (typeof GOAL_KINDS)[number];

export const TIMES_OF_DAY = ["morning", "midday", "evening"] as const;

/**
 * Der Wochenraster (P2): je Wochentag (1 = Montag bis 7 = Sonntag), ob, wann und wie lange der Athlet trainiert, auf
 * Wunsch mit fester Sportart. Tage ohne Training sind feste Ruhetage.
 */
const ScheduleDaySchema = z.object({
  weekday: z.number().int().min(1).max(7),
  trains: z.boolean(),
  time_of_day: z.enum(TIMES_OF_DAY).optional(),
  max_minutes: z.number().int().min(0).max(600),
  sport: sportId.optional()
});

const TrainingGoalSchema = z
  .object({
    /** Vorlage, aus der das Ziel stammt (z. B. "triathlon_olympic"); fehlt bei einem eigenen Ziel. */
    template: z.string().regex(/^[a-z][a-z0-9_]{1,39}$/).optional(),
    /** Fehlt bei einer App vor P2: dann ein Wettkampf. */
    kind: z.enum(GOAL_KINDS).optional(),
    target_date: z.iso.datetime(),
    days_until_goal: days,
    training_days_per_week: z.number().int().min(1).max(7),
    weekly_hours: z.number().min(0.5).max(40),
    disciplines: z
      .array(
        z.object({
          sport: sportId,
          distance_meters: z.number().min(25).max(1_000_000),
          target_duration_seconds: z.number().min(60).max(1_000_000).optional()
        })
      )
      .max(8),
    emphasis: z.array(z.object({ sport: sportId, percent: z.number().int().min(0).max(100) })).min(1).max(16),
    weekly_schedule: z.array(ScheduleDaySchema).length(7).optional()
  })
  .superRefine((goal, ctx) => {
    if (goal.kind === "fitness" && goal.disciplines.length > 0) {
      ctx.addIssue({ code: "custom", path: ["disciplines"], message: "Fitnessziel ohne Disziplinen" });
    }
    if (goal.kind !== "fitness" && goal.disciplines.length === 0) {
      ctx.addIssue({ code: "custom", path: ["disciplines"], message: "Ziel ohne Disziplin" });
    }
    if (goal.weekly_schedule !== undefined) {
      const weekdays = goal.weekly_schedule.map((day) => day.weekday);
      if (new Set(weekdays).size !== weekdays.length) ctx.addIssue({ code: "custom", path: ["weekly_schedule"], message: "Wochentag doppelt" });
      if (!goal.weekly_schedule.some((day) => day.trains)) ctx.addIssue({ code: "custom", path: ["weekly_schedule"], message: "kein Trainingstag" });
      goal.weekly_schedule.forEach((day, index) => {
        if (day.trains && day.max_minutes < 15) ctx.addIssue({ code: "custom", path: ["weekly_schedule", index, "max_minutes"], message: "Trainingstag unter 15 min" });
      });
    }
    const emphasisSports = goal.emphasis.map((entry) => entry.sport);
    if (new Set(emphasisSports).size !== emphasisSports.length) {
      ctx.addIssue({ code: "custom", path: ["emphasis"], message: "Sportart doppelt" });
    }
    if (goal.emphasis.reduce((sum, entry) => sum + entry.percent, 0) !== 100) {
      ctx.addIssue({ code: "custom", path: ["emphasis"], message: "Schwerpunkte ergeben nicht 100 %" });
    }
    const disciplineSports = goal.disciplines.map((discipline) => discipline.sport);
    if (new Set(disciplineSports).size !== disciplineSports.length) {
      ctx.addIssue({ code: "custom", path: ["disciplines"], message: "Sportart doppelt" });
    }
    goal.disciplines.forEach((discipline, index) => {
      if (!goal.emphasis.some((entry) => entry.sport === discipline.sport && entry.percent > 0)) {
        ctx.addIssue({ code: "custom", path: ["disciplines", index, "sport"], message: "Disziplin ohne Schwerpunkt" });
      }
      const duration = discipline.target_duration_seconds;
      if (duration !== undefined && !SPORTS.plausibleGoal(discipline.sport, discipline.distance_meters, duration)) {
        ctx.addIssue({ code: "custom", path: ["disciplines", index, "target_duration_seconds"], message: "unplausibles Zieltempo" });
      }
    });
  });

const SportStateSchema = z.object({
  sport: sportId,
  sessions_last_seven_days: count,
  sessions_last_four_weeks: count,
  minutes_last_seven_days: minutes,
  average_weekly_minutes: minutes,
  meters_last_seven_days: distance,
  average_weekly_meters: distance,
  longest_session_meters: distance,
  longest_session_minutes: minutes,
  load_last_seven_days: load,
  average_weekly_load: load,
  days_since_last_session: days.optional()
});

const TotalLoadSchema = z.object({
  minutes_last_seven_days: minutes,
  average_weekly_minutes: minutes,
  load_last_seven_days: load,
  average_weekly_load: load,
  /** Last der letzten 7 Tage durch den Wochenschnitt der letzten 4 Wochen; fehlt ohne Vergleichswert. */
  acute_chronic_ratio: z.number().min(0).max(100).optional()
});

const metricId = z.string().regex(/^[a-z][a-z0-9_]{1,31}$/);

const PerformanceValueSchema = z.object({
  metric: metricId,
  value: z.number().positive().max(100_000),
  source: z.enum(PERFORMANCE_SOURCES),
  measured_at: z.iso.datetime()
});

const ZoneBound = z.number().min(0).max(100_000);

const ZonesSchema = z.object({
  target: z.enum(STEP_TARGETS),
  basis: metricId,
  zones: z
    .array(z.object({ zone: z.number().int().min(1).max(10), minimum: ZoneBound.optional(), maximum: ZoneBound.optional() }))
    .min(1)
    .max(10)
});

/**
 * Leistungswerte fuer alle Sportarten (`athlete`) und je Sportart. Jeder Wert muss zu seiner Sportart gehoeren und im
 * plausiblen Bereich liegen (dieselben Grenzen wie in der App, contracts/sports.json); jede Zone braucht ein Ziel der
 * Sportart und einen bekannten Grundwert.
 */
const PerformanceSchema = z
  .object({
    athlete: z.array(PerformanceValueSchema).max(16),
    sports: z
      .array(z.object({ sport: sportId, values: z.array(PerformanceValueSchema).max(16), zones: z.array(ZonesSchema).max(16) }))
      .max(16)
  })
  .superRefine((performance, ctx) => {
    const checkValues = (values: Array<{ metric: string; value: number }>, sport: string | undefined, path: Array<string | number>) => {
      const seen = new Set<string>();
      values.forEach((entry, index) => {
        const definition = SPORTS.metric(sport, entry.metric);
        if (definition === undefined) {
          ctx.addIssue({ code: "custom", path: [...path, index, "metric"], message: "unbekannter Leistungswert" });
        } else if (entry.value < definition.min || entry.value > definition.max) {
          ctx.addIssue({ code: "custom", path: [...path, index, "value"], message: "unplausibler Leistungswert" });
        }
        if (seen.has(entry.metric)) ctx.addIssue({ code: "custom", path: [...path, index, "metric"], message: "Leistungswert doppelt" });
        seen.add(entry.metric);
      });
    };
    checkValues(performance.athlete, undefined, ["athlete"]);
    const sports = new Set<string>();
    performance.sports.forEach((entry, index) => {
      if (sports.has(entry.sport)) ctx.addIssue({ code: "custom", path: ["sports", index, "sport"], message: "Sportart doppelt" });
      sports.add(entry.sport);
      checkValues(entry.values, entry.sport, ["sports", index, "values"]);
      entry.zones.forEach((zones, zonesIndex) => {
        if (!(SPORTS.get(entry.sport)?.targets.includes(zones.target) ?? false)) {
          ctx.addIssue({ code: "custom", path: ["sports", index, "zones", zonesIndex, "target"], message: "Ziel passt nicht zur Sportart" });
        }
        if (SPORTS.metric(entry.sport, zones.basis) === undefined && SPORTS.metric(undefined, zones.basis) === undefined) {
          ctx.addIssue({ code: "custom", path: ["sports", index, "zones", zonesIndex, "basis"], message: "unbekannter Grundwert" });
        }
      });
    });
  });

/**
 * Startniveau, das der Athlet selbst angibt (P1): Wochenumfang und laengste Einheit, die er zurzeit schafft (oder vor
 * der Pause geschafft hat), in der Einheit der Sportart (`plan_unit`: Meter oder Minuten), dazu sein Trainingsstand.
 */
const StartingLevelSchema = z.object({
  sport: sportId,
  weekly_amount: z.number().min(0).max(1_000_000),
  longest_session: z.number().min(0).max(1_000_000),
  status: z.enum(["regular", "short_break", "long_break", "beginner"]),
  reported_at: z.iso.datetime()
});

const SnapshotV1Schema = z.object({ schema_version: z.literal(1), ...v1Fields });

const SnapshotV2Schema = z
  .object({
    schema_version: z.literal(2),
    ...v1Fields,
    training_goal: TrainingGoalSchema,
    sports: z.array(SportStateSchema).max(16),
    total_load: TotalLoadSchema,
    performance: PerformanceSchema.optional(),
    starting_levels: z.array(StartingLevelSchema).max(16).optional()
  })
  .superRefine((snapshot, ctx) => {
    const ids = snapshot.sports.map((state) => state.sport);
    if (new Set(ids).size !== ids.length) ctx.addIssue({ code: "custom", path: ["sports"], message: "Sportart doppelt" });
    const levels = (snapshot.starting_levels ?? []).map((level) => level.sport);
    if (new Set(levels).size !== levels.length) ctx.addIssue({ code: "custom", path: ["starting_levels"], message: "Sportart doppelt" });
  });

export const SnapshotSchema = z.discriminatedUnion("schema_version", [SnapshotV1Schema, SnapshotV2Schema]);

export type Snapshot = z.infer<typeof SnapshotSchema>;
export type SnapshotV2 = z.infer<typeof SnapshotV2Schema>;
export type TrainingGoal = SnapshotV2["training_goal"];
export type ScheduleDay = NonNullable<TrainingGoal["weekly_schedule"]>[number];
export type SportState = SnapshotV2["sports"][number];
export type Performance = NonNullable<SnapshotV2["performance"]>;
export type StartingLevel = NonNullable<SnapshotV2["starting_levels"]>[number];
export type SnapshotFlag = Snapshot["flags"][number];


/**
 * Das Gesamtziel als v2, auch fuer einen v1-Snapshot: Dort ist es das Schwimmziel aus `goal`, mit Schwerpunkt
 * 100 % auf dieser einen Sportart. Trainingstage und Stunden kennt v1 nicht, sie kommen aus dem bisherigen Verlauf.
 */
export function trainingGoalOf(snapshot: Snapshot): TrainingGoal {
  if (snapshot.schema_version === 2) return snapshot.training_goal;
  const { goal, volume } = snapshot;
  return {
    target_date: goal.target_date,
    days_until_goal: goal.days_until_goal,
    training_days_per_week: Math.min(7, Math.max(1, Math.round(volume.sessions_last_four_weeks / 4))),
    weekly_hours: Math.min(40, Math.max(0.5, Math.round(((volume.average_weekly_meters / 100) * (snapshot.pace.recent_pace_seconds_per_hundred_meters ?? goal.target_pace_seconds_per_hundred_meters)) / 360) / 10)),
    disciplines: [{ sport: LEGACY_SPORT_ID, distance_meters: goal.distance_meters, target_duration_seconds: goal.target_duration_seconds }],
    emphasis: [{ sport: LEGACY_SPORT_ID, percent: 100 }]
  };
}

/**
 * Die Werte je Sportart als v2. Fuer einen v1-Snapshot nur die eine Sportart, ohne Minuten und Last (die kennt
 * v1 nicht): Sie fehlen dann als `undefined` statt geraten zu werden.
 */
export function sportStatesOf(snapshot: Snapshot): Array<Partial<SportState> & Pick<SportState, "sport">> {
  if (snapshot.schema_version === 2) return snapshot.sports;
  const { volume, load } = snapshot;
  return [
    {
      sport: LEGACY_SPORT_ID,
      sessions_last_seven_days: volume.sessions_last_seven_days,
      sessions_last_four_weeks: volume.sessions_last_four_weeks,
      meters_last_seven_days: volume.last_seven_days_meters,
      average_weekly_meters: volume.average_weekly_meters,
      longest_session_meters: volume.longest_session_meters,
      ...(load.days_since_last_workout !== undefined ? { days_since_last_session: load.days_since_last_workout } : {})
    }
  ];
}
