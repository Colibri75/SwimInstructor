import { z } from "zod";
import { addDays, DATE_PATTERN, weekdayIndex } from "./week";

/**
 * Gesamtplan: Claude plant die Wochen von heute bis zum Zieltag als Geruest (Umfang, Einheiten,
 * Entlastung, Schwerpunkt je Woche). Die Phase einer Woche (Aufbau, zielspezifisch, Zuspitzen, Zielwoche)
 * rechnet der Code aus dem Abstand zum Zieltag, Claude liefert sie nicht. Der Gesamtplan gibt die
 * Richtung vor; den Plan fuer die naechsten sieben Tage justiert die App jeden Tag neu darauf und auf
 * den Zustand (siehe weekPrompt.ts).
 *
 * Wie bei Tages- und Wochenplan ohne Wertegrenzen im Schema: Die Grenzen prueft macroSanity.ts.
 */
export const MACRO_PHASES = ["base", "specific", "taper", "goal_week", "maintain"] as const;
export type MacroPhase = (typeof MACRO_PHASES)[number];

export const MacroWeekSchema = z.object({
  week_start: z.string().describe("Montag der Woche im Format YYYY-MM-DD, genau eine der angegebenen Wochen"),
  target_meters: z.number().int().describe("Geplanter Wochenumfang in Metern"),
  sessions: z.number().int().describe("Geplante Trainingstage in dieser Woche (2 bis 5)"),
  deload: z.boolean().describe("true bei einer Entlastungswoche mit deutlich weniger Umfang als davor"),
  focus: z.string().describe("Schwerpunkt der Woche in hoechstens 60 Zeichen auf Deutsch, z. B. Grundlagenausdauer und Technik")
});

export const MacroPlanSchema = z.object({
  rationale: z.string().describe("Begruendung des Gesamtplans auf Deutsch, hoechstens fuenf Saetze, mit konkreten Zahlen (Wochen bis zum Ziel, Umfang jetzt und zum Hoehepunkt)"),
  weeks: z.array(MacroWeekSchema)
});

export type MacroWeekRaw = z.infer<typeof MacroWeekSchema>;
export type MacroPlanRaw = z.infer<typeof MacroPlanSchema>;

/** Eine Woche des geprueften Gesamtplans, mit der vom Code berechneten Phase. */
export interface MacroWeek extends MacroWeekRaw {
  phase: MacroPhase;
}

/** Was der Gesamtplan fuer eine Woche vorgibt. Geht mit der Wochenplan-Anfrage mit (Feld `macro_weeks`). */
export const MacroWeekTargetSchema = z.object({
  week_start: z.string().regex(DATE_PATTERN),
  phase: z.enum(MACRO_PHASES),
  target_meters: z.number().int().min(0).max(60_000),
  sessions: z.number().int().min(0).max(7),
  deload: z.boolean(),
  focus: z.string().max(120)
});
export type MacroWeekTarget = z.infer<typeof MacroWeekTargetSchema>;

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

/** Phase einer Woche aus ihrem Abstand zur Zielwoche (in ganzen Wochen). */
export function macroPhase(weekStart: string, goalDay: string, today: string): MacroPhase {
  if (goalDay < today) return "maintain";
  const weeksToGoal = Math.round(daysBetween(weekStart, mondayOf(goalDay)) / 7);
  if (weeksToGoal <= 0) return "goal_week";
  if (weeksToGoal <= 2) return "taper";
  if (weeksToGoal <= 12) return "specific";
  return "base";
}
