import { PerformanceMetricDefinition } from "../performance";
import { EQUIPMENT_LABELS } from "../../plan/vocabulary";
import { SportDefinition, SportPlanningContext, TargetRange } from "../types";
import { StepTarget } from "../vocabulary";
import { effortDistanceStep, paceRange, performanceValue, recentPaceSeconds } from "./shared";

/** Critical Swim Speed als Pace in Sekunden pro 100 m. */
const CSS_PACE: PerformanceMetricDefinition = { id: "css_pace_per_100m", displayName: "CSS-Pace", unit: "s/100m", min: 50, max: 300 };

/**
 * Mit bekannter CSS: nicht schneller als 88 % der CSS-Pace (kurze, schnelle Wiederholungen liegen bei etwa 95 %).
 * Sonst wie in der Sicherheitsschicht des Tagesplans (src/plan/sanity.ts): nicht schneller als 90 % der Zielpace und
 * nicht schneller als 60 % der aktuellen Pace (die Pausen enthaelt). Nie langsamer als 10:00/100 m.
 */
function targetRange(target: StepTarget, context: SportPlanningContext): TargetRange | null {
  const { state, discipline } = context;
  switch (target) {
    case "pace_per_100m": {
      const css = performanceValue(context, CSS_PACE.id);
      if (css !== undefined) return { min: Math.round(css * 0.88), max: 600 };
      const recent = recentPaceSeconds(state, 100);
      const goal = discipline?.target_duration_seconds !== undefined ? (discipline.target_duration_seconds / discipline.distance_meters) * 100 : undefined;
      return paceRange({ recent, goal, recentFactor: 0.6, goalFactor: 0.9, unknownGoalFactor: 1.3, absoluteFastest: 40, slowest: 600 });
    }
    case "perceived_effort":
      return { min: 1, max: 10 };
    default:
      // Puls ist im Wasser nur eingeschraenkt brauchbar: kein Pulsziel im Plan.
      return null;
  }
}

const WARM_UP = "Locker einschwimmen, Kraul oder deine Lieblingslage.";
const BUILD_UP = "Jede Bahn etwas schneller als die vorige, die letzte fast im Testtempo.";
const COOL_DOWN = "Ganz locker ausschwimmen.";

/** Die Testeinheiten: Ein- und Ausschwimmen plus die Testbelastung. Ein 25-m- und ein 50-m-Becken gehen auf. */
const TEST_SESSIONS = {
  // CSS = 200 / (Zeit 400 m - Zeit 200 m) in m/s (Wakayoshi 1992); die App rechnet daraus die Pace pro 100 m.
  css_400_200: [
    effortDistanceStep("Einschwimmen", 200, 3, "Locker einschwimmen", WARM_UP, 1, 30),
    effortDistanceStep("Steigerung", 50, 6, "Steigern", BUILD_UP, 2, 30),
    effortDistanceStep(
      "Test 400 m",
      400,
      10,
      "400 m maximal",
      "400 m so schnell, wie du sie gleichmäßig durchhältst, wie im Wettkampf. Die Zeit zählt. Danach 10 Minuten locker erholen.",
      1,
      600
    ),
    effortDistanceStep("Test 200 m", 200, 10, "200 m maximal", "200 m so schnell du kannst, gleichmäßig eingeteilt. Die Zeit zählt.", 1, 0),
    effortDistanceStep("Ausschwimmen", 100, 2, "Locker ausschwimmen", COOL_DOWN)
  ],
  // Schwellentempo = Zeit fuer 1000 m durch 10 (Friel).
  time_trial_1000m: [
    effortDistanceStep("Einschwimmen", 300, 3, "Locker einschwimmen", WARM_UP, 1, 30),
    effortDistanceStep("Steigerung", 50, 6, "Steigern", BUILD_UP, 2, 30),
    effortDistanceStep(
      "Test 1000 m",
      1000,
      9,
      "1000 m gleichmäßig hart",
      "1000 m so schnell, wie du sie gleichmäßig durchhältst. Nicht zu schnell anfangen. Die Zeit zählt.",
      1,
      0
    ),
    effortDistanceStep("Ausschwimmen", 100, 2, "Locker ausschwimmen", COOL_DOWN)
  ]
};

