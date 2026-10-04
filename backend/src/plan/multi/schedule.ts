import { GoalKind, ScheduleDay, SnapshotV2 } from "../snapshot";
import { weekdayIndex } from "../week";
import { sportName } from "./sports";

/**
 * Zielart und Wochenraster (P2). Ohne Angaben (App vor P2) gilt wie bisher: ein Wettkampf, Trainingstage und
 * Wochenstunden aus dem Ziel, kein fester Tag.
 */

export function goalKind(snapshot: SnapshotV2): GoalKind {
  return snapshot.training_goal.kind ?? "race";
}

/** Fit werden und bleiben: kein Wettkampf, kein Zuspitzen, der Zieltag ist nur das Ende des Planungszeitraums. */
export function isFitnessGoal(snapshot: SnapshotV2): boolean {
  return goalKind(snapshot) === "fitness";
}

/** Der Eintrag des Wochenrasters fuer den Tag `date`, `undefined` ohne Wochenraster. */
export function scheduleDay(snapshot: SnapshotV2, date: string): ScheduleDay | undefined {
  const weekday = weekdayIndex(date) + 1;
  return snapshot.training_goal.weekly_schedule?.find((day) => day.weekday === weekday);
}

/** Trainingstage pro Woche: aus dem Wochenraster, sonst aus dem Ziel. */
export function trainingDaysPerWeek(snapshot: SnapshotV2): number {
  const schedule = snapshot.training_goal.weekly_schedule;
  return schedule === undefined ? snapshot.training_goal.training_days_per_week : schedule.filter((day) => day.trains).length;
}

/** Minuten pro Woche: Summe des Wochenrasters, sonst die Wochenstunden des Ziels. */
export function weeklyMinutes(snapshot: SnapshotV2): number {
  const schedule = snapshot.training_goal.weekly_schedule;
  return schedule === undefined
    ? Math.round(snapshot.training_goal.weekly_hours * 60)
    : schedule.reduce((sum, day) => sum + (day.trains ? day.max_minutes : 0), 0);
}

/** Die feste Sportart eines Tages, wenn sie zum Plan gehoert (Schwerpunkt ueber 0); sonst `undefined`. */
export function fixedSport(snapshot: SnapshotV2, date: string): string | undefined {
  const sport = scheduleDay(snapshot, date)?.sport;
  if (sport === undefined) return undefined;
  return snapshot.training_goal.emphasis.some((entry) => entry.sport === sport && entry.percent > 0) ? sport : undefined;
}

const TIME_TEXT = { morning: "morgens", midday: "mittags", evening: "abends" } as const;

/** Der Wochenraster fuer einen Tag in Worten, z. B. "abends, höchstens 60 min, nur Schwimmen". */
export function scheduleDayText(snapshot: SnapshotV2, date: string): string | null {
  const day = scheduleDay(snapshot, date);
  if (day === undefined) return null;
  if (!day.trains) return "Ruhetag laut Wochenraster";
  const sport = fixedSport(snapshot, date);
  return [
    ...(day.time_of_day !== undefined ? [TIME_TEXT[day.time_of_day]] : []),
    `höchstens ${day.max_minutes} min`,
    ...(sport !== undefined ? [`nur ${sportName(sport)}`] : [])
  ].join(", ");
}
