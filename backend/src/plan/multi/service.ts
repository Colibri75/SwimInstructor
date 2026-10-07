import { createHash } from "node:crypto";
import { Logger } from "pino";
import { z } from "zod";
import { OWNER_ID } from "../../users";
import { UsageOutcome, UsageRecorder } from "../../usage";
import { GenerationBudget, UserBudgets } from "../budget";
import { FallbackReason, PlanGenerationError, PlanRequestError, PlanUnavailableError } from "../errors";
import { CallOptions, GeneratedPlan, StructuredGenerator } from "../generator";
import { daysBetween, localDate, macroWeekStarts, windowDates } from "../calendar";
import { buildRaceUserMessage, RACE_SYSTEM_PROMPT, RacePlan, RacePlanSchema, sanitizeRace } from "./race";
import { SnapshotV2 } from "../snapshot";
import { DayOptionsV2, DayPlanV2, sanitizeDayV2 } from "./daySanity";
import { DayWeather, roundLocation, WeatherProvider } from "../weather";
import { goalDayOf, MULTI_RULES } from "./limits";
import { expandMacroBlocks, MacroContextV2, MacroPlanV2, sanitizeMacroV2 } from "./macroSanity";
import {
  buildDayUserMessageV2,
  buildMacroUserMessageV2,
  buildReviseUserMessage,
  buildReviewUserMessage,
  buildWeekUserMessageV2,
  MULTI_DAY_SYSTEM_PROMPT,
  MULTI_MACRO_SYSTEM_PROMPT,
  MULTI_REVISE_SYSTEM_PROMPT,
  MULTI_REVIEW_SYSTEM_PROMPT,
  MULTI_WEEK_SYSTEM_PROMPT,
  performanceSection
} from "./prompts";
import {
  DayTargetV2,
  FeedbackRound,
  FixedDay,
  MacroReviewSchema,
  MacroRevisionSchema,
  MacroWeekTargetV2,
  MultiDayPlanSchema,
  MultiMacroPlanSchema,
  MultiWeekPlanSchema,
  MissedSession,
  PauseReport,
  ReplanReason,
  Availability,
  GeoLocation,
  Supplements,
  PerformanceChange,
  RecentTraining,
  ReviewReason,
  ActualWeek,
  TestSettings
} from "./schemas";
import { asRawDayPlan, DayPlanStoreV2, StoredDayV2 } from "./store";
import { sanitizeWeekV2, WeekContextV2, WeekPlanV2 } from "./weekSanity";

/**
 * Plan v2 fuer mehrere Sportarten: Tag, sieben Tage, Gesamtplan und Feedback zum Gesamtplan. Ablauf:
 * Claude fragen (mit Budget), das Ergebnis gegen das Schema und durch die Sicherheitsschicht. Nur der Tagesplan hat
 * Cache und Fallback auf den letzten gueltigen Plan; Woche und Gesamtplan haelt die App, sie behaelt bei einem Ausfall
 * ihren bisherigen.
 */
export interface MultiServiceDeps {
  /** `null`, wenn kein ANTHROPIC_API_KEY konfiguriert ist. */
  generator: StructuredGenerator | null;
  /** Der Speicher des letzten Tagesplans: einer fuer alle oder einer je Nutzer. */
  store: DayPlanStoreV2 | ((user: string) => DayPlanStoreV2);
  /** Das Budget des ganzen Servers (Kostenbremse). */
  budget: GenerationBudget;
  /** Zusaetzlich ein Budget je Nutzer, damit einer nicht das der anderen aufbraucht. */
  userBudgets?: UserBudgets;
  /** Nimmt jede Anfrage mit Ergebnis, Token und Dauer auf (Monitoring). */
  usage?: UsageRecorder;
  /** Wettervorhersage; ohne sie (oder ohne Ort in der Anfrage) wird ohne Wetter geplant. */
  weather?: WeatherProvider;
  logger: Logger;
  timezone: string;
  now?: () => Date;
}

