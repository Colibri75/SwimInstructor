import { SportDefinition } from "../types";

/** Laufen, draussen und auf dem Laufband. */
export const run: SportDefinition = {
  id: "run",
  displayName: "Laufen",
  measures: ["distance", "duration"],
  targets: ["pace_per_km", "heart_rate_zone", "cadence", "perceived_effort"]
};
