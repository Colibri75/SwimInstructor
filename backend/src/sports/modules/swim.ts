import { PerformanceMetricDefinition } from "../performance";
import { SportDefinition } from "../types";

/** Critical Swim Speed als Pace in Sekunden pro 100 m. */
const CSS_PACE: PerformanceMetricDefinition = { id: "css_pace_per_100m", displayName: "CSS-Pace", unit: "s/100m", min: 50, max: 300 };

/** Schwimmen, im Becken und im Freiwasser. */
export const swim: SportDefinition = {
  id: "swim",
  displayName: "Schwimmen",
  measures: ["distance", "duration"],
  targets: ["pace_per_100m", "heart_rate_zone", "perceived_effort"],
  // 10:00 bis 0:40 pro 100 m, wie die bisherige Zielpruefung der App.
  goalSpeed: { minMetersPerSecond: 0.15, maxMetersPerSecond: 2.5 },
  loadFactor: 1,
  performanceMetrics: [CSS_PACE],
  performanceTests: [
    { id: "css_400_200", displayName: "CSS-Test 400/200 m", produces: [CSS_PACE.id], maximalEffort: true, durationMinutes: 10 },
    { id: "time_trial_1000m", displayName: "1000-m-Test", produces: [CSS_PACE.id], maximalEffort: true, durationMinutes: 20 }
  ]
};