export interface DayInputV2 {
  /** Kennung des Nutzers (Token), Standard der Besitzer. */
  user?: string;
  snapshot: SnapshotV2;
  /** Vorschau fuer einen kommenden Tag (1 bis `PREVIEW_DAYS` nach heute); ohne Angabe heute. */
  date?: string;
  regenerate?: boolean;
  wishes?: string;
  dayTarget?: DayTargetV2;
  equipment?: readonly string[];
  recent?: readonly RecentTraining[];
  testSettings?: TestSettings;
  supplements?: Supplements;
  location?: GeoLocation;
  /** Freie Minuten heute laut Kalender. */
  availableMinutes?: number;
}

export interface DayResultV2 {
  source: "claude" | "cache" | "fallback";
  date: string;
  generatedAt: string;
  stale: boolean;
  plan: DayPlanV2;
  adjustments: string[];
  fallbackReason?: FallbackReason;
  wishes?: string;
}

export interface WeekInputV2 {
  /** Kennung des Nutzers (Token), Standard der Besitzer. */
  user?: string;
  snapshot: SnapshotV2;
  fromDate: string;
  today: string;
  unavailable: string[];
  /** Feste Tage (von Hand geaendert, heute schon geplant): bleiben, wie sie sind. */
  fixed?: FixedDay[];
  /** Training der Tage davor; Eintraege ab `fromDate` (heute schon trainiert) zaehlen nur mit ihren Beschwerden. */
  recent: RecentTraining[];
  missed?: MissedSession[];
  reason?: ReplanReason;
  macroWeeks?: MacroWeekTargetV2[];
  wishes?: string;
  equipment?: readonly string[];
  testSettings?: TestSettings;
  supplements?: Supplements;
  location?: GeoLocation;
  availability?: Availability[];
}

export interface WeekResultV2 {
  fromDate: string;
  generatedAt: string;
  plan: WeekPlanV2;
  adjustments: string[];
  wishes?: string;
}

export interface MacroResultV2 {
  goalDay: string;
  generatedAt: string;
  plan: MacroPlanV2;
  adjustments: string[];
}

export interface ReviseInput {
  /** Kennung des Nutzers (Token), Standard der Besitzer. */
  user?: string;
  snapshot: SnapshotV2;
  today: string;
  plan: { rationale?: string; weeks: MacroWeekTargetV2[] };
  feedback: string;
  history: FeedbackRound[];
  testSettings?: TestSettings;
}

export interface ReviseResult extends MacroResultV2 {
  /** Was sich laut Claude geaendert hat, auf Deutsch. */
  changes: string[];
  feedback: string;
}

export interface ReviewInput {
  /** Kennung des Nutzers (Token), Standard der Besitzer. */
  user?: string;
  snapshot: SnapshotV2;
  today: string;
  plan: { rationale?: string; weeks: MacroWeekTargetV2[] };
  actual: ActualWeek[];
  reason: ReviewReason;
  pause?: PauseReport;
  feedback?: string;
  performanceChanges?: PerformanceChange[];
  testSettings?: TestSettings;
}

export interface ReviewResult extends MacroResultV2 {
  /** Die Bilanz der letzten Wochen, auf Deutsch. */
  summary: string;
  changes: string[];
  reason: ReviewReason;
  /** Das Feedback zur Fortschreibung, so wie der Server es gelesen hat; fehlt ohne Feedback. */
  feedback?: string;
}

export interface MacroInputV2 {
  snapshot: SnapshotV2;
  today: string;
  testSettings?: TestSettings;
  user?: string;
}

/** Was ein Claude-Aufruf verbraucht hat, auch wenn er danach scheiterte (fuer die Nutzung). */
interface Attempt {
  meta?: GeneratedPlan;
  latencyMs?: number;
}

