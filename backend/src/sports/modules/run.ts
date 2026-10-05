import { PerformanceMetricDefinition, THRESHOLD_HEART_RATE } from "../performance";
import { SportDefinition, SportPlanningContext, TargetRange } from "../types";
import { StepTarget } from "../vocabulary";
import { effortStep, paceRange, performanceValue, recentPaceSeconds, zoneRange } from "./shared";

/** Schwellentempo in Sekunden pro km. */
const THRESHOLD_PACE: PerformanceMetricDefinition = { id: "threshold_pace_per_km", displayName: "Schwellentempo", unit: "s/km", min: 150, max: 900 };

/**
 * Mit bekanntem Schwellentempo: nicht schneller als 85 % davon (Intervalle liegen bei etwa 90 bis 95 %). Sonst nach
 * Verlauf und Zielpace. Pulszonen nur, wenn die App sie aus dem Profil gerechnet hat.
 */
function targetRange(target: StepTarget, context: SportPlanningContext): TargetRange | null {
  const { state, discipline } = context;
  switch (target) {
    case "pace_per_km": {
      const threshold = performanceValue(context, THRESHOLD_PACE.id);
      if (threshold !== undefined) return { min: Math.round(threshold * 0.85), max: 900 };
      const goal = discipline?.target_duration_seconds !== undefined ? (discipline.target_duration_seconds / discipline.distance_meters) * 1000 : undefined;
      // Intervalle duerfen deutlich schneller sein als der Schnitt (der Gehpausen und lockere Laeufe enthaelt), aber nicht
      // schneller als 90 % der Zielpace; ohne Verlauf nur langsamer als das Ziel.
      return paceRange({ recent: recentPaceSeconds(state, 1000), goal, recentFactor: 0.7, goalFactor: 0.9, unknownGoalFactor: 1.2, absoluteFastest: 150, slowest: 900 });
    }
    case "heart_rate_zone":
      return zoneRange(context, target);
    case "perceived_effort":
      return { min: 1, max: 10 };
    case "cadence":
      return { min: 140, max: 200 };
    default:
      return null;
  }
}

/**
 * Die Testeinheiten. Der 30-Minuten-Test (Friel) setzt voraus, dass der Athlet schon gut 40 Minuten am Stueck laeuft
 * (die Einheit ist 47 Minuten lang und haelt die 10-%-Regel ein); sonst gibt es den lockeren Einstiegstest.
 */
const TEST_SESSIONS = {
  threshold_30min: [
    effortStep("Einlaufen", 10, 3, "Locker einlaufen", "Locker einlaufen, du kannst dich noch unterhalten."),
    effortStep("Steigerung", 20 / 60, 7, "Steigern", "20 Sekunden zügig, dann locker weiter.", 2, 40),
    effortStep(
      "Test 30 Minuten",
      30,
      9,
      "30 min hart, gleichmäßig",
      "30 Minuten allein so schnell, wie du sie gleichmäßig durchhältst, wie im Wettkampf. Nicht zu schnell anfangen. Am besten auf einer flachen Runde oder der Bahn.",
      1,
      0
    ),
    effortStep("Auslaufen", 5, 2, "Locker auslaufen", "Ganz locker auslaufen oder gehen.")
  ],
  entry_easy_25min: [
    effortStep(
      "Lauf locker",
      25,
      3,
      "Locker, gleichmäßig",
      "25 Minuten locker und gleichmäßig, so dass du dich noch unterhalten kannst. Pace und Puls ergeben eine erste Schätzung deiner Schwelle.",
      1,
      0
    ),
    effortStep("Gehen", 5, 1, "Gehen", "Fünf Minuten gehen.")
  ]
};

/** Laufen, draussen und auf dem Laufband. Die verletzungstraechtigste Disziplin: strengste Grenzen. */
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
  ],
  planning: {
    limitUnit: "minutes",
    limits: {
      // Eine Einheit hoechstens 10 % laenger als die laengste der letzten 4 Wochen (Frandsen et al., BJSM 2025: dort
      // 30 Tage und Strecke, hier 28 Tage und Dauer aus dem Snapshot).
      sessionGrowthFactor: 1.1,
      minSessionCap: 30,
      absoluteMaxSession: 210,
      // Harte Obergrenze +30 % (Nielsen et al. 2014); geplant wird mit etwa +10 %, das sagt der Prompt.
      weeklyGrowthFactor: 1.3,
      minWeeklyCap: 60,
      minSession: 15,
      pauseSessionCap: 20,
      pauseAfterDays: 14,
      maxSessionsPerWeek: 4,
      macroGrowthFactor: 1.1,
      amountStep: 5
    },
    // Laufen vorsichtiger: nach einer Pause hoechstens die Stufe darunter, nach langer Pause zaehlt die Angabe nicht
    // (Wiedereinstieg wie ohne Angabe); zurueck nur mit den ueblichen 10 % pro Woche.
    startingLevel: {
      factors: { regular: 1, short_break: 0.5, long_break: 0 },
      returnGrowthFactor: 1.1
    },
    // 6:00 pro km.
    typicalSpeedMetersPerSecond: 2.8,
    stepMeasures: ["duration", "distance"],
    distanceStepMeters: 100,
    minStepMeters: 100,
    maxStepMeters: 50_000,
    minStepSeconds: 10,
    maxStepSeconds: 4 * 3600,
    targetRange,
    testSessions: TEST_SESSIONS,
    equipment: {},
    // Der klassische Koppellauf direkt nach dem Rad (Wechsel 2); auf dem Laufband ohne Wetter.
    brickAfter: ["bike"],
    weatherSensitive: true,
    indoor: { equipment: "treadmill", displayName: "Laufband" },
    canFuelDuringRace: true,
    promptRules: `- Laufen ist im Triathlon die verletzungsträchtigste Disziplin und hat die strengsten Grenzen. Keine Laufeinheit ist mehr als 10 % länger als die längste der letzten 4 Wochen (longest_session_minutes im Snapshot). Der Laufumfang steigt pro Woche um etwa 10 %, auch wenn die Grenzen mehr erlauben, und nicht mehrere Wochen hintereinander am oberen Rand.
- Rund 80 % der Laufzeit sind locker (Zone 1 bis 2, Gespräch möglich). Schwelle und Intervalle erst auf einer stabilen Grundlage, höchstens eine harte Laufeinheit pro Woche.
- Gesteuert über die Pace (target_type pace_per_km, target_value in Sekunden pro km), Pulszonen (heart_rate_zone 1 bis 5 nach Prozent der Lauf-Schwellenherzfrequenz: 1 unter 85 %, 2 85 bis 89 %, 3 90 bis 94 %, 4 95 bis 99 %, 5 ab 100 %) oder die gefühlte Anstrengung (perceived_effort). Einsteiger und Wiedereinsteiger laufen nach gefühlter Anstrengung, gern mit Gehpausen (eigener Schritt "Gehen"), nicht nach Pace.
- Schritte nach Dauer (measure duration) oder Strecke (measure distance, Vielfache von 100 m, zum Beispiel 6 mal 400 m).
- Nennt der Athlet Schmerzen beim Laufen (Wunsch oder Feedback), ersetze die nächsten Laufeinheiten durch Rad oder Schwimmen und rate bei anhaltenden Beschwerden zu ärztlichem Rat.
- Ein Koppellauf direkt nach dem Rad zählt voll für die Laufgrenzen.`
  }
};
