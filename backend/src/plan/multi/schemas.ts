import { z } from "zod";
import { SPORTS } from "../../sports/registry";
import { STEP_TARGETS } from "../../sports/vocabulary";
import { MACRO_PHASES } from "../macro";
import { INTENSITIES, SESSION_TYPES } from "../plan";
import { MAX_WISH_LENGTH } from "../routes";
import { SnapshotSchema, SnapshotV2 } from "../snapshot";
import { DATE_PATTERN } from "../week";

/**
 * Schemas der Planung fuer mehrere Sportarten (Plan v2, docs/multisport-planning.md): was Claude liefert (ohne
 * Wertegrenzen, die prueft die Sicherheitsschicht) und was die App schickt (mit Grenzen, wie bei v1).
 *
 * Umfaenge (`amount`) stehen immer in der Einheit der Sportart (`SportPlanning.limitUnit`): Meter beim Schwimmen,
 * Minuten bei Rad und Laufen. Die Nutzernachricht nennt die Einheit je Sportart.
 */
const SPORT_IDS = SPORTS.ids as [string, ...string[]];
const Sport = z.enum(SPORT_IDS);

// --- Was Claude liefert ---

export const StepSchema = z.object({
  name: z.string().describe("Name des Schritts, z. B. Einlaufen, Hauptteil, Auslaufen"),
  repetitions: z.number().int().describe("Anzahl der Wiederholungen"),
  measure: z.enum(["distance", "duration"]).describe("distance: Strecke je Wiederholung in distance_meters; duration: Dauer je Wiederholung in duration_seconds"),
  distance_meters: z.number().int().nullable().describe("Strecke je Wiederholung in Metern bei measure distance, sonst null"),
  duration_seconds: z.number().int().nullable().describe("Dauer je Wiederholung in Sekunden bei measure duration, sonst null"),
  target_type: z.enum(STEP_TARGETS).nullable().describe("Woran sich die Intensität ausrichtet (nur Ziele, die die Nutzernachricht für die Sportart erlaubt), null ohne Ziel"),
  target_value: z.number().nullable().describe("Zielwert in der Einheit des Ziels (Sekunden pro 100 m oder km, Zone 1 bis 5, Watt, 1 bis 10), null ohne Ziel"),
  rest_seconds: z.number().int().describe("Pause nach jeder Wiederholung in Sekunden"),
  instructions: z.string().describe("Anweisung für den Schritt in ein bis zwei Sätzen"),
  cue: z.string().describe("Kurztext für die Uhr: zwei bis vier Wörter, höchstens 30 Zeichen"),
  equipment: z.array(z.string()).describe("Hilfsmittel für diesen Schritt (nur die der Sportart, die der Athlet hat), sonst leer")
});

const TestId = z.string().nullable().describe("Nur bei session_type test: die Kennung des Leistungstests aus der Nutzernachricht, sonst null");

export const DaySessionSchema = z.object({
  sport: Sport,
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  focus: z.string().describe("Schwerpunkt der Einheit in höchstens 60 Zeichen auf Deutsch"),
  test_id: TestId,
  steps: z.array(StepSchema).describe("Die Schritte in der Reihenfolge des Trainings; bei einem Leistungstest setzt der Server sie selbst ein")
});

export const MultiDayPlanSchema = z.object({
  rationale: z.string().describe("Begründung auf Deutsch, höchstens vier Sätze, mit konkreten Zahlen aus dem Snapshot"),
  sessions: z.array(DaySessionSchema).describe("Null bis zwei Einheiten; ein Ruhetag hat keine"),
  coach_notes: z.array(z.string()).describe("Null bis drei kurze Hinweise auf Deutsch")
});

export const WeekSessionSchema = z.object({
  sport: Sport,
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  amount: z.number().int().describe("Umfang in der Einheit der Sportart (Meter oder Minuten, siehe Nutzernachricht)"),
  focus: z.string().describe("Schwerpunkt in höchstens 60 Zeichen auf Deutsch"),
  test_id: TestId
});