export interface RaceInput {
  user?: string;
  snapshot: SnapshotV2;
  today: string;
  startTime?: string;
  location?: GeoLocation;
  bodyWeightKg?: number;
  notes?: string;
}

export interface RaceResult {
  raceDay: string;
  generatedAt: string;
  plan: RacePlan;
  adjustments: string[];
  /** Die Vorhersage fuer den Wettkampftag, wenn es schon eine gab. */
  weather?: DayWeather;
}

/** So weit reicht die Vorhersage (Open-Meteo: 14 Tage). */
const FORECAST_DAYS = 14;
/** So weit im Voraus zeigt der Tagesplan eine Vorschau (der Plan-Tab reicht bis in die naechste Woche). */
export const PREVIEW_DAYS = 13;

export class MultiPlanService {
  private readonly now: () => Date;

  constructor(private readonly deps: MultiServiceDeps) {
    this.now = deps.now ?? (() => new Date());
  }

  async planDay(input: DayInputV2): Promise<DayResultV2> {
    const user = input.user ?? OWNER_ID;
    return this.tracked("day", user, (attempt) => this.dayPlan(input, user, attempt), (result) => ({ outcome: result.source, reason: result.fallbackReason }));
  }

  private async dayPlan(input: DayInputV2, user: string, attempt: Attempt): Promise<DayResultV2> {
    const { logger } = this.deps;
    const store = this.storeFor(user);
    const today = localDate(this.now(), this.deps.timezone);
    if (input.date !== undefined && input.date !== today) return this.previewDay(input, user, attempt, today, input.date);
    const wishes = input.wishes?.trim() || undefined;
    const hash = dayHash(input, wishes);
    const weather = input.location !== undefined ? (await this.weatherFor(input.location, [today]))[0] : undefined;
    const options: DayOptionsV2 = {
      date: today,
      equipment: input.equipment,
      recent: input.recent ?? [],
      testSettings: input.testSettings,
      supplements: input.supplements,
      ...(input.dayTarget !== undefined ? { plannedExtras: (input.dayTarget.extras ?? []).map((extra) => extra.kind) } : {}),
      ...(input.availableMinutes !== undefined ? { availableMinutes: input.availableMinutes } : {}),
      ...(weather !== undefined ? { weather } : {})
    };

    const stored = await this.latestOrNull(store);
    if (input.regenerate !== true && stored !== null && stored.date === today && stored.hash === hash) {
      logger.info({ date: today }, "plan v2 served from cache");
      return { source: "cache", date: today, generatedAt: stored.generatedAt, stale: false, plan: stored.plan, adjustments: stored.adjustments, ...(wishes ? { wishes } : {}) };
    }

    let generated: { data: z.infer<typeof MultiDayPlanSchema>; meta: GeneratedPlan };
    try {
      generated = await this.generate(
        "day",
        MULTI_DAY_SYSTEM_PROMPT,
        buildDayUserMessageV2({
          snapshot: input.snapshot,
          date: today,
          wishes,
          dayTarget: input.dayTarget,
          equipment: input.equipment,
          recent: input.recent,
          testSettings: input.testSettings,
          supplements: input.supplements,
          availableMinutes: input.availableMinutes,
          weather
        }),
        MultiDayPlanSchema,
        user,
        attempt
      );
    } catch (error) {
      if (error instanceof PlanUnavailableError) return this.fallback(error.reason, input.snapshot, today, stored, options);
      throw error;
    }
    const sanitized = sanitizeDayV2(generated.data, input.snapshot, options);
    if (sanitized.blocked !== null) {
      logger.warn({ reason: sanitized.blocked }, "claude plan v2 blocked by sanity layer");
      return this.fallback("sanity_blocked", input.snapshot, today, stored, options);
    }
    const record: StoredDayV2 = {
      date: today,
      hash,
      generatedAt: this.now().toISOString(),
      model: generated.meta.model,
      plan: sanitized.plan,
      adjustments: sanitized.adjustments
    };
    await this.saveQuietly(store, record);
    this.logGenerated("day", generated.meta, sanitized.adjustments.length, { sessions: sanitized.plan.sessions.length, wishChars: wishes?.length ?? 0 });
    return { source: "claude", date: today, generatedAt: record.generatedAt, stale: false, plan: record.plan, adjustments: record.adjustments, ...(wishes ? { wishes } : {}) };
  }

