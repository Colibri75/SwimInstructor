import { z } from "zod";
import { SPORTS } from "../../sports/registry";
import { STEP_TARGETS } from "../../sports/vocabulary";
import { MACRO_PHASES } from "../calendar";
import { INTENSITIES, SESSION_TYPES } from "../vocabulary";
import { SnapshotSchema } from "../snapshot";
import { DATE_PATTERN } from "../calendar";

/**
 * Schemas der Planung fuer mehrere Sportarten (Plan v2, docs/multisport-planning.md): was Claude liefert (ohne
 * Wertegrenzen, die prueft die Sicherheitsschicht) und was die App schickt (mit Grenzen).
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

/**
 * Neue Felder haben einen Standardwert: Claude muss sie liefern (im JSON-Schema stehen sie als Pflicht), gespeicherte
 * Plaene und aufgezeichnete Bewertungslaeufe ohne sie bleiben gueltig.
 */
const Brick = z
  .boolean()
  .describe("true, wenn die Einheit am selben Tag direkt an die vorige Einheit anschließt (Koppeltraining, nur die zweite Einheit des Tages), sonst false")
  .default(false);
const Indoor = z.boolean().describe("true: drinnen (Rolle oder Laufband, nur wenn die Nutzernachricht es erlaubt), sonst false").default(false);
const OpenWater = z.boolean().describe("true: im Freiwasser (See, Meer; nur wenn die Nutzernachricht es erlaubt), sonst false").default(false);

/** Ergaenzungstraining neben den Sportarten: Kraft und Mobilitaet (Dehnen, Beweglichkeit). */
export const EXTRA_KINDS = ["strength", "mobility"] as const;
export type ExtraKind = (typeof EXTRA_KINDS)[number];

const ExtraKind = z.enum(EXTRA_KINDS);

export const ExerciseSchema = z.object({
  name: z.string().describe("Name der Übung auf Deutsch, z. B. Kniebeuge, Ausfallschritt, Hüftbeuger-Dehnung"),
  sets: z.number().int().describe("Anzahl der Sätze, 1 bis 5"),
  reps: z.number().int().nullable().describe("Wiederholungen je Satz, null bei einer Übung nach Zeit"),
  seconds: z.number().int().nullable().describe("Dauer je Satz in Sekunden bei einer Übung nach Zeit (Halten, Dehnen), sonst null"),
  rest_seconds: z.number().int().describe("Pause nach jedem Satz in Sekunden"),
  cue: z.string().describe("Kurztext: zwei bis vier Wörter, höchstens 30 Zeichen"),
  instructions: z.string().describe("Ausführung in ein bis zwei Sätzen, ohne Geräte außer dem eigenen Körpergewicht, einem Band oder einer Matte")
});

const WeekExtraSchema = z.object({
  kind: ExtraKind,
  minutes: z.number().int().describe("Dauer in Minuten"),
  focus: z.string().describe("Schwerpunkt in höchstens 60 Zeichen, z. B. Rumpf und Hüfte")
});

const DayExtraSchema = WeekExtraSchema.extend({
  exercises: z.array(ExerciseSchema).describe("Die Übungen in der Reihenfolge, höchstens 10")
});

export const DaySessionSchema = z.object({
  sport: Sport,
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  focus: z.string().describe("Schwerpunkt der Einheit in höchstens 60 Zeichen auf Deutsch"),
  test_id: TestId,
  brick: Brick,
  indoor: Indoor,
  open_water: OpenWater,
  steps: z.array(StepSchema).describe("Die Schritte in der Reihenfolge des Trainings; bei einem Leistungstest setzt der Server sie selbst ein")
});

