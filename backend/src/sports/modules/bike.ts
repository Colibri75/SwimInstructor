import { SportDefinition } from "../types";

/** Radfahren, draussen und auf der Rolle. Ohne Wattmessung nach Puls und gefuehlter Anstrengung. */
export const bike: SportDefinition = {
  id: "bike",
  displayName: "Radfahren",
  measures: ["duration", "distance"],
  targets: ["power", "heart_rate_zone", "speed", "cadence", "perceived_effort"],
  // 7,2 bis 72 km/h.
  goalSpeed: { minMetersPerSecond: 2, maxMetersPerSecond: 20 }
};
