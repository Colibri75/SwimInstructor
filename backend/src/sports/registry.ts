import { bike } from "./modules/bike";
import { run } from "./modules/run";
import { swim } from "./modules/swim";
import { ATHLETE_METRICS, PerformanceMetricDefinition } from "./performance";
import { SportDefinition } from "./types";
import { STEP_MEASURES, STEP_TARGETS, StepMeasure, StepTarget } from "./vocabulary";

const SPORT_ID_PATTERN = /^[a-z][a-z0-9_]{1,31}$/;

export class SportRegistryError extends Error {
  constructor(
    readonly problem:
      | "malformed_id"
      | "duplicate"
      | "missing_display_name"
      | "no_measures"
      | "unknown_measure"
      | "unknown_target"
      | "invalid_goal_speed"
      | "invalid_load_factor"
      | "invalid_performance_metric"
      | "invalid_performance_test"
      | "invalid_planning"
      | "invalid_brick",
    readonly sportId: string
  ) {
    super(`Sportart ${sportId}: ${problem}`);
    this.name = "SportRegistryError";
  }
}

/** Die angemeldeten Sportarten, geprueft beim Anlegen (vollstaendig, keine Kennung doppelt). */
export class SportRegistry {
  private readonly byId: ReadonlyMap<string, SportDefinition>;

  constructor(readonly sports: readonly SportDefinition[]) {
    const byId = new Map<string, SportDefinition>();
    for (const sport of sports) {
      if (!SPORT_ID_PATTERN.test(sport.id)) throw new SportRegistryError("malformed_id", sport.id);
      if (byId.has(sport.id)) throw new SportRegistryError("duplicate", sport.id);
      if (sport.displayName.trim() === "") throw new SportRegistryError("missing_display_name", sport.id);
      if (sport.measures.length === 0) throw new SportRegistryError("no_measures", sport.id);
      if (sport.measures.some((measure) => !(STEP_MEASURES as readonly string[]).includes(measure))) {
        throw new SportRegistryError("unknown_measure", sport.id);
      }
      if (sport.targets.some((target) => !(STEP_TARGETS as readonly string[]).includes(target))) {
        throw new SportRegistryError("unknown_target", sport.id);
      }
      const { minMetersPerSecond: min, maxMetersPerSecond: max } = sport.goalSpeed;
      if (!(Number.isFinite(min) && Number.isFinite(max) && min > 0 && min < max)) {
        throw new SportRegistryError("invalid_goal_speed", sport.id);
      }
      if (!(Number.isFinite(sport.loadFactor) && sport.loadFactor > 0)) throw new SportRegistryError("invalid_load_factor", sport.id);
      validatePerformance(sport);
      if (!validPlanning(sport)) throw new SportRegistryError("invalid_planning", sport.id);
      byId.set(sport.id, sport);
    }
    // Koppeltraining nur nach einer anderen, angemeldeten Sportart.
    for (const sport of sports) {
      if (sport.planning.brickAfter.some((other) => other === sport.id || !byId.has(other))) throw new SportRegistryError("invalid_brick", sport.id);
    }
    this.byId = byId;
  }

  get ids(): string[] {
    return this.sports.map((sport) => sport.id);
  }

  /** `undefined` fuer eine Kennung, die dieser Server nicht kennt. */
  get(id: string): SportDefinition | undefined {
    return this.byId.get(id);
  }

  /** Ob ein Ziel (Strecke in Zielzeit) fuer diese Sportart ein plausibles Durchschnittstempo hat. */
  plausibleGoal(id: string, distanceMeters: number, durationSeconds: number): boolean {
    const sport = this.byId.get(id);
    if (sport === undefined || durationSeconds <= 0) return false;
    const speed = distanceMeters / durationSeconds;
    return speed >= sport.goalSpeed.minMetersPerSecond && speed <= sport.goalSpeed.maxMetersPerSecond;
  }

  /** Was ein Leistungswert bedeutet: `sportId` undefined fuer die Werte aller Sportarten. `undefined`, wenn unbekannt. */
  metric(sportId: string | undefined, metricId: string): PerformanceMetricDefinition | undefined {
    const metrics = sportId === undefined ? ATHLETE_METRICS : this.byId.get(sportId)?.performanceMetrics;
    return metrics?.find((metric) => metric.id === metricId);
  }

