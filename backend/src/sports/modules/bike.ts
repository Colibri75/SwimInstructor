import { THRESHOLD_HEART_RATE, THRESHOLD_POWER } from "../performance";
import { SportDefinition } from "../types";

/** Radfahren, draussen und auf der Rolle. Ohne Wattmessung nach Puls und gefuehlter Anstrengung. */
export const bike: SportDefinition = {
  id: "bike",
  displayName: "Radfahren",
  measures: ["duration", "distance"],
  targets: ["power", "heart_rate_zone", "speed", "cadence", "perceived_effort"],
  // 7,2 bis 72 km/h.
  goalSpeed: { minMetersPerSecond: 2, maxMetersPerSecond: 20 },
  loadFactor: 0.8,
  performanceMetrics: [THRESHOLD_HEART_RATE, THRESHOLD_POWER],
  performanceTests: [
    {
      id: "threshold_30min",
      displayName: "30-Minuten-Test",
      produces: [THRESHOLD_HEART_RATE.id, THRESHOLD_POWER.id],
      maximalEffort: true,
      durationMinutes: 30
    }
  ]
};
