import { createHash } from "node:crypto";
import { Logger } from "pino";
import { z } from "zod";
import { GenerationBudget } from "../budget";
import { FallbackReason, PlanGenerationError, PlanUnavailableError } from "../errors";
import { GeneratedPlan, StructuredGenerator } from "../generator";
import { macroWeekStarts } from "../macro";
import { localDate } from "../service";
import { SnapshotV2 } from "../snapshot";
import { windowDates } from "../week";
import { DayPlanV2, sanitizeDayV2 } from "./daySanity";
import { goalDayOf, MULTI_RULES } from "./limits";
import { expandMacroBlocks, MacroContextV2, MacroPlanV2, sanitizeMacroV2 } from "./macroSanity";
import {
  buildDayUserMessageV2,
  buildMacroUserMessageV2,
  buildReviseUserMessage,
  buildWeekUserMessageV2,
  MULTI_DAY_SYSTEM_PROMPT,
  MULTI_MACRO_SYSTEM_PROMPT,
  MULTI_REVISE_SYSTEM_PROMPT,
  MULTI_WEEK_SYSTEM_PROMPT
} from "./prompts";
import {
  DayTargetV2,
  FeedbackRound,
  MacroRevisionSchema,
  MacroWeekTargetV2,
  MultiDayPlanSchema,
  MultiMacroPlanSchema,
  MultiWeekPlanSchema,
  RecentTraining,
  TestSettings
} from "./schemas";
import { asRawDayPlan, DayPlanStoreV2, StoredDayV2 } from "./store";
import { sanitizeWeekV2, WeekContextV2, WeekPlanV2 } from "./weekSanity";

/**
 * Plan v2 fuer mehrere Sportarten: Tag, sieben Tage, Gesamtplan und Feedback zum Gesamtplan. Ablauf wie bei v1:
 * Claude fragen (mit Budget), das Ergebnis gegen das Schema und durch die Sicherheitsschicht. Nur der Tagesplan hat
 * Cache und Fallback auf den letzten gueltigen Plan; Woche und Gesamtplan haelt die App, sie behaelt bei einem Ausfall
 * ihren bisherigen.
 */
export interface MultiServiceDeps {
  /** `null`, wenn kein ANTHROPIC_API_KEY konfiguriert ist. */
  generator: StructuredGenerator | null;
  store: DayPlanStoreV2;
  budget: GenerationBudget;
  logger: Logger;
  timezone: string;
  now?: () => Date;
}

export interface DayInputV2 {
  snapshot: SnapshotV2;
  regenerate?: boolean;
  wishes?: string;
  dayTarget?: DayTargetV2;
  equipment?: readonly string[];
  recent?: readonly RecentTraining[];
  testSettings?: TestSettings;
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
  snapshot: SnapshotV2;
  fromDate: string;
  today: string;
  unavailable: string[];
  recent: RecentTraining[];
  macroWeeks?: MacroWeekTargetV2[];
  wishes?: string;
  equipment?: readonly string[];
  testSettings?: TestSettings;
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

export class MultiPlanService {
  private readonly now: () => Date;

  constructor(private readonly deps: MultiServiceDeps) {
    this.now = deps.now ?? (() => new Date());
  }

