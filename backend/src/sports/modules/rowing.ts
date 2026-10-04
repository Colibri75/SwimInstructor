import { PerformanceMetricDefinition, THRESHOLD_HEART_RATE } from "../performance";
import { SportDefinition, SportPlanningContext, TargetRange } from "../types";
import { StepTarget } from "../vocabulary";
import { effortDistanceStep, effortStep, zoneRange } from "./shared";

/** Zeit fuer 2000 m in Sekunden, der Standardtest auf dem Ruderergometer. */
const TIME_2000M: PerformanceMetricDefinition = { id: "time_2000m", displayName: "2000-m-Zeit", unit: "s", min: 330, max: 1200 };

/** Nach Schlagzahl (Schlaege pro Minute), Pulszonen aus dem Profil und gefuehlter Anstrengung. */
function targetRange(target: StepTarget, context: SportPlanningContext): TargetRange | null {
  switch (target) {
    case "stroke_rate":
      return { min: 16, max: 40 };
    case "heart_rate_zone":
      return zoneRange(context, target);
    case "perceived_effort":
      return { min: 1, max: 10 };
    default:
      return null;
  }
}

/** 2000 m so schnell wie moeglich, davor Einrudern mit kurzen Steigerungen. */
const TEST_SESSIONS = {
  time_trial_2000m: [
    effortStep("Einrudern", 10, 3, "Locker einrudern", "Locker einrudern, Schlagzahl um 20."),
    effortStep("Steigerung", 0.5, 7, "Steigern", "30 Sekunden zügig mit höherer Schlagzahl, dann locker weiter.", 3, 60),
    effortDistanceStep("Test 2000 m", 2000, 10, "2000 m Vollgas", "2000 m so schnell wie möglich und gleichmäßig. Die ersten 500 m nicht zu schnell."),
    effortStep("Ausrudern", 5, 2, "Locker ausrudern", "Ganz locker ausrudern.")
  ]
};

/** Rudern, auf dem Ergometer und auf dem Wasser. */
export const rowing: SportDefinition = {
  id: "rowing",
  displayName: "Rudern",
  measures: ["duration", "distance"],
  targets: ["stroke_rate", "heart_rate_zone", "perceived_effort"],
  // 4:10 bis 1:11 pro 500 m.
  goalSpeed: { minMetersPerSecond: 2, maxMetersPerSecond: 7 },
  loadFactor: 0.9,
  performanceMetrics: [THRESHOLD_HEART_RATE, TIME_2000M],
  performanceTests: [
    { id: "time_trial_2000m", displayName: "2000-m-Test", produces: [TIME_2000M.id, THRESHOLD_HEART_RATE.id], maximalEffort: true, durationMinutes: 8 }
  ],
  planning: {
    limitUnit: "minutes",
    limits: {
      sessionGrowthFactor: 1.2,
      minSessionCap: 40,
      absoluteMaxSession: 150,
      weeklyGrowthFactor: 1.25,
      minWeeklyCap: 80,
      minSession: 20,
      pauseSessionCap: 30,
      pauseAfterDays: 10,
      maxSessionsPerWeek: 4,
      macroGrowthFactor: 1.1,
      amountStep: 5
    },
    // 2:23 pro 500 m.
    typicalSpeedMetersPerSecond: 3.5,
    stepMeasures: ["duration", "distance"],
    distanceStepMeters: 250,
    minStepMeters: 250,
    maxStepMeters: 20_000,
    minStepSeconds: 30,
    maxStepSeconds: 2 * 3600,
    targetRange,
    testSessions: TEST_SESSIONS,
    equipment: {},
    promptRules: `- Gesteuert über die Schlagzahl (stroke_rate, Schläge pro Minute: Grundlage 18 bis 22, Schwelle 24 bis 28), Pulszonen (heart_rate_zone 1 bis 5 nach Prozent des Schwellenpulses: 1 unter 80 %, 2 80 bis 87 %, 3 88 bis 93 %, 4 94 bis 99 %, 5 ab 100 %) oder die gefühlte Anstrengung (perceived_effort).
- Schritte nach Dauer (measure duration) oder Strecke (measure distance, Vielfache von 250 m, zum Beispiel 4 mal 500 m).
- Grundlage ist langes, lockeres Rudern mit niedriger Schlagzahl; harte Intervalle höchstens einmal pro Woche.`
  }
};