export const MultiDayPlanSchema = z.object({
  rationale: z.string().describe("Begründung auf Deutsch, höchstens vier Sätze, mit konkreten Zahlen aus dem Snapshot"),
  sessions: z.array(DaySessionSchema).describe("Null bis zwei Einheiten; ein Ruhetag hat keine"),
  extras: z.array(DayExtraSchema).describe("Kraft- oder Mobilitätsblock heute, nur wenn die Nutzernachricht ihn vorsieht, sonst leer").default([]),
  coach_notes: z.array(z.string()).describe("Null bis drei kurze Hinweise auf Deutsch")
});

export const WeekSessionSchema = z.object({
  sport: Sport,
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  amount: z.number().int().describe("Umfang in der Einheit der Sportart (Meter oder Minuten, siehe Nutzernachricht)"),
  focus: z.string().describe("Schwerpunkt in höchstens 60 Zeichen auf Deutsch"),
  test_id: TestId,
  brick: Brick,
  indoor: Indoor,
  open_water: OpenWater
});

export const MultiWeekPlanSchema = z.object({
  rationale: z.string().describe("Begründung der Woche auf Deutsch, höchstens vier Sätze, mit konkreten Zahlen aus dem Snapshot"),
  days: z.array(
    z.object({
      date: z.string().describe("Kalendertag im Format YYYY-MM-DD, genau einer der angegebenen Tage"),
      focus: z.string().describe("Schwerpunkt des Tages in höchstens 60 Zeichen, z. B. Ruhetag oder Koppeltraining"),
      sessions: z.array(WeekSessionSchema).describe("Null bis zwei Einheiten; ein Ruhetag hat keine"),
      extras: z.array(WeekExtraSchema).describe("Kraft- oder Mobilitätsblock an diesem Tag, nur wenn die Nutzernachricht sie vorsieht, sonst leer").default([])
    })
  )
});

/**
 * Der Gesamtplan kommt von Claude in Abschnitten statt Woche fuer Woche: Eine Woche je Zeile ueber 40 Wochen und drei
 * Sportarten dauerte zu lange fuer das Zeitlimit. Der Server rechnet die Abschnitte in Wochen um (`expandMacroBlocks`),
 * danach prueft die Sicherheitsschicht jede Woche.
 */
const MacroBlockRawSchema = z.object({
  weeks: z.number().int().describe("Anzahl der Wochen dieses Abschnitts, 1 bis 6; die Abschnitte folgen lückenlos aufeinander"),
  deload_last: z.boolean().describe("true, wenn die letzte Woche des Abschnitts eine Entlastungswoche ist"),
  focus: z.string().describe("Schwerpunkt des Abschnitts in höchstens 60 Zeichen auf Deutsch"),
  sports: z
    .array(
      z.object({
        sport: Sport,
        start_amount: z.number().int().describe("Wochenumfang der ersten Woche des Abschnitts in der Einheit der Sportart (Meter oder Minuten, siehe Nutzernachricht)"),
        end_amount: z.number().int().describe("Wochenumfang der letzten Woche ohne Entlastung; dazwischen steigt oder sinkt der Umfang gleichmäßig"),
        deload_amount: z.number().int().nullable().describe("Wochenumfang der Entlastungswoche, null ohne Entlastungswoche"),
        sessions: z.number().int().describe("Einheiten dieser Sportart je Woche")
      })
    )
    .describe("Jede geplante Sportart einmal")
});

export const MultiMacroPlanSchema = z.object({
  rationale: z.string().describe("Begründung des Gesamtplans auf Deutsch, höchstens fünf Sätze, mit konkreten Zahlen"),
  blocks: z.array(MacroBlockRawSchema).describe("Die Abschnitte von der ersten Woche bis zur Zielwoche, in zeitlicher Reihenfolge")
});

export const MacroRevisionSchema = z.object({
  rationale: z.string().describe("Begründung des geänderten Gesamtplans auf Deutsch, höchstens fünf Sätze"),
  changes: z.array(z.string()).describe("Was sich gegenüber dem bisherigen Plan ändert, ein Punkt je Änderung, höchstens acht, auf Deutsch"),
  blocks: z.array(MacroBlockRawSchema).describe("Die Abschnitte von der ersten Woche bis zur Zielwoche, in zeitlicher Reihenfolge")
});

