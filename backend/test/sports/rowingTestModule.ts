import { THRESHOLD_HEART_RATE } from "../../src/sports/performance";
import { SportDefinition } from "../../src/sports/types";

/**
 * Erfundene Sportart nur fuer Tests, mit anderer Logik als die drei echten: geplant nach Zeit, Intensitaet nach
 * Schlagzahl. Laeuft durch dieselben Pruefungen wie Schwimmen, Rad und Laufen. Bricht sie, ist der Kern nicht
 * mehr allgemein genug fuer weitere Sportarten. Gegenstueck in Swift: RowingTestModule.
 */
export const rowingTestSport: SportDefinition = {
  id: "rowing",
  displayName: "Rudern",
  measures: ["duration", "distance"],
  targets: ["stroke_rate", "power", "heart_rate_zone"],
  goalSpeed: { minMetersPerSecond: 0.5, maxMetersPerSecond: 7 },
  loadFactor: 0.9,
  // Eigener Wert und eigener Test, die keine echte Sportart kennt.
  performanceMetrics: [THRESHOLD_HEART_RATE, { id: "time_2000m", displayName: "2000-m-Zeit", unit: "s", min: 330, max: 1200 }],
  performanceTests: [
    { id: "time_trial_2000m", displayName: "2000-m-Test", produces: ["time_2000m", THRESHOLD_HEART_RATE.id], maximalEffort: true, durationMinutes: 8 }
  ]
};
