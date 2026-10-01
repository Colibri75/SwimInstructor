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
/** Hilfsmittel, die ein Abschnitt verlangen kann. Die App uebersetzt die Werte in deutsche Namen. */
export const EQUIPMENT = ["pull_buoy", "paddles", "fins", "snorkel", "kickboard", "ankle_band"] as const;

export const PlanSetSchema = z.object({
  name: z.string().describe("Name des Abschnitts, z. B. Einschwimmen, Technik, Hauptsatz, Ausschwimmen"),
  repetitions: z.number().int().describe("Anzahl der Wiederholungen"),
  distance_meters: z.number().int().describe("Distanz pro Wiederholung in Metern"),
  target_pace_seconds_per_hundred_meters: z
    .number()
    .nullable()
    .describe("Zielpace in Sekunden pro 100 m, null wenn keine Pace vorgegeben ist"),
  rest_seconds: z.number().int().describe("Pause nach jeder Wiederholung in Sekunden"),
  instructions: z
    .string()
    .describe("Anweisung für den Abschnitt. Bei einer Technikübung: Name der Übung plus ein bis zwei Sätze, wie sie geschwommen wird und worauf man achtet"),
  equipment: z
    .array(z.enum(EQUIPMENT))
    .describe("Hilfsmittel, die der Athlet für diesen Abschnitt braucht (pull_buoy, paddles, fins, snorkel, kickboard, ankle_band). Leere Liste, wenn keine")
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

/**
 * Schema fuer gespeicherte Plaene. Plaene, die vor der Einfuehrung des Equipments gespeichert wurden,
 * haben kein `equipment`: Sie bekommen eine leere Liste, statt als ungueltig verworfen zu werden.
 */
export const StoredTrainingPlanSchema = z.preprocess((value) => {
  if (typeof value !== "object" || value === null || !("sets" in value) || !Array.isArray(value.sets)) return value;
  return {
    ...value,
    sets: value.sets.map((set: unknown) =>
      typeof set === "object" && set !== null && !("equipment" in set) ? { ...set, equipment: [] } : set
    )
  };
}, TrainingPlanSchema);

export type PlanSet = z.infer<typeof PlanSetSchema>;
export type TrainingPlan = z.infer<typeof TrainingPlanSchema>;
export type Intensity = (typeof INTENSITIES)[number];