  async planDay(input: DayInputV2): Promise<DayResultV2> {
    const { store, logger } = this.deps;
    const today = localDate(this.now(), this.deps.timezone);
    const wishes = input.wishes?.trim() || undefined;
    const hash = dayHash(input, wishes);
    const options = { date: today, equipment: input.equipment, recent: input.recent ?? [], testSettings: input.testSettings };

    const stored = await this.latestOrNull();
    if (input.regenerate !== true && stored !== null && stored.date === today && stored.hash === hash) {
      logger.info({ date: today }, "plan v2 served from cache");
      return { source: "cache", date: today, generatedAt: stored.generatedAt, stale: false, plan: stored.plan, adjustments: stored.adjustments, ...(wishes ? { wishes } : {}) };
    }

    let generated: { data: z.infer<typeof MultiDayPlanSchema>; meta: GeneratedPlan };
    try {
      generated = await this.generate(
        "day",
        MULTI_DAY_SYSTEM_PROMPT,
        buildDayUserMessageV2({ snapshot: input.snapshot, date: today, wishes, dayTarget: input.dayTarget, equipment: input.equipment, recent: input.recent, testSettings: input.testSettings }),
        MultiDayPlanSchema
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
    await this.saveQuietly(record);
    this.logGenerated("day", generated.meta, sanitized.adjustments.length, { sessions: sanitized.plan.sessions.length, wishChars: wishes?.length ?? 0 });
    return { source: "claude", date: today, generatedAt: record.generatedAt, stale: false, plan: record.plan, adjustments: record.adjustments, ...(wishes ? { wishes } : {}) };
  }

  async planWeek(input: WeekInputV2): Promise<WeekResultV2> {
    const wishes = input.wishes?.trim() || undefined;
    const context: WeekContextV2 = {
      today: input.today,
      dates: windowDates(input.fromDate, 7),
      unavailable: input.unavailable,
      recent: input.recent.filter((entry) => entry.date < input.fromDate),
      ...(input.macroWeeks !== undefined && input.macroWeeks.length > 0 ? { macroWeeks: input.macroWeeks } : {}),
      ...(input.testSettings !== undefined ? { testSettings: input.testSettings } : {})
    };
    const generated = await this.generate(
      "week",
      MULTI_WEEK_SYSTEM_PROMPT,
      buildWeekUserMessageV2({ snapshot: input.snapshot, context, wishes, equipment: input.equipment }),
      MultiWeekPlanSchema
    );
    const sanitized = sanitizeWeekV2(generated.data, input.snapshot, context);
    if (sanitized.blocked !== null) throw this.blocked("week", sanitized.blocked);
    this.logGenerated("week", generated.meta, sanitized.adjustments.length, { wishChars: wishes?.length ?? 0 });
    return { fromDate: input.fromDate, generatedAt: this.now().toISOString(), plan: sanitized.plan, adjustments: sanitized.adjustments, ...(wishes ? { wishes } : {}) };
  }

  async planMacro(input: { snapshot: SnapshotV2; today: string; testSettings?: TestSettings }): Promise<MacroResultV2> {
    const context = macroContext(input.snapshot, input.today, input.testSettings);
    const generated = await this.generate("macro", MULTI_MACRO_SYSTEM_PROMPT, buildMacroUserMessageV2(input.snapshot, context), MultiMacroPlanSchema);
    const weeks = expandMacroBlocks(generated.data.blocks, context.weeks);
    const sanitized = sanitizeMacroV2({ rationale: generated.data.rationale, weeks }, input.snapshot, context);
    if (sanitized.blocked !== null) throw this.blocked("macro", sanitized.blocked);
    this.logGenerated("macro", generated.meta, sanitized.adjustments.length, { blocks: generated.data.blocks.length, weeks: sanitized.plan.weeks.length });
    return { goalDay: context.goalDay, generatedAt: this.now().toISOString(), plan: sanitized.plan, adjustments: sanitized.adjustments };
  }

  async reviseMacro(input: ReviseInput): Promise<ReviseResult> {
    const context = macroContext(input.snapshot, input.today, input.testSettings);
    const feedback = input.feedback.trim();
    const generated = await this.generate(
      "revise",
      MULTI_REVISE_SYSTEM_PROMPT,
      buildReviseUserMessage({ snapshot: input.snapshot, context, plan: input.plan, feedback, history: input.history }),
      MacroRevisionSchema
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

  /** Ein Claude-Aufruf mit Budget und Schema-Pruefung; jeder Ausfall wird `PlanUnavailableError` mit Grund. */
  private async generate<S extends z.ZodType>(kind: string, system: string, user: string, schema: S): Promise<{ data: z.infer<S>; meta: GeneratedPlan }> {
    const { generator, budget, logger } = this.deps;
    if (generator === null) throw new PlanUnavailableError("not_configured");
    if (!budget.tryConsume()) throw new PlanUnavailableError("budget_exceeded");
    const started = Date.now();
    let meta: GeneratedPlan;
    try {
      meta = await generator.complete(system, user, schema);
    } catch (error) {
      const reason = error instanceof PlanGenerationError ? error.reason : "unknown";
      const level = reason === "auth" || reason === "bad_request" || reason === "unknown" ? "error" : "warn";
      logger[level]({ err: error, reason, kind, latencyMs: Date.now() - started }, "plan v2 generation failed");
      throw new PlanUnavailableError(reason);
    }
    const parsed = schema.safeParse(meta.raw);
    if (!parsed.success) {
      logger.warn({ kind, issues: parsed.error.issues.slice(0, 5) }, "claude plan v2 does not match schema");
      throw new PlanUnavailableError("schema_invalid");
    }
    return { data: parsed.data as z.infer<S>, meta };
  }

  private blocked(kind: string, reason: string): PlanUnavailableError {
    this.deps.logger.warn({ kind, reason }, "claude plan v2 blocked by sanity layer");
    return new PlanUnavailableError("sanity_blocked");
  }

  private logGenerated(kind: string, meta: GeneratedPlan, adjustments: number, extra: Record<string, number>): void {
    this.deps.logger.info(
      { kind, model: meta.model, inputTokens: meta.usage.inputTokens, outputTokens: meta.usage.outputTokens, adjustments, ...extra },
      "plan v2 generated"
    );
  }

  /** Wie bei v1: der letzte gueltige Tagesplan, noch einmal gegen den heutigen Zustand geprueft. */
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

  private async latestOrNull(): Promise<StoredDayV2 | null> {
    try {
      return await this.deps.store.latest();
    } catch (error) {
      this.deps.logger.error({ err: error }, "could not read stored plan v2");
      return null;
    }
  }

  private async saveQuietly(record: StoredDayV2): Promise<void> {
    try {
      await this.deps.store.save(record);
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
    ...(input.testSettings ? { test_settings: input.testSettings } : {})
  };
  return createHash("sha256").update(JSON.stringify(material)).digest("hex");
}