  /**
   * Der konkrete Plan fuer einen kommenden Tag, damit der Athlet ihn im Plan-Tab ansehen kann. Ohne Cache und ohne
   * Fallback, und er ersetzt nicht den gespeicherten Plan von heute; am Tag selbst entsteht der Plan neu.
   */
  private async previewDay(input: DayInputV2, user: string, attempt: Attempt, today: string, date: string): Promise<DayResultV2> {
    const ahead = daysBetween(today, date);
    if (ahead < 1 || ahead > PREVIEW_DAYS) throw new PlanRequestError("date", `Vorschau nur für die nächsten ${PREVIEW_DAYS} Tage`);
    const wishes = input.wishes?.trim() || undefined;
    const weather = input.location !== undefined ? (await this.weatherFor(input.location, [date]))[0] : undefined;
    const options: DayOptionsV2 = {
      date,
      preview: true,
      equipment: input.equipment,
      recent: input.recent ?? [],
      testSettings: input.testSettings,
      supplements: input.supplements,
      ...(input.dayTarget !== undefined ? { plannedExtras: (input.dayTarget.extras ?? []).map((extra) => extra.kind) } : {}),
      ...(input.availableMinutes !== undefined ? { availableMinutes: input.availableMinutes } : {}),
      ...(weather !== undefined ? { weather } : {})
    };
    const generated = await this.generate(
      "day",
      MULTI_DAY_SYSTEM_PROMPT,
      buildDayUserMessageV2({
        snapshot: input.snapshot,
        date,
        wishes,
        dayTarget: input.dayTarget,
        equipment: input.equipment,
        recent: input.recent,
        testSettings: input.testSettings,
        supplements: input.supplements,
        availableMinutes: input.availableMinutes,
        weather,
        preview: true
      }),
      MultiDayPlanSchema,
      user,
      attempt
    );
    const sanitized = sanitizeDayV2(generated.data, input.snapshot, options);
    if (sanitized.blocked !== null) throw this.blocked("day", sanitized.blocked);
    this.logGenerated("day", generated.meta, sanitized.adjustments.length, { sessions: sanitized.plan.sessions.length, preview: "yes" });
    return { source: "claude", date, generatedAt: this.now().toISOString(), stale: false, plan: sanitized.plan, adjustments: sanitized.adjustments, ...(wishes ? { wishes } : {}) };
  }

  async planWeek(input: WeekInputV2): Promise<WeekResultV2> {
    const user = input.user ?? OWNER_ID;
    return this.tracked("week", user, (attempt) => this.weekPlan(input, user, attempt), () => ({ outcome: "claude" }));
  }