export const MacroReviewSchema = z.object({
  summary: z.string().describe("Bilanz der letzten Wochen in zwei, drei Sätzen auf Deutsch: Plan gegen Ist je Sportart in Prozent, Auffälligkeiten wie Pause oder Krankheit"),
  rationale: z.string().describe("Begründung des fortgeschriebenen Gesamtplans auf Deutsch, höchstens fünf Sätze"),
  changes: z.array(z.string()).describe("Was sich gegenüber dem bisherigen Plan ändert, ein Punkt je Änderung, höchstens acht, auf Deutsch"),
  blocks: z.array(MacroBlockRawSchema).describe("Die Abschnitte von der laufenden Woche bis zur Zielwoche, in zeitlicher Reihenfolge")
});

/** Eine Woche des Gesamtplans, wie die Sicherheitsschicht sie prueft (aus den Abschnitten berechnet). */
export interface MacroWeekRawV2 {
  week_start: string;
  deload: boolean;
  focus: string;
  sports: { sport: string; amount: number; sessions: number }[];
}

/** Der Gesamtplan Woche fuer Woche, Eingang der Sicherheitsschicht. */
export interface MacroWeeksRaw {
  rationale: string;
  weeks: MacroWeekRawV2[];
}

export type StepRaw = z.infer<typeof StepSchema>;
export type ExerciseRaw = z.infer<typeof ExerciseSchema>;
export type WeekExtraRaw = z.infer<typeof WeekExtraSchema>;
export type DayExtraRaw = z.infer<typeof DayExtraSchema>;
// Eingangstypen der Sicherheitsschicht: Felder mit Standardwert duerfen fehlen (gespeicherte Plaene, Tests).
export type DaySessionRaw = z.input<typeof DaySessionSchema>;
export type MultiDayPlanRaw = z.input<typeof MultiDayPlanSchema>;
export type WeekSessionRaw = z.input<typeof WeekSessionSchema>;
export type MultiWeekPlanRaw = z.input<typeof MultiWeekPlanSchema>;
export type MacroBlockRaw = z.infer<typeof MacroBlockRawSchema>;
export type MultiMacroPlanRaw = z.infer<typeof MultiMacroPlanSchema>;
export type MacroRevisionRaw = z.infer<typeof MacroRevisionSchema>;
export type MacroReviewRaw = z.infer<typeof MacroReviewSchema>;

// --- Was die App schickt ---

export const DateString = z.string().regex(DATE_PATTERN);
const KnownSport = z.string().refine((id) => SPORTS.get(id) !== undefined, { message: "unbekannte Sportart" });
const Identifier = z.string().regex(/^[a-z][a-z0-9_]{1,39}$/);
const Amount = z.number().min(0).max(1_000_000);

/** Wo der Athlet nach einer Einheit Beschwerden hatte (Rueckmeldung in der App). */
export const PAIN_AREAS = ["knee", "shin", "achilles", "foot", "hip", "back", "shoulder", "other"] as const;
export type PainArea = (typeof PAIN_AREAS)[number];

/**
 * Was der Athlet in den Tagen vor dem Plan trainiert hat (je Einheit), mit `hard` fuer eine harte Einheit, der gefuehlten
 * Anstrengung (0 bis 10, aus Health oder vom Athleten) und Beschwerden (0 keine, 1 leicht, 2 deutlich, 3 stark).
 */
export const RecentTrainingSchema = z
  .array(
    z.object({
      date: DateString,
      sport: KnownSport,
      minutes: z.number().min(0).max(1440),
      meters: Amount,
      hard: z.boolean().optional(),
      effort: z.number().min(0).max(10).optional(),
      pain: z.number().int().min(0).max(3).optional(),
      pain_area: z.enum(PAIN_AREAS).optional()
    })
  )
  .max(40);

