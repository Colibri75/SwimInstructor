import { Logger } from "pino";
import { GenerationBudget } from "./budget";
import { FallbackReason, PlanGenerationError, PlanUnavailableError } from "./errors";
import { MacroGenerator } from "./generator";
import { macroWeekStarts, MacroPlanSchema, MacroWeek } from "./macro";
import { MacroContext, sanitizeMacro } from "./macroSanity";
import { Snapshot } from "./snapshot";

export interface MacroRequest {
  snapshot: Snapshot;
  /** Heute beim Athleten. */
  today: string;
}

export interface MacroResult {
  /** Der Zieltag, auf den geplant wurde (`yyyy-MM-dd`). */
  goalDay: string;
  generatedAt: string;
  plan: { rationale: string; weeks: MacroWeek[] };
  /** Korrekturen der Sicherheitsschicht, auf Deutsch. */
  adjustments: string[];
}

export interface MacroServiceDeps {
  /** `null`, wenn kein ANTHROPIC_API_KEY konfiguriert ist. */
  generator: MacroGenerator | null;
  budget: GenerationBudget;
  logger: Logger;
  now?: () => Date;
}

/**
 * Erzeugt den Gesamtplan bis zum Zieltag. Wie beim Wochenplan speichert der Server ihn nicht: Die App
 * haelt ihn. Scheitert Claude, gibt es keinen Ersatz, sondern `PlanUnavailableError`; die App behaelt
 * ihren bisherigen Gesamtplan und versucht es spaeter erneut.
 */
export class MacroPlanService {
  private readonly now: () => Date;

  constructor(private readonly deps: MacroServiceDeps) {
    this.now = deps.now ?? (() => new Date());
  }

  async planMacro(request: MacroRequest): Promise<MacroResult> {
    const { generator, budget, logger } = this.deps;
    const goalDay = request.snapshot.goal.target_date.slice(0, 10);
    const context: MacroContext = { today: request.today, goalDay, weeks: macroWeekStarts(request.today, goalDay) };

    if (generator === null) throw this.unavailable("not_configured");
    if (!budget.tryConsume()) throw this.unavailable("budget_exceeded");

    const started = Date.now();
    try {
      const generated = await generator.generateMacro({ snapshot: request.snapshot, context });
      const parsed = MacroPlanSchema.safeParse(generated.raw);
      if (!parsed.success) {
        logger.warn({ issues: parsed.error.issues.slice(0, 5) }, "claude macro plan does not match schema");
        throw this.unavailable("schema_invalid");
      }

      const sanitized = sanitizeMacro(parsed.data, request.snapshot, context);
      if (sanitized.blocked !== null) {
        logger.warn({ reason: sanitized.blocked }, "claude macro plan blocked by sanity layer");
        throw this.unavailable("sanity_blocked");
      }

      logger.info(
        {
          model: generated.model,
          inputTokens: generated.usage.inputTokens,
          outputTokens: generated.usage.outputTokens,
          latencyMs: Date.now() - started,
          weeks: sanitized.plan.weeks.length,
          adjustments: sanitized.adjustments.length
        },
        "macro plan generated"
      );
      return { goalDay, generatedAt: this.now().toISOString(), plan: sanitized.plan, adjustments: sanitized.adjustments };
    } catch (error) {
      if (error instanceof PlanUnavailableError) throw error;
      const reason = error instanceof PlanGenerationError ? error.reason : "unknown";
      const level = reason === "auth" || reason === "bad_request" || reason === "unknown" ? "error" : "warn";
      logger[level]({ err: error, reason, latencyMs: Date.now() - started }, "macro plan generation failed");
      throw this.unavailable(reason);
    }
  }

  private unavailable(reason: FallbackReason): PlanUnavailableError {
    return new PlanUnavailableError(reason);
  }
}