  private async weekPlan(input: WeekInputV2, user: string, attempt: Attempt): Promise<WeekResultV2> {
    const wishes = input.wishes?.trim() || undefined;
    const dates = windowDates(input.fromDate, 7);
    const weather = input.location !== undefined ? await this.weatherFor(input.location, dates) : [];
    const context: WeekContextV2 = {
      today: input.today,
      dates,
      ...(input.equipment !== undefined ? { equipment: input.equipment } : {}),
      ...(input.availability !== undefined && input.availability.length > 0 ? { availability: input.availability } : {}),
      ...(weather.length > 0 ? { weather } : {}),
      ...(input.supplements !== undefined ? { supplements: input.supplements } : {}),
      unavailable: input.unavailable,
      ...(input.fixed !== undefined && input.fixed.length > 0 ? { fixed: input.fixed } : {}),
      recent: input.recent.filter((entry) => entry.date < input.fromDate),
      reports: input.recent.filter((entry) => (entry.pain ?? 0) > 0),
      ...(input.missed !== undefined && input.missed.length > 0 ? { missed: input.missed } : {}),
      ...(input.reason !== undefined ? { reason: input.reason } : {}),
      ...(input.macroWeeks !== undefined && input.macroWeeks.length > 0 ? { macroWeeks: input.macroWeeks } : {}),
      ...(input.testSettings !== undefined ? { testSettings: input.testSettings } : {})
    };
    const generated = await this.generate(
      "week",
      MULTI_WEEK_SYSTEM_PROMPT,
      buildWeekUserMessageV2({ snapshot: input.snapshot, context, wishes, equipment: input.equipment }),
      MultiWeekPlanSchema,
      user,
      attempt
    );
    const sanitized = sanitizeWeekV2(generated.data, input.snapshot, context);
    if (sanitized.blocked !== null) throw this.blocked("week", sanitized.blocked);
    this.logGenerated("week", generated.meta, sanitized.adjustments.length, { wishChars: wishes?.length ?? 0 });
    return { fromDate: input.fromDate, generatedAt: this.now().toISOString(), plan: sanitized.plan, adjustments: sanitized.adjustments, ...(wishes ? { wishes } : {}) };
  }

  async planMacro(input: MacroInputV2): Promise<MacroResultV2> {
    const user = input.user ?? OWNER_ID;
    return this.tracked("macro", user, (attempt) => this.macroPlan(input, user, attempt), () => ({ outcome: "claude" }));
  }

  private async macroPlan(input: MacroInputV2, user: string, attempt: Attempt): Promise<MacroResultV2> {
    const context = macroContext(input.snapshot, input.today, input.testSettings);
    const generated = await this.generate("macro", MULTI_MACRO_SYSTEM_PROMPT, buildMacroUserMessageV2(input.snapshot, context), MultiMacroPlanSchema, user, attempt, { macro: true });
    const weeks = expandMacroBlocks(generated.data.blocks, context.weeks);
    const sanitized = sanitizeMacroV2({ rationale: generated.data.rationale, weeks }, input.snapshot, context);
    if (sanitized.blocked !== null) throw this.blocked("macro", sanitized.blocked);
    this.logGenerated("macro", generated.meta, sanitized.adjustments.length, { blocks: generated.data.blocks.length, weeks: sanitized.plan.weeks.length });
    return { goalDay: context.goalDay, generatedAt: this.now().toISOString(), plan: sanitized.plan, adjustments: sanitized.adjustments };
  }

  async reviseMacro(input: ReviseInput): Promise<ReviseResult> {
    const user = input.user ?? OWNER_ID;
    return this.tracked("revise", user, (attempt) => this.revise(input, user, attempt), () => ({ outcome: "claude" }));
  }

  private async revise(input: ReviseInput, user: string, attempt: Attempt): Promise<ReviseResult> {
    const context = macroContext(input.snapshot, input.today, input.testSettings);
    const feedback = input.feedback.trim();
    const generated = await this.generate(
      "revise",
      MULTI_REVISE_SYSTEM_PROMPT,
      buildReviseUserMessage({ snapshot: input.snapshot, context, plan: input.plan, feedback, history: input.history }),
      MacroRevisionSchema,
      user,
      attempt,
      { macro: true }
    );
    const weeks = expandMacroBlocks(generated.data.blocks, context.weeks);
    const sanitized = sanitizeMacroV2({ rationale: generated.data.rationale, weeks }, input.snapshot, context);
    if (sanitized.blocked !== null) throw this.blocked("revise", sanitized.blocked);
    const changes = generated.data.changes
      .map((change) => change.trim().slice(0, MULTI_RULES.maxChangeLength))
      .filter((change) => change !== "")
      .slice(0, MULTI_RULES.maxChanges);
    this.logGenerated("revise", generated.meta, sanitized.adjustments.length, { blocks: generated.data.blocks.length, weeks: sanitized.plan.weeks.length, changes: changes.length, feedbackChars: feedback.length });
    return { goalDay: context.goalDay, generatedAt: this.now().toISOString(), plan: sanitized.plan, adjustments: sanitized.adjustments, changes, feedback };
  }

