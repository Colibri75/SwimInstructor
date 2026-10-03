import { bike } from "./modules/bike";
import { run } from "./modules/run";
import { swim } from "./modules/swim";
import { SportDefinition } from "./types";
import { STEP_MEASURES, STEP_TARGETS, StepMeasure, StepTarget } from "./vocabulary";

const SPORT_ID_PATTERN = /^[a-z][a-z0-9_]{1,31}$/;

export class SportRegistryError extends Error {
  constructor(
    readonly problem: "malformed_id" | "duplicate" | "missing_display_name" | "no_measures" | "unknown_measure" | "unknown_target" | "invalid_goal_speed",
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
      byId.set(sport.id, sport);
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

  /** Ob ein Schritt mit diesem Mass und Ziel zur Sportart passt (ohne Ziel immer erlaubt). */
  supports(id: string, measure: StepMeasure, target?: StepTarget): boolean {
    const sport = this.byId.get(id);
    if (sport === undefined) return false;
    return sport.measures.includes(measure) && (target === undefined || sport.targets.includes(target));
  }
}

/** Die Sportart, um die es vor dem Triathlon-Umbau allein ging: Snapshot v1 und alte Plaene sind Schwimmen. */
export const LEGACY_SPORT_ID = swim.id;

/** Die Sportarten des Servers. Die Tests pruefen, dass sie zu contracts/sports.json passen. */
export const SPORTS = new SportRegistry([swim, bike, run]);
