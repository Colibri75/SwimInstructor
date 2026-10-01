import { z } from "zod";
import { INTENSITIES, SESSION_TYPES } from "./plan";

/**
 * Wochenplan: Claude plant sieben Tage als Geruest (Typ, Intensitaet, Umfang, Schwerpunkt). Die
 * Abschnitte einer Einheit entstehen erst am Tag selbst (POST /v1/plan/today), passend zu dieser Vorgabe.
 * So bleibt der Aufruf kurz und die Details beruecksichtigen den Zustand des Tages.
 *
 * Wie beim Tagesplan ohne Wertegrenzen im Schema: Die Grenzen prueft die Sicherheitsschicht (weekSanity.ts).
 */
export const WeekDaySchema = z.object({
  date: z.string().describe("Kalendertag im Format YYYY-MM-DD, genau einer der angegebenen Tage"),
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  target_distance_meters: z.number().int().describe("Geplanter Umfang der Einheit in Metern, 0 an einem Ruhetag"),
  estimated_duration_minutes: z.number().int().describe("Geschaetzte Dauer inklusive Pausen, 0 an einem Ruhetag"),
  focus: z.string().describe("Schwerpunkt in hoechstens 60 Zeichen auf Deutsch, z. B. Technik mit Pull Buoy oder Ruhetag")
});

export const WeekPlanSchema = z.object({
  rationale: z.string().describe("Begruendung der Woche auf Deutsch, hoechstens vier Saetze, mit konkreten Zahlen aus dem Snapshot"),
  days: z.array(WeekDaySchema)
});

export type WeekDay = z.infer<typeof WeekDaySchema>;
export type WeekPlan = z.infer<typeof WeekPlanSchema>;

/** Was der Wochenplan fuer einen Tag vorgibt. Geht mit der Tagesplan-Anfrage mit (Feld `day_plan`). */
export const DayTargetSchema = z.object({
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  target_distance_meters: z.number().int().min(0).max(20_000),
  focus: z.string().max(120)
});
export type DayTarget = z.infer<typeof DayTargetSchema>;

// --- Datumshilfen (rein kalendarisch, ohne Zeitzone) ---

export const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function parse(iso: string): Date {
  // Mittag UTC: Verschiebungen um einen Tag durch Sommerzeit sind ausgeschlossen.
  return new Date(`${iso}T12:00:00Z`);
}

export function isRealDate(iso: string): boolean {
  if (!DATE_PATTERN.test(iso)) return false;
  const date = parse(iso);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === iso;
}

export function addDays(iso: string, days: number): string {
  const date = parse(iso);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** 0 = Montag bis 6 = Sonntag. */
export function weekdayIndex(iso: string): number {
  return (parse(iso).getUTCDay() + 6) % 7;
}

export const WEEKDAYS_DE = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"] as const;

export function weekdayName(iso: string): string {
  return WEEKDAYS_DE[weekdayIndex(iso)];
}

/** Die sieben Tage ab dem Montag. */
export function weekDates(weekStart: string): string[] {
  return Array.from({ length: 7 }, (_, offset) => addDays(weekStart, offset));
}