/** Schwimmen, im Becken und im Freiwasser. */
export const swim: SportDefinition = {
  id: "swim",
  displayName: "Schwimmen",
  measures: ["distance", "duration"],
  targets: ["pace_per_100m", "heart_rate_zone", "perceived_effort"],
  // 10:00 bis 0:40 pro 100 m, wie die bisherige Zielpruefung der App.
  goalSpeed: { minMetersPerSecond: 0.15, maxMetersPerSecond: 2.5 },
  loadFactor: 1,
  performanceMetrics: [CSS_PACE],
  performanceTests: [
    { id: "css_400_200", displayName: "CSS-Test 400/200 m", produces: [CSS_PACE.id], maximalEffort: true, durationMinutes: 10 },
    { id: "time_trial_1000m", displayName: "1000-m-Test", produces: [CSS_PACE.id], maximalEffort: true, durationMinutes: 20 }
  ],
  planning: {
    // Die Grenzen des bisherigen Schwimmplans (src/plan/sanity.ts, DEFAULT_LIMITS), in Metern. Die Untergrenzen je
    // Einheit und Woche sind seit dem Betatest hoeher (dort 1000 und 1500 m), sonst blieb mit wenig Verlauf zu wenig.
    limitUnit: "meters",
    limits: {
      sessionGrowthFactor: 1.25,
      minSessionCap: 1500,
      absoluteMaxSession: 4500,
      weeklyGrowthFactor: 1.3,
      minWeeklyCap: 2500,
      minSession: 400,
      pauseSessionCap: 800,
      pauseAfterDays: 14,
      maxSessionsPerWeek: 5,
      macroGrowthFactor: 1.1,
      amountStep: 50
    },
    // Nach einer Pause steigt man beim Schwimmen schneller wieder ein als beim Laufen (Praxiswert).
    startingLevel: {
      factors: { regular: 1, short_break: 0.7, long_break: 0.5 },
      returnGrowthFactor: 1.2
    },
    // 2:05 pro 100 m inklusive Pausen.
    typicalSpeedMetersPerSecond: 0.8,
    stepMeasures: ["distance"],
    distanceStepMeters: 50,
    minStepMeters: 50,
    maxStepMeters: 3800,
    minStepSeconds: 30,
    maxStepSeconds: 5400,
    targetRange,
    testSessions: TEST_SESSIONS,
    equipment: EQUIPMENT_LABELS,
    // Im Triathlon kommt das Rad nach dem Schwimmen, nicht umgekehrt; das Becken ist drinnen oder wetterunabhaengig genug.
    brickAfter: [],
    weatherSensitive: false,
    indoor: null,
    promptRules: `- Gesteuert über das Tempo pro 100 m (target_type pace_per_100m, target_value in Sekunden pro 100 m) oder die gefühlte Anstrengung (perceived_effort, 1 bis 10). Kein Pulsziel: Puls ist im Wasser kaum brauchbar. Die Pace im Snapshot enthält Pausen, das reine Schwimmtempo ist schneller.
- Ist die CSS-Pace bekannt (Abschnitt Leistungswerte), richte das Tempo danach: Grundlage etwa 8 bis 12 % langsamer als die CSS-Pace, Schwelle (CSS-Serien) etwa auf CSS-Pace, kurze schnelle Wiederholungen etwa 5 % schneller.
- Eine Einheit besteht aus Einschwimmen, Hauptteil und Ausschwimmen. Jeder Schritt wird über die Strecke gemessen (measure distance). Jede Wiederholung ist ein Vielfaches von 50 m und mindestens 50 m lang (50, 100, 150, 200 …), damit der Plan in einem 25-m- und in einem 50-m-Becken aufgeht: keine 25er und keine 75er.
- Der Athlet schwimmt ohne Trainer vor Ort: Erkläre jede Technikübung im Feld instructions in ein bis zwei Sätzen und verwende keinen Fachbegriff ohne diese Erklärung. Das Feld cue liest er im Wasser auf der Uhr: zwei bis vier Wörter, höchstens 30 Zeichen, zum Beispiel "Locker kraulen" oder "Zielpace halten".
- Hilfsmittel (pull_buoy, paddles, fins, snorkel, kickboard, ankle_band) sparsam und nur, wenn der Athlet sie hat; Abschnitte mit Hilfsmitteln ohne Zielpace.
- Im Triathlon zählt Schwimmen als Technik- und Ausdauerdisziplin: Technik und gleichmäßiges Tempo gehen vor harten Serien, die Schulter wird nicht überlastet.`
  }
};
