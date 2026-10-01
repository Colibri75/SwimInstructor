import { Logger } from "pino";
import { GenerationBudget } from "./budget";
import { FallbackReason, PlanGenerationError, PlanUnavailableError } from "./errors";
import { WeekGenerator } from "./generator";
import { Equipment } from "./plan";
import { Snapshot } from "./snapshot";
import { WeekDay, WeekPlanSchema, weekDates } from "./week";
import { sanitizeWeek, WeekContext } from "./weekSanity";

export interface WeekRequest {
  snapshot: Snapshot;
  /** Montag der Woche. */
  weekStart: string;
  /** Erster zu planender Tag (heute oder der Montag einer kommenden Woche). */
  fromDate: string;
  today: string;
  unavailableDates: string[];
  swumThisWeek: { date: string; meters: number }[];
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
    const dates = weekDates(request.weekStart).filter((date) => date >= request.fromDate);
    const wishes = request.wishes?.trim() || undefined;
    const context: WeekContext = {
      today: request.today,
      dates,
      unavailable: request.unavailableDates,
      swumBefore: request.swumThisWeek.filter((day) => day.date < request.fromDate && day.date >= request.weekStart)
    };

    if (generator === null) throw this.unavailable("not_configured");
    if (!budget.tryConsume()) throw this.unavailable("budget_exceeded");

    const started = Date.now();
    try {
      const generated = await generator.generateWeek({ snapshot: request.snapshot, context, ...(wishes ? { wishes } : {}), ...(request.equipment ? { equipment: request.equipment } : {}) });
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
        weekStart: request.weekStart,
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
