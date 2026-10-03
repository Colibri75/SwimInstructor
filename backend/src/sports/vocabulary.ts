/**
 * Gemeinsamer Wortschatz fuer Schritte einer Einheit, ueber alle Sportarten. Die Werte sind Teil des
 * Vertrags mit der App (contracts/sports.json) und duerfen nicht umbenannt werden.
 */

/** Woran ein Schritt gemessen wird. */
export const STEP_MEASURES = ["distance", "duration", "repetitions"] as const;
export type StepMeasure = (typeof STEP_MEASURES)[number];

/** Woran sich die Intensitaet eines Schritts ausrichtet. */
export const STEP_TARGETS = [
  "pace_per_100m",
  "pace_per_km",
  "speed",
  "heart_rate_zone",
  "power",
  "cadence",
  "stroke_rate",
  "perceived_effort"
] as const;
export type StepTarget = (typeof STEP_TARGETS)[number];
