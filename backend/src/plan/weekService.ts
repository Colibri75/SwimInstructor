import { Logger } from "pino";
import { GenerationBudget } from "./budget";
import { FallbackReason, PlanGenerationError, PlanUnavailableError } from "./errors";
import { WeekGenerator } from "./generator";
import { Equipment } from "./plan";
import { Snapshot } from "./snapshot";
import { MacroWeekTarget } from "./macro";
import { WeekDay, WeekPlanSchema, weekDates, windowDates } from "./week";
import { sanitizeWeek, WeekContext } from "./weekSanity";

export interface WeekRequest {
  snapshot: Snapshot;
  /** Montag der Kalenderwoche. Fehlt er, gilt der rollende Plan: die sieben Tage ab `fromDate`. */
  weekStart?: string;
  /** Erster zu planender Tag (heute oder der Montag einer kommenden Woche). */
  fromDate: string;
  today: string;
  unavailableDates: string[];
  swumThisWeek: { date: string; meters: number }[];
  /** Die Vorwoche (7 Tage vor `fromDate`), nur Information fuer Claude. */
  recentSwim?: { date: string; meters: number }[];
  /** Was der Gesamtplan fuer die Wochen der geplanten Tage vorgibt. */
  macroWeeks?: readonly MacroWeekTarget[];
  wishes?: string;
  equipment?: readonly Equipment[];
}

export interface WeekResult {
  weekStart: string;
  generatedAt: string;
  plan: { rationale: string; total_distance_meters: number; days: WeekDay[] };
  /** Korrekturen der Sicherheitsschicht, auf Deutsch. */
  adjustments: string[];
  wishes?: string;
}

export interface WeekServiceDeps {
  /** `null`, wenn kein ANTHROPIC_API_KEY konfiguriert ist. */
  generator: WeekGenerator | null;
  budget: GenerationBudget;
  logger: Logger;
  now?: () => Date;
}

/**
 * Erzeugt einen Wochenplan. Anders als der Tagesplan speichert der Server ihn nicht: Die App haelt ihn
 * (und die Aenderungen des Athleten daran) selbst. Scheitert Claude, gibt es keinen Ersatzplan, sondern
 * `PlanUnavailableError`; die App behaelt ihren bisherigen Wochenplan und kann es erneut versuchen.
 */
export class WeekPlanService {
  private readonly now: () => Date;

  constructor(private readonly deps: WeekServiceDeps) {
    this.now = deps.now ?? (() => new Date());
  }

  async planWeek(request: WeekRequest): Promise<WeekResult> {
    const { generator, budget, logger } = this.deps;
    const rolling = request.weekStart === undefined;
    const dates = rolling ? windowDates(request.fromDate, 7) : weekDates(request.weekStart as string).filter((date) => date >= request.fromDate);
    const wishes = request.wishes?.trim() || undefined;
    const context: WeekContext = {
      today: request.today,
      dates,
      unavailable: request.unavailableDates,
      // Der rollende Plan hat keine Kalenderwoche: Die Vorwoche steht nur im Prompt, sie schmaelert
      // das Budget der naechsten sieben Tage nicht.
      swumBefore: rolling ? [] : request.swumThisWeek.filter((day) => day.date < request.fromDate && day.date >= (request.weekStart as string)),
      ...(request.recentSwim === undefined ? {} : { recentSwim: request.recentSwim.filter((day) => day.date < request.fromDate) })
    };

    if (generator === null) throw this.unavailable("not_configured");
    if (!budget.tryConsume()) throw this.unavailable("budget_exceeded");

    const started = Date.now();
    try {
      const generated = await generator.generateWeek({
        snapshot: request.snapshot,
        context,
        ...(wishes ? { wishes } : {}),
        ...(request.equipment ? { equipment: request.equipment } : {}),
        ...(request.macroWeeks && request.macroWeeks.length > 0 ? { macroWeeks: request.macroWeeks } : {})
      });
      const parsed = WeekPlanSchema.safeParse(generated.raw);
      if (!parsed.success) {
        logger.warn({ issues: parsed.error.issues.slice(0, 5) }, "claude week plan does not match schema");
        throw this.unavailable("schema_invalid");
      }

      const sanitized = sanitizeWeek(parsed.data, request.snapshot, context);
      if (sanitized.blocked !== null) {
        logger.warn({ reason: sanitized.blocked }, "claude week plan blocked by sanity layer");
        throw this.unavailable("sanity_blocked");
      }

      logger.info(
        {
          model: generated.model,
          inputTokens: generated.usage.inputTokens,
          outputTokens: generated.usage.outputTokens,
          latencyMs: Date.now() - started,
          days: sanitized.plan.days.length,
          adjustments: sanitized.adjustments.length,
          wishChars: wishes?.length ?? 0
        },
        "week plan generated"
      );
      return {
        weekStart: request.weekStart ?? request.fromDate,
        generatedAt: this.now().toISOString(),
        plan: {
          rationale: sanitized.plan.rationale,
          total_distance_meters: sanitized.plan.days.reduce((sum, day) => sum + day.target_distance_meters, 0),
          days: sanitized.plan.days
        },
        adjustments: sanitized.adjustments,
        ...(wishes ? { wishes } : {})
      };
    } catch (error) {
      if (error instanceof PlanUnavailableError) throw error;
      const reason = error instanceof PlanGenerationError ? error.reason : "unknown";
      const level = reason === "auth" || reason === "bad_request" || reason === "unknown" ? "error" : "warn";
      logger[level]({ err: error, reason, latencyMs: Date.now() - started }, "week plan generation failed");
      throw this.unavailable(reason);
    }
  }

  private unavailable(reason: FallbackReason): PlanUnavailableError {
    return new PlanUnavailableError(reason);
  }
}
