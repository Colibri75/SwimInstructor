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
  targets: ["stroke_rate", "power", "heart_rate_zone"]
};
