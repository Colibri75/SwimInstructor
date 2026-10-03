/**
 * Leistungswerte (Maximalpuls, Schwellenpuls, CSS ...) und Leistungstests. Die App rechnet daraus Zonen und schickt
 * beides im Snapshot v2 mit (`performance`); der Server prueft die Werte gegen dieselben Grenzen wie die App
 * (contracts/sports.json). Was eine einzelne Sportart misst, steht in ihrer Definition unter modules/.
 */

/** Was ein Leistungswert bedeutet und welche Werte plausibel sind. */
export interface PerformanceMetricDefinition {
  /** Kennung wie bei Sportarten, z. B. "threshold_heart_rate". */
  readonly id: string;
  readonly displayName: string;
  /** "bpm", "W", "s/100m", "s/km" oder "s". */
  readonly unit: string;
  readonly min: number;
  readonly max: number;
}

/** Ein Leistungstest einer Sportart. Wann er im Plan steht, entscheidet die Planung (T3). */
export interface PerformanceTestDefinition {
  /** Kennung wie bei Sportarten, eindeutig innerhalb der Sportart. */
  readonly id: string;
  readonly displayName: string;
  /** Die Leistungswerte der Sportart, die der Test ermittelt. */
  readonly produces: readonly string[];
  /** Vollbelastung: harte Einheit, das Ergebnis gilt als getestet. Sonst (Einstiegstest) bleibt es eine Schaetzung. */
  readonly maximalEffort: boolean;
  /** Dauer der eigentlichen Testbelastung ohne Ein- und Auslaufen. */
  readonly durationMinutes: number;
}

/** Woher ein Wert stammt: Test und eigene Eingabe sind bestaetigt, Schaetzung aus Health, Faustformel. */
export const PERFORMANCE_SOURCES = ["tested", "manual", "estimated", "formula"] as const;
export type PerformanceSource = (typeof PERFORMANCE_SOURCES)[number];

export const MAX_HEART_RATE: PerformanceMetricDefinition = { id: "max_heart_rate", displayName: "Maximalpuls", unit: "bpm", min: 120, max: 230 };
export const RESTING_HEART_RATE: PerformanceMetricDefinition = { id: "resting_heart_rate", displayName: "Ruhepuls", unit: "bpm", min: 30, max: 110 };
export const THRESHOLD_HEART_RATE: PerformanceMetricDefinition = { id: "threshold_heart_rate", displayName: "Schwellenpuls", unit: "bpm", min: 100, max: 215 };
export const THRESHOLD_POWER: PerformanceMetricDefinition = { id: "threshold_power", displayName: "Schwellenleistung (FTP)", unit: "W", min: 50, max: 600 };

/** Die Werte, die fuer alle Sportarten gelten (ohne Sportart im Snapshot). */
export const ATHLETE_METRICS: readonly PerformanceMetricDefinition[] = [MAX_HEART_RATE, RESTING_HEART_RATE];
