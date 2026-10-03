import { SportDefinition } from "../types";

/** Schwimmen, im Becken und im Freiwasser. */
export const swim: SportDefinition = {
  id: "swim",
  displayName: "Schwimmen",
  measures: ["distance", "duration"],
  targets: ["pace_per_100m", "heart_rate_zone", "perceived_effort"]
};