export const MultiWeekPlanSchema = z.object({
  rationale: z.string().describe("Begründung der Woche auf Deutsch, höchstens vier Sätze, mit konkreten Zahlen aus dem Snapshot"),
  days: z.array(
    z.object({
      date: z.string().describe("Kalendertag im Format YYYY-MM-DD, genau einer der angegebenen Tage"),
      focus: z.string().describe("Schwerpunkt des Tages in höchstens 60 Zeichen, z. B. Ruhetag oder Koppeltraining"),
      sessions: z.array(WeekSessionSchema).describe("Null bis zwei Einheiten; ein Ruhetag hat keine")
    })
  )
});

const MacroWeekRawSchema = z.object({
  week_start: z.string().describe("Montag der Woche im Format YYYY-MM-DD, genau eine der angegebenen Wochen"),
  deload: z.boolean().describe("true bei einer Entlastungswoche mit deutlich weniger Umfang als davor"),
  focus: z.string().describe("Schwerpunkt der Woche in höchstens 60 Zeichen auf Deutsch"),
  sports: z
    .array(
      z.object({
        sport: Sport,
        amount: z.number().int().describe("Wochenumfang in der Einheit der Sportart (Meter oder Minuten, siehe Nutzernachricht)"),
        sessions: z.number().int().describe("Einheiten dieser Sportart in der Woche")
      })
    )
    .describe("Jede geplante Sportart einmal")
});

export const MultiMacroPlanSchema = z.object({
  rationale: z.string().describe("Begründung des Gesamtplans auf Deutsch, höchstens fünf Sätze, mit konkreten Zahlen"),
  weeks: z.array(MacroWeekRawSchema)
});

export const MacroRevisionSchema = z.object({
  rationale: z.string().describe("Begründung des geänderten Gesamtplans auf Deutsch, höchstens fünf Sätze"),
  changes: z.array(z.string()).describe("Was sich gegenüber dem bisherigen Plan ändert, ein Punkt je Änderung, höchstens acht, auf Deutsch"),
  weeks: z.array(MacroWeekRawSchema)
});

export type StepRaw = z.infer<typeof StepSchema>;
export type DaySessionRaw = z.infer<typeof DaySessionSchema>;
export type MultiDayPlanRaw = z.infer<typeof MultiDayPlanSchema>;
export type WeekSessionRaw = z.infer<typeof WeekSessionSchema>;
export type MultiWeekPlanRaw = z.infer<typeof MultiWeekPlanSchema>;
export type MacroWeekRawV2 = z.infer<typeof MacroWeekRawSchema>;
export type MultiMacroPlanRaw = z.infer<typeof MultiMacroPlanSchema>;
export type MacroRevisionRaw = z.infer<typeof MacroRevisionSchema>;

// --- Was die App schickt ---

const DateString = z.string().regex(DATE_PATTERN);
const KnownSport = z.string().refine((id) => SPORTS.get(id) !== undefined, { message: "unbekannte Sportart" });
const Identifier = z.string().regex(/^[a-z][a-z0-9_]{1,39}$/);
const Amount = z.number().min(0).max(1_000_000);

/** Was der Athlet in den Tagen vor dem Plan trainiert hat (je Einheit), mit `hard` fuer eine harte Einheit. */
export const RecentTrainingSchema = z
  .array(z.object({ date: DateString, sport: KnownSport, minutes: z.number().min(0).max(1440), meters: Amount, hard: z.boolean().optional() }))
  .max(40);

/** Leistungstests: angeboten (Standard ja), Abstand fuer die Wiederholung (Standard 6 Wochen), bevorzugter Test je Sportart. */
export const TestSettingsSchema = z.object({
  offer: z.boolean().optional(),
  interval_weeks: z.number().int().min(4).max(12).optional(),
  preferred: z.array(z.object({ sport: KnownSport, test_id: Identifier })).max(16).optional()
});

/** Das Equipment des Athleten ueber alle Sportarten; fehlt das Feld, ist jedes erlaubt. */
export const EquipmentV2Schema = z.array(Identifier).max(32);

const TargetSession = z.object({
  sport: KnownSport,
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  amount: Amount,
  focus: z.string().max(120),
  test_id: Identifier.nullable().optional()
});

