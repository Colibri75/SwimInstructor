import { THRESHOLD_HEART_RATE, THRESHOLD_POWER } from "../performance";
import { SportDefinition, SportPlanningContext, TargetRange } from "../types";
import { StepTarget } from "../vocabulary";
import { effortStep, performanceValue, zoneRange } from "./shared";

/**
 * Nach Puls (Zonen aus dem Profil) und gefuehlter Anstrengung. Watt nur mit bekannter Schwellenleistung (FTP), dann
 * zwischen 40 und 150 % davon; Tempo haengt draussen an Wind und Gelaende und taugt nicht als Ziel.
 */
function targetRange(target: StepTarget, context: SportPlanningContext): TargetRange | null {
  switch (target) {
    case "power": {
      const ftp = performanceValue(context, THRESHOLD_POWER.id);
      return ftp === undefined ? null : { min: Math.round(ftp * 0.4), max: Math.round(ftp * 1.5) };
    }
    case "heart_rate_zone":
      return zoneRange(context, target);
    case "perceived_effort":
      return { min: 1, max: 10 };
    case "cadence":
      return { min: 50, max: 120 };
    default:
      return null;
  }
}

/** 30 Minuten allein so hart wie im Wettkampf (Friel): Schwellenpuls = Schnitt der letzten 20 Minuten, FTP = Schnitt der 30 Minuten. */
const TEST_SESSIONS = {
  threshold_30min: [
    effortStep("Einfahren", 12, 3, "Locker einfahren", "Locker einrollen, leichter Gang, hohe Trittfrequenz."),
    effortStep("Steigerung", 1, 6, "Steigern", "Eine Minute zügig, dann eine Minute locker.", 3, 60),
    effortStep(
      "Test 30 Minuten",
      30,
      9,
      "30 min hart, gleichmäßig",
      "30 Minuten allein so hart, wie du sie gleichmäßig durchhältst, wie im Wettkampf. Nicht zu schnell anfangen. Am besten auf der Rolle oder auf einer flachen Strecke ohne Ampeln.",
      1,
      0
    ),
    effortStep("Ausfahren", 10, 2, "Locker ausfahren", "Ganz locker ausrollen.")
  ]
};

/** Radfahren, draussen und auf der Rolle. Ohne Wattmessung nach Puls und gefuehlter Anstrengung, mit FTP auch nach Watt. */
export const bike: SportDefinition = {
  id: "bike",
  displayName: "Radfahren",
  measures: ["duration", "distance"],
  targets: ["power", "heart_rate_zone", "speed", "cadence", "perceived_effort"],
  // 7,2 bis 72 km/h.
  goalSpeed: { minMetersPerSecond: 2, maxMetersPerSecond: 20 },
  loadFactor: 0.8,
  performanceMetrics: [THRESHOLD_HEART_RATE, THRESHOLD_POWER],
  performanceTests: [
    {
      id: "threshold_30min",
      displayName: "30-Minuten-Test",
      produces: [THRESHOLD_HEART_RATE.id, THRESHOLD_POWER.id],
      maximalEffort: true,
      durationMinutes: 30
    }
  ],
  planning: {
    // Startwerte wie beim Schwimmen (keine Studie zu sicheren Steigerungen beim Rad), in Minuten.
    limitUnit: "minutes",
    limits: {
      sessionGrowthFactor: 1.25,
      minSessionCap: 60,
      absoluteMaxSession: 360,
      weeklyGrowthFactor: 1.3,
      minWeeklyCap: 120,
      minSession: 20,
      pauseSessionCap: 45,
      pauseAfterDays: 14,
      maxSessionsPerWeek: 4,
      macroGrowthFactor: 1.1,
      amountStep: 5
    },
    // Wie beim Schwimmen (Praxiswert).
    startingLevel: {
      factors: { regular: 1, short_break: 0.7, long_break: 0.5 },
      returnGrowthFactor: 1.2
    },
    // 25 km/h.
    typicalSpeedMetersPerSecond: 7,
    stepMeasures: ["duration", "distance"],
    distanceStepMeters: 500,
    minStepMeters: 500,
    maxStepMeters: 200_000,
    minStepSeconds: 10,
    maxStepSeconds: 6 * 3600,
    targetRange,
    testSessions: TEST_SESSIONS,
    equipment: {},
    promptRules: `- Gesteuert über Pulszonen (target_type heart_rate_zone, target_value 1 bis 5 nach Prozent der Rad-Schwellenherzfrequenz: 1 unter 81 %, 2 81 bis 89 %, 3 90 bis 93 %, 4 94 bis 99 %, 5 ab 100 %) und die gefühlte Anstrengung (perceived_effort, 1 bis 10). Kurze harte Abschnitte unter etwa 3 Minuten bekommen ein perceived_effort-Ziel statt eines Pulsziels, weil der Puls zu träge reagiert. Kein Tempo als Ziel. Trittfrequenz (cadence, Umdrehungen pro Minute) nur für Technikabschnitte.
- Wattziele (power, target_value in Watt) nur, wenn eine Schwellenleistung (FTP) bekannt ist: Grundlage 55 bis 75 %, Tempo 76 bis 87 %, Schwelle 95 bis 105 %, VO2max 106 bis 120 % der FTP.
- Schritte meist nach Dauer (measure duration, duration_seconds); eine Strecke nur, wenn sie sinnvoll ist (Vielfache von 500 m).
- Grundlage ist die lange, lockere Ausfahrt in Zone 2. In der Aufbauphase kommen Tempo- und Schwellenabschnitte dazu (Zone 3 bis 4), dazu Koppeltraining: Rad und direkt danach ein kurzer Lauf.
- Das Rad nimmt Umfang auf, den das Laufen wegen seiner strengeren Grenzen nicht aufnehmen kann: mehr Ausdauer über das Rad statt über mehr Laufen.
- Drinnen auf der Rolle ist eine Einheit ohne Rollphasen anstrengender als draußen: plane sie eher kürzer.`
  }
};
