import { PerformanceMetricDefinition, THRESHOLD_HEART_RATE } from "../performance";
import { SportDefinition } from "../types";

/** Schwellentempo in Sekunden pro km. */
const THRESHOLD_PACE: PerformanceMetricDefinition = { id: "threshold_pace_per_km", displayName: "Schwellentempo", unit: "s/km", min: 150, max: 900 };

/** Laufen, draussen und auf dem Laufband. */
export const run: SportDefinition = {
  id: "run",
  displayName: "Laufen",
  measures: ["distance", "duration"],
  targets: ["pace_per_km", "heart_rate_zone", "cadence", "perceived_effort"],
  // 16:40 bis 2:23 pro km.
  goalSpeed: { minMetersPerSecond: 1, maxMetersPerSecond: 7 },
  loadFactor: 1,
  performanceMetrics: [THRESHOLD_HEART_RATE, THRESHOLD_PACE],
  performanceTests: [
    {
      id: "threshold_30min",
      displayName: "30-Minuten-Test",
      produces: [THRESHOLD_HEART_RATE.id, THRESHOLD_PACE.id],
      maximalEffort: true,
      durationMinutes: 30
    },
    // Fuer Einsteiger: locker nach Gefuehl, das Ergebnis bleibt eine Schaetzung.
    { id: "entry_easy_25min", displayName: "Einstiegstest locker", produces: [THRESHOLD_PACE.id], maximalEffort: false, durationMinutes: 25 }
  ]
};
