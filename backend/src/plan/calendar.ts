/**
 * Kalender der Planung: Datumshilfen (rein kalendarisch, ohne Zeitzone), die Wochen des Gesamtplans bis zum Zieltag und
 * seine Phasen. Alles ist reiner Code ohne Netzwerk; Tage sind Strings `YYYY-MM-DD`.
 */

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

/** Sieben (oder `count`) Tage ab `from`, unabhaengig vom Wochentag. */
export function windowDates(from: string, count = 7): string[] {
  return Array.from({ length: count }, (_, offset) => addDays(from, offset));
}

/** Kalendertag YYYY-MM-DD in der gegebenen Zeitzone. */
export function localDate(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}

/** Phasen des Gesamtplans. Die Phase einer Woche rechnet der Code aus dem Abstand zur Zielwoche, Claude liefert sie nicht. */
export const MACRO_PHASES = ["base", "specific", "taper", "goal_week", "maintain"] as const;
export type MacroPhase = (typeof MACRO_PHASES)[number];

/** Hoechstens so viele Wochen plant der Gesamtplan voraus (knapp anderthalb Jahre). */
export const MAX_MACRO_WEEKS = 80;

/** Montag der Woche, in der `iso` liegt. */
export function mondayOf(iso: string): string {
  return addDays(iso, -weekdayIndex(iso));
}

/** Tage von `from` bis `to` (negativ, wenn `to` davor liegt). */
export function daysBetween(from: string, to: string): number {
  const a = Date.parse(`${from}T12:00:00Z`);
  const b = Date.parse(`${to}T12:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

/**
 * Die Wochen des Gesamtplans: vom Montag der Woche von heute bis zum Montag der Zielwoche, hoechstens
 * `MAX_MACRO_WEEKS`. Liegt der Zieltag vor heute, bleibt nur die laufende Woche.
 */
export function macroWeekStarts(today: string, goalDay: string, maxWeeks: number = MAX_MACRO_WEEKS): string[] {
  const first = mondayOf(today);
  const last = goalDay < today ? first : mondayOf(goalDay);
  const count = Math.min(Math.round(daysBetween(first, last) / 7) + 1, maxWeeks);
  return Array.from({ length: count }, (_, index) => addDays(first, index * 7));
}