  /**
   * Fortschreibung (P4): Plan gegen Ist der letzten Wochen, Anlass und optional Feedback; die Antwort hat die Wochen ab der
   * laufenden, die Bilanz und die Aenderungen. Die laufende Woche haelt die App fest (sie ersetzt sie durch ihre).
   */
  async reviewMacro(input: ReviewInput): Promise<ReviewResult> {
    const user = input.user ?? OWNER_ID;
    return this.tracked("review", user, (attempt) => this.review(input, user, attempt), () => ({ outcome: "claude" }));
  }

  private async review(input: ReviewInput, user: string, attempt: Attempt): Promise<ReviewResult> {
    const context = macroContext(input.snapshot, input.today, input.testSettings);
    const feedback = input.feedback?.trim() || undefined;
    const generated = await this.generate(
      "review",
      MULTI_REVIEW_SYSTEM_PROMPT,
      buildReviewUserMessage({ snapshot: input.snapshot, context, plan: input.plan, actual: input.actual, reason: input.reason, pause: input.pause, feedback, performanceChanges: input.performanceChanges }),
      MacroReviewSchema,
      user,
      attempt,
      { macro: true }
    );
    const weeks = expandMacroBlocks(generated.data.blocks, context.weeks);
    const sanitized = sanitizeMacroV2({ rationale: generated.data.rationale, weeks }, input.snapshot, context);
    if (sanitized.blocked !== null) throw this.blocked("review", sanitized.blocked);
    const changes = generated.data.changes
      .map((change) => change.trim().slice(0, MULTI_RULES.maxChangeLength))
      .filter((change) => change !== "")
      .slice(0, MULTI_RULES.maxChanges);
    const summary = generated.data.summary.trim().slice(0, MULTI_RULES.maxSummaryLength);
    this.logGenerated("review", generated.meta, sanitized.adjustments.length, { weeks: sanitized.plan.weeks.length, changes: changes.length, reason: input.reason, actualWeeks: input.actual.length });
    return {
      goalDay: context.goalDay,
      generatedAt: this.now().toISOString(),
      plan: sanitized.plan,
      adjustments: sanitized.adjustments,
      summary,
      changes,
      reason: input.reason,
      ...(feedback !== undefined ? { feedback } : {})
    };
  }

  /** Der Plan fuer den Wettkampftag (Ablauf, Pacing, Wechsel, Verpflegung). */
  async planRace(input: RaceInput): Promise<RaceResult> {
    const user = input.user ?? OWNER_ID;
    return this.tracked("race", user, (attempt) => this.racePlan(input, user, attempt), () => ({ outcome: "claude" }));
  }

  private async racePlan(input: RaceInput, user: string, attempt: Attempt): Promise<RaceResult> {
    const raceDay = goalDayOf(input.snapshot);
    const days = daysBetween(input.today, raceDay);
    const weather =
      input.location !== undefined && days >= 0 && days < FORECAST_DAYS ? (await this.weatherFor(input.location, [raceDay]))[0] : undefined;
    const notes = input.notes?.trim() || undefined;
    const generated = await this.generate(
      "race",
      RACE_SYSTEM_PROMPT,
      buildRaceUserMessage({
        snapshot: input.snapshot,
        today: input.today,
        startTime: input.startTime,
        bodyWeightKg: input.bodyWeightKg,
        notes,
        weather,
        performance: performanceSection(input.snapshot)
      }),
      RacePlanSchema,
      user,
      attempt,
      { macro: true }
    );
    const sanitized = sanitizeRace(generated.data, input.snapshot, weather !== undefined ? { weather } : {});
    if (sanitized.blocked !== null) throw this.blocked("race", sanitized.blocked);
    this.logGenerated("race", generated.meta, sanitized.adjustments.length, { disciplines: sanitized.plan.disciplines.length, notesChars: notes?.length ?? 0 });
    return { raceDay, generatedAt: this.now().toISOString(), plan: sanitized.plan, adjustments: sanitized.adjustments, ...(weather !== undefined ? { weather } : {}) };
  }

