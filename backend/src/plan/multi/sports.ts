import { PerformanceSource } from "../../sports/performance";
import { SPORTS } from "../../sports/registry";
import { SportDefinition, SportPerformance, SportPlanningContext, SportStateValues } from "../../sports/types";
import { SnapshotV2 } from "../snapshot";

/**
 * Bausteine der Planung fuer mehrere Sportarten: welche Sportarten geplant werden, ihre Werte aus dem Snapshot, Tempo
 * und Umrechnung zwischen Strecke und Dauer. Nichts hier kennt eine bestimmte Sportart, alles kommt aus der Registry.
 */

/** Eine Sportart ohne Einheiten in den letzten 4 Wochen (oder ohne Eintrag im Snapshot). */
export const EMPTY_STATE: SportStateValues = {
  sessions_last_seven_days: 0,
  sessions_last_four_weeks: 0,
  minutes_last_seven_days: 0,
  average_weekly_minutes: 0,
  meters_last_seven_days: 0,
  average_weekly_meters: 0,
  longest_session_meters: 0,
  longest_session_minutes: 0
};

export function stateOf(snapshot: SnapshotV2, sportId: string): SportStateValues {
  return snapshot.sports.find((state) => state.sport === sportId) ?? EMPTY_STATE;
}

export function emphasisOf(snapshot: SnapshotV2, sportId: string): number {
  return snapshot.training_goal.emphasis.find((entry) => entry.sport === sportId)?.percent ?? 0;
}

/** Die Sportarten des Plans: Schwerpunkt ueber 0, in der Reihenfolge der Registry. */
export function plannedSports(snapshot: SnapshotV2): SportDefinition[] {
  return SPORTS.sports.filter((sport) => emphasisOf(snapshot, sport.id) > 0);
}

export function isPlanned(snapshot: SnapshotV2, sportId: string): boolean {
  return SPORTS.get(sportId) !== undefined && emphasisOf(snapshot, sportId) > 0;
}

export function isConfirmed(source: PerformanceSource): boolean {
  return source === "tested" || source === "manual";
}

/** Leistungswerte fuer eine Sportart: die fuer alle Sportarten plus die eigenen (die gehen vor). `undefined` ohne Profil. */
export function performanceFor(snapshot: SnapshotV2, sportId: string): SportPerformance | undefined {
  const performance = snapshot.performance;
  if (performance === undefined) return undefined;
  const values: Record<string, SportPerformance["values"][string]> = {};
  const sport = performance.sports.find((entry) => entry.sport === sportId);
  for (const value of [...performance.athlete, ...(sport?.values ?? [])]) {
    values[value.metric] = { value: value.value, source: value.source, measuredAt: value.measured_at };
  }
  return { values, zoneTargets: (sport?.zones ?? []).map((zones) => zones.target) };
}

/** Was ein Modul fuer seine Zielbereiche braucht: Verlauf, Disziplin des Ziels und Leistungswerte. */
export function planningContext(snapshot: SnapshotV2, sport: SportDefinition): SportPlanningContext {
  const discipline = snapshot.training_goal.disciplines.find((entry) => entry.sport === sport.id);
  const performance = performanceFor(snapshot, sport.id);
  return {
    state: stateOf(snapshot, sport.id),
    ...(discipline !== undefined ? { discipline } : {}),
    ...(performance !== undefined ? { performance } : {})
  };
}

/**
 * Trainingstempo in m/s (inklusive Pausen) aus den letzten 4 Wochen. Ohne Verlauf oder bei einem unplausiblen Wert
 * (Tippfehler in Health) das typische Tempo der Sportart.
 */
export function trainingSpeed(sport: SportDefinition, state: SportStateValues): number {
  if (state.average_weekly_meters > 0 && state.average_weekly_minutes > 0) {
    const speed = state.average_weekly_meters / (state.average_weekly_minutes * 60);
    if (speed >= sport.goalSpeed.minMetersPerSecond / 2 && speed <= sport.goalSpeed.maxMetersPerSecond) return speed;
  }
  return sport.planning.typicalSpeedMetersPerSecond;
}

/** Ein Umfang in der Einheit der Sportart (Meter oder Minuten) als Minuten. */
export function amountToMinutes(sport: SportDefinition, amount: number, speed: number): number {
  return sport.planning.limitUnit === "minutes" ? amount : amount / speed / 60;
}

/** Ein Umfang in der Einheit der Sportart als Meter (bei Minuten geschaetzt aus dem Tempo). */
export function amountToMeters(sport: SportDefinition, amount: number, speed: number): number {
  return sport.planning.limitUnit === "meters" ? amount : amount * 60 * speed;
}

/** Auf das Raster der Sportart abgerundet (Grenzen werden nie aufgerundet). */
export function floorAmount(sport: SportDefinition, value: number): number {
  const step = sport.planning.limits.amountStep;
  return Math.max(Math.floor(value / step + 1e-9) * step, 0);
}

export function roundAmount(sport: SportDefinition, value: number): number {
  const step = sport.planning.limits.amountStep;
  return Math.max(Math.round(value / step) * step, 0);
}

export function unitLabel(sport: SportDefinition): string {
  return sport.planning.limitUnit === "meters" ? "m" : "min";
}

export function formatAmount(sport: SportDefinition, amount: number): string {
  return `${Math.round(amount)} ${unitLabel(sport)}`;
}

/** Die laengste Einheit, der Wochenschnitt und die letzten 7 Tage in der Einheit der Sportart. */
export function stateAmounts(sport: SportDefinition, state: SportStateValues): { longest: number; average: number; lastSeven: number } {
  return sport.planning.limitUnit === "meters"
    ? { longest: state.longest_session_meters, average: state.average_weekly_meters, lastSeven: state.meters_last_seven_days }
    : { longest: state.longest_session_minutes, average: state.average_weekly_minutes, lastSeven: state.minutes_last_seven_days };
}

export function sportName(id: string): string {
  return SPORTS.get(id)?.displayName ?? id;
}

/** Die Dauer des Wettkampfs je Disziplin in Sekunden: Zielzeit oder, ohne Zielzeit, mit dem typischen Tempo geschaetzt. */
export function disciplineSeconds(discipline: { sport: string; distance_meters: number; target_duration_seconds?: number }): number {
  if (discipline.target_duration_seconds !== undefined) return discipline.target_duration_seconds;
  const sport = SPORTS.get(discipline.sport);
  return sport === undefined ? 0 : discipline.distance_meters / sport.planning.typicalSpeedMetersPerSecond;
}

export function raceSeconds(snapshot: SnapshotV2): number {
  return snapshot.training_goal.disciplines.reduce((sum, discipline) => sum + disciplineSeconds(discipline), 0);
}

/** Der Umfang einer Disziplin im Wettkampf in der Einheit der Sportart; 0, wenn die Sportart keine Disziplin ist. */
export function raceAmount(snapshot: SnapshotV2, sport: SportDefinition): number {
  const discipline = snapshot.training_goal.disciplines.find((entry) => entry.sport === sport.id);
  if (discipline === undefined) return 0;
  return sport.planning.limitUnit === "meters" ? discipline.distance_meters : disciplineSeconds(discipline) / 60;
}