/** Eine geplante Einheit der letzten Tage, die der Athlet nicht gemacht hat. */
export const MissedSessionSchema = z.object({
  date: DateString,
  sport: KnownSport,
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  amount: Amount
});

/** Warum die App die sieben Tage neu plant: taeglich, nach verpassten Einheiten, nach sehr harter Einheit, Beschwerden, von Hand. */
export const REPLAN_REASONS = ["daily", "missed", "effort", "pain", "manual"] as const;
export type ReplanReason = (typeof REPLAN_REASONS)[number];

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
  test_id: Identifier.nullable().optional(),
  brick: z.boolean().optional(),
  indoor: z.boolean().optional(),
  open_water: z.boolean().optional()
});

const TargetExtra = z.object({ kind: ExtraKind, minutes: z.number().int().min(1).max(120), focus: z.string().max(120) });

/** Was der Wochenplan fuer einen Tag vorgibt (Feld `day_plan` des Tagesplans v2). Keine Einheit: Ruhetag. */
export const DayTargetV2Schema = z.object({
  focus: z.string().max(120).optional(),
  sessions: z.array(TargetSession).max(2),
  extras: z.array(TargetExtra).max(2).optional()
});

/** Wie oft pro Woche Kraft und Mobilitaet dazukommen sollen (Einstellung in der App). */
export const SupplementsSchema = z.object({
  strength_per_week: z.number().int().min(0).max(3),
  mobility_per_week: z.number().int().min(0).max(7)
});

/** Ungefaehrer Ort fuer die Wettervorhersage (die App rundet auf eine Nachkommastelle, etwa 10 km). */
export const LocationSchema = z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) });

/** Freie Zeit je Tag laut Kalender des Athleten, in Minuten (laengster freier Block im Trainingsfenster). */
export const AvailabilitySchema = z.array(z.object({ date: DateString, minutes: z.number().int().min(0).max(1440) })).max(14);

/** Was der Gesamtplan fuer eine Woche vorgibt (Feld `macro_weeks` des Wochenplans v2); die App schickt die Woche, wie sie sie bekam. */
export const MacroWeekTargetV2Schema = z.object({
  week_start: DateString,
  phase: z.enum(MACRO_PHASES),
  deload: z.boolean(),
  focus: z.string().max(120),
  sports: z.array(z.object({ sport: KnownSport, amount: Amount, sessions: z.number().int().min(0).max(14) })).max(16),
  tests: z.array(z.object({ sport: KnownSport, test_id: Identifier })).max(8).optional()
});

export const MAX_WISH_LENGTH = 500;

/** Jede Anfrage nennt `plan_version: 2`; fehlt es, ist die App veraltet (der Plan von Version 1 wird nicht mehr beantwortet). */
export const PlanVersion = z.literal(2, { error: "plan_version 2 erforderlich: Diese App-Version ist veraltet, bitte aktualisieren" });

export const DayRequestV2Schema = z
  .object({
    plan_version: PlanVersion,
    snapshot: SnapshotSchema,
    regenerate: z.boolean().optional(),
    wishes: z.string().max(MAX_WISH_LENGTH).optional(),
    day_plan: DayTargetV2Schema.optional(),
    equipment: EquipmentV2Schema.optional(),
    recent_training: RecentTrainingSchema.optional(),
    test_settings: TestSettingsSchema.optional(),
    supplements: SupplementsSchema.optional(),
    location: LocationSchema.optional(),
    available_minutes: z.number().int().min(0).max(1440).optional()
  });