  /** Ob ein Schritt mit diesem Mass und Ziel zur Sportart passt (ohne Ziel immer erlaubt). */
  supports(id: string, measure: StepMeasure, target?: StepTarget): boolean {
    const sport = this.byId.get(id);
    if (sport === undefined) return false;
    return sport.measures.includes(measure) && (target === undefined || sport.targets.includes(target));
  }
}

/** Leistungswerte und Tests: gueltige Kennungen, nichts doppelt, Bereiche ueber 0, Tests messen eigene Werte. */
function validatePerformance(sport: SportDefinition): void {
  const athlete = new Set(ATHLETE_METRICS.map((metric) => metric.id));
  const metrics = new Set<string>();
  for (const metric of sport.performanceMetrics) {
    const valid =
      SPORT_ID_PATTERN.test(metric.id) &&
      !athlete.has(metric.id) &&
      !metrics.has(metric.id) &&
      metric.displayName.trim() !== "" &&
      metric.unit !== "" &&
      Number.isFinite(metric.max) &&
      metric.min > 0 &&
      metric.min < metric.max;
    if (!valid) throw new SportRegistryError("invalid_performance_metric", sport.id);
    metrics.add(metric.id);
  }
  const tests = new Set<string>();
  for (const test of sport.performanceTests) {
    const valid =
      SPORT_ID_PATTERN.test(test.id) &&
      !tests.has(test.id) &&
      test.displayName.trim() !== "" &&
      test.produces.length > 0 &&
      test.produces.every((metric) => metrics.has(metric)) &&
      Number.isInteger(test.durationMinutes) &&
      test.durationMinutes > 0;
    if (!valid) throw new SportRegistryError("invalid_performance_test", sport.id);
    tests.add(test.id);
  }
}

const positive = (value: number) => Number.isFinite(value) && value > 0;

/**
 * Planungsangaben: Grenzen ueber 0 und in sich stimmig (kleinste Einheit <= Untergrenze <= Obergrenze, Faktoren ab 1),
 * Startniveau: Anteile von 0 bis 1, Rueckkehr nicht langsamer als die normale Steigerung und hoechstens +50 % pro Woche,
 * Schrittmasse aus den eigenen Massen, eine Testeinheit je Leistungstest und keine fuer unbekannte Tests.
 */
function validPlanning(sport: SportDefinition): boolean {
  const planning = sport.planning;
  const limits = planning.limits;
  const values = Object.values(limits) as number[];
  if (!values.every(positive)) return false;
  if (limits.sessionGrowthFactor < 1 || limits.weeklyGrowthFactor < 1 || limits.macroGrowthFactor < 1) return false;
  if (!(limits.minSession <= limits.minSessionCap && limits.minSessionCap <= limits.absoluteMaxSession)) return false;
  if (limits.pauseSessionCap < limits.minSession || limits.minWeeklyCap < limits.minSession) return false;
  if (!Number.isInteger(limits.maxSessionsPerWeek) || limits.maxSessionsPerWeek > 14) return false;
  if (planning.limitUnit !== "meters" && planning.limitUnit !== "minutes") return false;
  const starting = planning.startingLevel;
  const factors = [starting.factors.regular, starting.factors.short_break, starting.factors.long_break];
  if (!factors.every((factor) => Number.isFinite(factor) && factor >= 0 && factor <= 1)) return false;
  if (!(starting.returnGrowthFactor >= limits.macroGrowthFactor && starting.returnGrowthFactor <= 1.5)) return false;
  if (!positive(planning.typicalSpeedMetersPerSecond)) return false;
  if (planning.stepMeasures.length === 0 || !planning.stepMeasures.every((measure) => sport.measures.includes(measure))) return false;
  if (![planning.distanceStepMeters, planning.minStepMeters, planning.minStepSeconds].every(positive)) return false;
  if (planning.minStepMeters > planning.maxStepMeters || planning.minStepSeconds > planning.maxStepSeconds) return false;
  if (planning.promptRules.trim() === "") return false;
  if (planning.indoor !== null && (!/^[a-z][a-z0-9_]{1,39}$/.test(planning.indoor.equipment) || planning.indoor.displayName.trim() === "")) return false;
  if (planning.indoor !== null && !planning.weatherSensitive) return false;
  const tests = sport.performanceTests.map((test) => test.id);
  const templates = Object.keys(planning.testSessions);
  return tests.every((id) => (planning.testSessions[id]?.length ?? 0) > 0) && templates.every((id) => tests.includes(id));
}


/** Die Sportarten des Servers. Die Tests pruefen, dass sie zu contracts/sports.json passen. */
export const SPORTS = new SportRegistry([swim, bike, run]);
