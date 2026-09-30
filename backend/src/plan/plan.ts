import { z } from "zod";

/**
 * Ausgabe-Schema des Trainingsplans. Dasselbe Schema erzwingt Claude per strukturierter Ausgabe und
 * validiert der Server danach noch einmal selbst.
 *
 * Bewusst ohne Wertegrenzen (min/max): Strukturierte Ausgaben unterstuetzen sie nicht zuverlaessig.
 * Die Grenzen prueft die Sicherheitsschicht (sanity.ts), die auch sinnvoll aussehende, aber
 * gefaehrliche Werte korrigiert.
 */
export const SESSION_TYPES = ["rest", "recovery", "technique", "endurance", "threshold", "intervals", "test"] as const;
export const INTENSITIES = ["rest", "easy", "moderate", "hard"] as const;

export const PlanSetSchema = z.object({
  name: z.string().describe("Name des Abschnitts, z. B. Einschwimmen, Technik, Hauptsatz, Ausschwimmen"),
  repetitions: z.number().int().describe("Anzahl der Wiederholungen"),
  distance_meters: z.number().int().describe("Distanz pro Wiederholung in Metern"),
  target_pace_seconds_per_hundred_meters: z
    .number()
    .nullable()
    .describe("Zielpace in Sekunden pro 100 m, null wenn keine Pace vorgegeben ist"),
  rest_seconds: z.number().int().describe("Pause nach jeder Wiederholung in Sekunden"),
  instructions: z.string().describe("Kurze Anweisung oder Technikfokus")
});

export const TrainingPlanSchema = z.object({
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  rationale: z.string().describe("Begruendung auf Deutsch, hoechstens vier Saetze, mit konkreten Zahlen aus dem Snapshot"),
  total_distance_meters: z.number().int().describe("Summe aus repetitions mal distance_meters ueber alle Abschnitte"),
  estimated_duration_minutes: z.number().int(),
  sets: z.array(PlanSetSchema),
  coach_notes: z.array(z.string()).describe("Null bis drei kurze Hinweise auf Deutsch")
});

export type PlanSet = z.infer<typeof PlanSetSchema>;
export type TrainingPlan = z.infer<typeof TrainingPlanSchema>;
export type Intensity = (typeof INTENSITIES)[number];