export const WeekRequestV2Schema = z
  .object({
    plan_version: PlanVersion,
    snapshot: SnapshotSchema,
    /** Erster der sieben geplanten Tage (rollender Plan), meist heute. */
    from_date: DateString,
    today: DateString,
    unavailable_dates: z.array(DateString).max(7).optional(),
    recent_training: RecentTrainingSchema.optional(),
    missed_sessions: z.array(MissedSessionSchema).max(14).optional(),
    reason: z.enum(REPLAN_REASONS).optional(),
    macro_weeks: z.array(MacroWeekTargetV2Schema).max(3).optional(),
    wishes: z.string().max(MAX_WISH_LENGTH).optional(),
    equipment: EquipmentV2Schema.optional(),
    test_settings: TestSettingsSchema.optional(),
    supplements: SupplementsSchema.optional(),
    location: LocationSchema.optional(),
    availability: AvailabilitySchema.optional()
  });

export const MacroRequestV2Schema = z
  .object({ plan_version: PlanVersion, snapshot: SnapshotSchema, today: DateString, test_settings: TestSettingsSchema.optional() });

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
  });

/** Anlass der Fortschreibung: alle 2 Wochen, nach einer gemeldeten Pause oder nach zwei schwachen Wochen. */
export const REVIEW_REASONS = ["scheduled", "pause", "low_compliance"] as const;
export const PAUSE_KINDS = ["sick", "injury", "vacation", "other"] as const;

/** Was in einer vergangenen Woche tatsaechlich trainiert wurde, je Sportart in ihrer Planeinheit. */
const ActualWeekSchema = z.object({
  week_start: DateString,
  sports: z.array(z.object({ sport: KnownSport, amount: Amount, sessions: z.number().int().min(0).max(30) })).max(16)
});

/** Ein vom Athleten bestaetigter Leistungswert (Test oder Eingabe), der seit dem letzten Stand des Gesamtplans neu ist. */
const PerformanceChangeSchema = z.object({
  sport: KnownSport.optional(),
  metric: Identifier,
  /** Der Wert, der beim letzten Stand galt; fehlt, wenn es keinen bestaetigten gab. */
  previous: z.number().positive().max(100_000).optional(),
  value: z.number().positive().max(100_000),
  source: z.enum(["tested", "manual"]),
  measured_at: z.iso.datetime()
});

/** Fortschreibung des Gesamtplans (P4): der Plan, wie die App ihn haelt, das Ist der letzten Wochen, der Anlass. */
export const ReviewRequestSchema = z
  .object({
    plan_version: PlanVersion.optional(),
    snapshot: SnapshotSchema,
    today: DateString,
    plan: z.object({ rationale: z.string().max(2000).optional(), weeks: z.array(MacroWeekTargetV2Schema).min(1).max(80) }),
    actual: z.array(ActualWeekSchema).max(12),
    reason: z.enum(REVIEW_REASONS),
    pause: z.object({ from: DateString, to: DateString.optional(), kind: z.enum(PAUSE_KINDS) }).optional(),
    feedback: z.string().trim().min(1).max(MAX_FEEDBACK_LENGTH).optional(),
    performance_changes: z.array(PerformanceChangeSchema).max(20).optional(),
    test_settings: TestSettingsSchema.optional()
  });

export type ReviewRequest = z.infer<typeof ReviewRequestSchema>;
export type ActualWeek = z.infer<typeof ActualWeekSchema>;
export type ReviewReason = (typeof REVIEW_REASONS)[number];
export type PauseReport = NonNullable<ReviewRequest["pause"]>;
export type PerformanceChange = z.infer<typeof PerformanceChangeSchema>;

export type RecentTraining = z.infer<typeof RecentTrainingSchema>[number];
export type MissedSession = z.infer<typeof MissedSessionSchema>;
export type Supplements = z.infer<typeof SupplementsSchema>;
export type GeoLocation = z.infer<typeof LocationSchema>;
export type Availability = z.infer<typeof AvailabilitySchema>[number];
export type TestSettings = z.infer<typeof TestSettingsSchema>;
export type DayTargetV2 = z.infer<typeof DayTargetV2Schema>;
export type MacroWeekTargetV2 = z.infer<typeof MacroWeekTargetV2Schema>;
export type FeedbackRound = NonNullable<z.infer<typeof ReviseRequestSchema>["history"]>[number];