  /** Ein Claude-Aufruf mit Budget und Schema-Pruefung; jeder Ausfall wird `PlanUnavailableError` mit Grund. */
  private async generate<S extends z.ZodType>(
    kind: string,
    system: string,
    message: string,
    schema: S,
    user: string,
    attempt: Attempt,
    options: CallOptions = {}
  ): Promise<{ data: z.infer<S>; meta: GeneratedPlan }> {
    const { generator, budget, userBudgets, logger } = this.deps;
    if (generator === null) throw new PlanUnavailableError("not_configured");
    const budgets = userBudgets === undefined ? [budget] : [budget, userBudgets.for(user)];
    if (!GenerationBudget.tryConsumeAll(budgets)) {
      logger.warn({ kind, user }, "plan v2 budget exceeded");
      throw new PlanUnavailableError("budget_exceeded");
    }
    const started = Date.now();
    let meta: GeneratedPlan;
    try {
      meta = await generator.complete(system, message, schema, options);
    } catch (error) {
      attempt.latencyMs = Date.now() - started;
      const reason = error instanceof PlanGenerationError ? error.reason : "unknown";
      const level = reason === "auth" || reason === "bad_request" || reason === "unknown" ? "error" : "warn";
      logger[level]({ err: error, reason, kind, latencyMs: attempt.latencyMs }, "plan v2 generation failed");
      throw new PlanUnavailableError(reason);
    }
    attempt.latencyMs = Date.now() - started;
    attempt.meta = meta;
    const parsed = schema.safeParse(meta.raw);
    if (!parsed.success) {
      logger.warn({ kind, issues: parsed.error.issues.slice(0, 5) }, "claude plan v2 does not match schema");
      throw new PlanUnavailableError("schema_invalid");
    }
    return { data: parsed.data as z.infer<S>, meta };
  }

  /** Fuehrt eine Anfrage aus und nimmt sie mit Ergebnis in die Nutzung auf, auch wenn sie scheitert. */
  private async tracked<T>(
    kind: string,
    user: string,
    work: (attempt: Attempt) => Promise<T>,
    outcomeOf: (result: T) => { outcome: UsageOutcome; reason?: string }
  ): Promise<T> {
    const attempt: Attempt = {};
    try {
      const result = await work(attempt);
      this.recordUsage(kind, user, attempt, outcomeOf(result));
      return result;
    } catch (error) {
      if (error instanceof PlanUnavailableError) this.recordUsage(kind, user, attempt, { outcome: "failed", reason: error.reason });
      throw error;
    }
  }

  private recordUsage(kind: string, user: string, attempt: Attempt, result: { outcome: UsageOutcome; reason?: string }): void {
    this.deps.usage?.record({
      user,
      kind,
      outcome: result.outcome,
      ...(result.reason !== undefined ? { reason: result.reason } : {}),
      ...(attempt.meta !== undefined
        ? { model: attempt.meta.model, inputTokens: attempt.meta.usage.inputTokens, outputTokens: attempt.meta.usage.outputTokens }
        : {}),
      ...(attempt.latencyMs !== undefined ? { latencyMs: attempt.latencyMs } : {})
    });
  }

  /** Die Vorhersage fuer die Tage; ohne Anbieter oder bei einem Fehler keine (dann ohne Wetter planen). */
  private async weatherFor(location: GeoLocation, dates: readonly string[]): Promise<DayWeather[]> {
    if (this.deps.weather === undefined) return [];
    try {
      return await this.deps.weather.forecast(location, dates);
    } catch (error) {
      this.deps.logger.warn({ err: error }, "weather forecast unavailable");
      return [];
    }
  }

