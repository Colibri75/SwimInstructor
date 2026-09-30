import { z } from "zod";

/**
 * Eingabe-Schema des Zustands-Snapshots (Schema v1, siehe docs/AthleteStateSnapshot.md). Spiegelt das
 * JSON, das `AthleteStateSnapshot` in der App erzeugt.
 *
 * Bewusst ohne Freitextfelder, nur Zahlen, Enums und Datumswerte: Was hier validiert durchkommt, geht
 * in den Prompt. Unbekannte Felder werden beim Parsen verworfen und erreichen Claude nie.
 */
const distance = z.number().min(0).max(1_000_000);
const count = z.number().int().min(0).max(10_000);
const pace = z.number().min(20).max(1_200); // Sekunden pro 100 m
const days = z.number().int().min(0).max(100_000);
const signed = z.number().min(-100_000).max(100_000);

export const SnapshotSchema = z.object({
  schema_version: z.literal(1),
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
});

export type Snapshot = z.infer<typeof SnapshotSchema>;
export type SnapshotFlag = Snapshot["flags"][number];
