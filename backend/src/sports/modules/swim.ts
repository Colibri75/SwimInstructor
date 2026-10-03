import { SportDefinition } from "../types";

/** Schwimmen, im Becken und im Freiwasser. */
export const swim: SportDefinition = {
  id: "swim",
  displayName: "Schwimmen",
  measures: ["distance", "duration"],
  targets: ["pace_per_100m", "heart_rate_zone", "perceived_effort"],
  // 10:00 bis 0:40 pro 100 m, wie die bisherige Zielpruefung der App.
  goalSpeed: { minMetersPerSecond: 0.15, maxMetersPerSecond: 2.5 }
};