  private storeFor(user: string): DayPlanStoreV2 {
    const store = this.deps.store;
    return typeof store === "function" ? store(user) : store;
  }

  private blocked(kind: string, reason: string): PlanUnavailableError {
    this.deps.logger.warn({ kind, reason }, "claude plan v2 blocked by sanity layer");
    return new PlanUnavailableError("sanity_blocked", reason);
  }

  private logGenerated(kind: string, meta: GeneratedPlan, adjustments: number, extra: Record<string, number | string>): void {
    this.deps.logger.info(
      { kind, model: meta.model, inputTokens: meta.usage.inputTokens, outputTokens: meta.usage.outputTokens, adjustments, ...extra },
      "plan v2 generated"
    );
  }

  /** Der letzte gueltige Tagesplan, noch einmal gegen den heutigen Zustand geprueft. */
  private fallback(
    reason: FallbackReason,
    snapshot: SnapshotV2,
    today: string,
    stored: StoredDayV2 | null,
    options: Parameters<typeof sanitizeDayV2>[2]
  ): DayResultV2 {
    if (stored === null) {
      this.deps.logger.warn({ reason }, "no plan v2 available and no earlier plan to fall back to");
      throw new PlanUnavailableError(reason);
    }
    const checked = sanitizeDayV2(asRawDayPlan(stored.plan), snapshot, options);
    if (checked.blocked !== null) {
      this.deps.logger.warn({ reason, blocked: checked.blocked }, "stored plan v2 no longer usable");
      throw new PlanUnavailableError(reason);
    }
    this.deps.logger.warn({ reason, planDate: stored.date }, "serving last valid plan v2 as fallback");
    return {
      source: "fallback",
      date: stored.date,
      generatedAt: stored.generatedAt,
      stale: stored.date !== today,
      plan: checked.plan,
      adjustments: checked.adjustments,
      fallbackReason: reason
    };
  }

  private async latestOrNull(store: DayPlanStoreV2): Promise<StoredDayV2 | null> {
    try {
      return await store.latest();
    } catch (error) {
      this.deps.logger.error({ err: error }, "could not read stored plan v2");
      return null;
    }
  }

  private async saveQuietly(store: DayPlanStoreV2, record: StoredDayV2): Promise<void> {
    try {
      await store.save(record);
    } catch (error) {
      this.deps.logger.error({ err: error }, "could not store plan v2");
    }
  }
}

function macroContext(snapshot: SnapshotV2, today: string, testSettings?: TestSettings): MacroContextV2 {
  const goalDay = goalDayOf(snapshot);
  return { today, goalDay, weeks: macroWeekStarts(today, goalDay), ...(testSettings !== undefined ? { testSettings } : {}) };
}

/** Fingerabdruck des Tages ohne Erzeugungszeitpunkt: Zustand, Wunsch, Vorgabe, Equipment (sortiert), Verlauf, Tests. */
export function dayHash(input: DayInputV2, wishes?: string): string {
  const { generated_at: _ignored, ...snapshot } = input.snapshot;
  const material = {
    plan_version: 2,
    snapshot,
    ...(wishes ? { wishes } : {}),
    ...(input.dayTarget ? { day_target: input.dayTarget } : {}),
    ...(input.equipment ? { equipment: [...new Set(input.equipment)].sort() } : {}),
    ...(input.recent && input.recent.length > 0 ? { recent: input.recent } : {}),
    ...(input.testSettings ? { test_settings: input.testSettings } : {}),
    ...(input.supplements ? { supplements: input.supplements } : {}),
    ...(input.availableMinutes !== undefined ? { available_minutes: input.availableMinutes } : {}),
    ...(input.location ? { location: roundLocation(input.location) } : {})
  };
  return createHash("sha256").update(JSON.stringify(material)).digest("hex");
}
