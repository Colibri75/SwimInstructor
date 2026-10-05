import { THRESHOLD_HEART_RATE } from "../../src/sports/performance";
import { SessionStep, SportDefinition, SportPlanningContext, TargetRange } from "../../src/sports/types";
import { StepTarget } from "../../src/sports/vocabulary";

const step = (name: string, patch: Partial<SessionStep>): SessionStep => ({
  name,
  repetitions: 1,
  measure: "duration",
  distance_meters: null,
  duration_seconds: 600,
  target_type: null,
  target_value: null,
  rest_seconds: 0,
  instructions: name,
  cue: name,
  equipment: [],
  ...patch
});

/** Nach Schlagzahl und Puls (mit Zonen); Watt gibt es hier nie, gefuehlte Anstrengung kennt die Sportart nicht. */
function targetRange(target: StepTarget, context: SportPlanningContext): TargetRange | null {
  if (target === "stroke_rate") return { min: 16, max: 40 };
  if (target === "heart_rate_zone") return context.performance?.zoneTargets.includes(target) === true ? { min: 1, max: 5 } : null;
  return null;
}

/**
 * Erfundene Sportart nur fuer Tests, mit anderer Logik als die drei echten: geplant nach Zeit, Intensitaet nach
 * Schlagzahl, ohne gefuehlte Anstrengung. Laeuft durch dieselben Pruefungen wie Schwimmen, Rad und Laufen. Bricht sie,
 * ist der Kern nicht mehr allgemein genug fuer weitere Sportarten. Gegenstueck in Swift: RowingTestModule.
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
      maxSessionsPerWeek: 3,
      macroGrowthFactor: 1.1,
      amountStep: 5
    },
    // Test-Sportart: Werte wie beim Rad.
    startingLevel: {
      factors: { regular: 1, short_break: 0.7, long_break: 0.5 },
      returnGrowthFactor: 1.2
    },
    typicalSpeedMetersPerSecond: 3.5,
    stepMeasures: ["duration", "distance"],
    distanceStepMeters: 250,
    minStepMeters: 250,
    maxStepMeters: 20_000,
    minStepSeconds: 30,
    maxStepSeconds: 2 * 3600,
    targetRange,
    testSessions: {
      time_trial_2000m: [
        step("Einrudern", { duration_seconds: 600, target_type: "stroke_rate", target_value: 20 }),
        step("Test 2000 m", { measure: "distance", distance_meters: 2000, duration_seconds: null }),
        step("Ausrudern", { duration_seconds: 300, target_type: "stroke_rate", target_value: 18 })
      ]
    },
    equipment: {},
    brickAfter: [],
    weatherSensitive: false,
    indoor: null,
    canFuelDuringRace: true,
    promptRules: "- Gesteuert über die Schlagzahl (stroke_rate, Schläge pro Minute), Grundlage 18 bis 22."
  }
};