/** Was der Wochenplan fuer einen Tag vorgibt (Feld `day_plan` des Tagesplans v2). Keine Einheit: Ruhetag. */
export const DayTargetV2Schema = z.object({ focus: z.string().max(120).optional(), sessions: z.array(TargetSession).max(2) });

/** Was der Gesamtplan fuer eine Woche vorgibt (Feld `macro_weeks` des Wochenplans v2); die App schickt die Woche, wie sie sie bekam. */
export const MacroWeekTargetV2Schema = z.object({
  week_start: DateString,
  phase: z.enum(MACRO_PHASES),
  deload: z.boolean(),
  focus: z.string().max(120),
  sports: z.array(z.object({ sport: KnownSport, amount: Amount, sessions: z.number().int().min(0).max(14) })).max(16),
  tests: z.array(z.object({ sport: KnownSport, test_id: Identifier })).max(8).optional()
});

const PlanVersion = z.literal(2);

function requireV2<T extends { snapshot: { schema_version: number } }>(request: T, ctx: z.RefinementCtx): void {
  if (request.snapshot.schema_version !== 2) {
    ctx.addIssue({ code: "custom", path: ["snapshot", "schema_version"], message: "Plan v2 braucht Snapshot v2" });
  }
}

export const DayRequestV2Schema = z
  .object({
    plan_version: PlanVersion,
    snapshot: SnapshotSchema,
    regenerate: z.boolean().optional(),
    wishes: z.string().max(MAX_WISH_LENGTH).optional(),
    day_plan: DayTargetV2Schema.optional(),
    equipment: EquipmentV2Schema.optional(),
    recent_training: RecentTrainingSchema.optional(),
    test_settings: TestSettingsSchema.optional()
  })
  .superRefine(requireV2);

export const WeekRequestV2Schema = z
  .object({
    plan_version: PlanVersion,
    snapshot: SnapshotSchema,
    /** Erster der sieben geplanten Tage (rollender Plan), meist heute. */
    from_date: DateString,
    today: DateString,
    unavailable_dates: z.array(DateString).max(7).optional(),
    recent_training: RecentTrainingSchema.optional(),
    macro_weeks: z.array(MacroWeekTargetV2Schema).max(3).optional(),
    wishes: z.string().max(MAX_WISH_LENGTH).optional(),
    equipment: EquipmentV2Schema.optional(),
    test_settings: TestSettingsSchema.optional()
  })
  .superRefine(requireV2);

export const MacroRequestV2Schema = z
  .object({ plan_version: PlanVersion, snapshot: SnapshotSchema, today: DateString, test_settings: TestSettingsSchema.optional() })
  .superRefine(requireV2);

export const MAX_FEEDBACK_LENGTH = 1000;

/** Feedback zum Gesamtplan: der Plan, wie die App ihn haelt, das Feedback und die bisherigen Runden (hoechstens 5). */
export const ReviseRequestSchema = z
  .object({
    plan_version: PlanVersion.optional(),
    snapshot: SnapshotSchema,
    today: DateString,
    plan: z.object({ rationale: z.string().max(2000).optional(), weeks: z.array(MacroWeekTargetV2Schema).min(1).max(80) }),
    feedback: z.string().trim().min(1).max(MAX_FEEDBACK_LENGTH),
    history: z
      .array(z.object({ feedback: z.string().max(MAX_FEEDBACK_LENGTH), changes: z.array(z.string().max(300)).max(8) }))
      .max(5)
      .optional(),
    test_settings: TestSettingsSchema.optional()
  })
  .superRefine(requireV2);

export type RecentTraining = z.infer<typeof RecentTrainingSchema>[number];
export type TestSettings = z.infer<typeof TestSettingsSchema>;
export type DayTargetV2 = z.infer<typeof DayTargetV2Schema>;
export type MacroWeekTargetV2 = z.infer<typeof MacroWeekTargetV2Schema>;
export type FeedbackRound = NonNullable<z.infer<typeof ReviseRequestSchema>["history"]>[number];

/** Nach der Pruefung durch die Request-Schemas ist der Snapshot v2. */
export function asV2(snapshot: z.infer<typeof SnapshotSchema>): SnapshotV2 {
  return snapshot as SnapshotV2;
}
