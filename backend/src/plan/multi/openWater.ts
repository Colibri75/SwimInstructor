import { SportDefinition } from "../../sports/types";
import { daysBetween } from "../calendar";
import { SnapshotV2 } from "../snapshot";
import { DayWeather, severeWeather } from "../weather";
import { goalDayOf } from "./limits";

/**
 * Freiwasser (Schwimmen im See oder Meer statt im Becken). Die Sportart sagt ueber `planning.openWater`, ob es das gibt;
 * der Athlet hat Zugang, wenn sein Equipment die Kennung enthaelt. Ein Ziel im Freiwasser (`open_water` der Disziplin)
 * braucht Gewoehnung: In den letzten Wochen davor kommt jede Woche mindestens eine Einheit dorthin.
 */
export const OPEN_WATER_RULES = {
  /** So viele Wochen vor einem Ziel im Freiwasser gehoert jede Woche eine Freiwasser-Einheit dazu. */
  raceWeeks: 8,
  /** Unter dieser Tageshoechsttemperatur (Luft) ist das Wasser meist zu kalt; dann ins Becken. */
  minAirTempC: 16
};

/** Freiwasser ist fuer diese Sportart moeglich und der Athlet hat Zugang (ohne Angabe zum Equipment: ja). */
export function openWaterAllowed(sport: SportDefinition, equipment: readonly string[] | undefined): boolean {
  const venue = sport.planning.openWater;
  return venue !== null && (equipment === undefined || equipment.includes(venue.equipment));
}

/** Das Ziel hat diese Sportart als Disziplin im Freiwasser. */
export function raceInOpenWater(snapshot: SnapshotV2, sportId: string): boolean {
  return snapshot.training_goal.disciplines.some((discipline) => discipline.sport === sportId && discipline.open_water === true);
}

/** Warum an diesem Tag kein Freiwasser geht (Unwetter, zu kalt), sonst `null`. Ohne Vorhersage: kein Einwand. */
export function openWaterBlocked(weather: DayWeather | undefined): string | null {
  if (weather === undefined) return null;
  const severe = severeWeather(weather);
  if (severe !== null) return severe;
  if (weather.temp_max_c < OPEN_WATER_RULES.minAirTempC) return `zu kalt fürs Freiwasser (höchstens ${weather.temp_max_c} °C)`;
  return null;
}

/** Der Tag liegt in den letzten `raceWeeks` Wochen vor dem Ziel (Zieltag eingeschlossen). */
export function inOpenWaterBlock(snapshot: SnapshotV2, date: string): boolean {
  const days = daysBetween(date, goalDayOf(snapshot));
  return days >= 0 && days < OPEN_WATER_RULES.raceWeeks * 7;
}
