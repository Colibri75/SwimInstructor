import { createHash } from "node:crypto";
import { Logger } from "pino";
import { FallbackReason, PlanGenerationError, PlanUnavailableError } from "./errors";
import { GenerationBudget } from "./budget";
import { PlanGenerator } from "./generator";
import { TrainingPlan, TrainingPlanSchema } from "./plan";
import { sanitizePlan } from "./sanity";
import { Snapshot } from "./snapshot";
import { PlanStore, StoredPlan } from "./store";

export interface PlanResult {
  /** claude: frisch erzeugt. cache: schon heute fuer denselben Zustand erzeugt. fallback: letzter gueltiger Plan. */
  source: "claude" | "cache" | "fallback";
  /** Kalendertag, fuer den der Plan erstellt wurde. */
  date: string;
  generatedAt: string;
  /** Der Plan stammt nicht von heute (nur bei fallback). */
  stale: boolean;
  plan: TrainingPlan;
  /** Korrekturen der Sicherheitsschicht, auf Deutsch. */
  adjustments: string[];
  fallbackReason?: FallbackReason;
}

export interface PlanServiceDeps {
  /** `null`, wenn kein ANTHROPIC_API_KEY konfiguriert ist: dann gibt es nur Cache und Fallback. */
  generator: PlanGenerator | null;
  store: PlanStore;
  budget: GenerationBudget;
  logger: Logger;
  timezone: string;
  now?: () => Date;
}

export class PlanService {
  private readonly now: () => Date;

  constructor(private readonly deps: PlanServiceDeps) {
    this.now = deps.now ?? (() => new Date());
  }

  async planForToday(snapshot: Snapshot): Promise<PlanResult> {
    const { generator, store, budget, logger } = this.deps;
    const today = localDate(this.now(), this.deps.timezone);
    const hash = snapshotHash(snapshot);

    // Derselbe Zustand am selben Tag: den schon erzeugten Plan wiederverwenden, das spart Claude-Kosten.
    const stored = await this.latestOrNull();
    if (stored && stored.date === today && stored.snapshotHash === hash) {
      logger.info({ date: today }, "plan served from cache");
      return { source: "cache", date: stored.date, generatedAt: stored.generatedAt, stale: false, plan: stored.plan, adjustments: stored.adjustments };
    }

    if (generator === null) return this.fallback("not_configured", snapshot, today, stored);
    if (!budget.tryConsume()) return this.fallback("budget_exceeded", snapshot, today, stored);

    const started = Date.now();
    try {
      const generated = await generator.generate({ snapshot, date: today });
      const parsed = TrainingPlanSchema.safeParse(generated.raw);
      if (!parsed.success) {
        logger.warn({ issues: parsed.error.issues.slice(0, 5) }, "claude plan does not match schema");
        return this.fallback("schema_invalid", snapshot, today, stored);
      }

      const sanitized = sanitizePlan(parsed.data, snapshot);
      if (sanitized.blocked !== null) {
        logger.warn({ reason: sanitized.blocked }, "claude plan blocked by sanity layer");
        return this.fallback("sanity_blocked", snapshot, today, stored);
      }

      const record: StoredPlan = {
        date: today,
        snapshotHash: hash,
        generatedAt: this.now().toISOString(),
        model: generated.model,
        plan: sanitized.plan,
        adjustments: sanitized.adjustments
      };
      await this.saveQuietly(record);

      logger.info(
        {
          model: generated.model,
          inputTokens: generated.usage.inputTokens,
          outputTokens: generated.usage.outputTokens,
          latencyMs: Date.now() - started,
          adjustments: sanitized.adjustments.length
        },
        "plan generated"
      );
      return { source: "claude", date: today, generatedAt: record.generatedAt, stale: false, plan: record.plan, adjustments: record.adjustments };
    } catch (error) {
      const reason = error instanceof PlanGenerationError ? error.reason : "unknown";
      // auth und bad_request sind Konfigurations- oder Programmierfehler und gehoeren laut ins Log.
      const level = reason === "auth" || reason === "bad_request" || reason === "unknown" ? "error" : "warn";
      logger[level]({ err: error, reason, latencyMs: Date.now() - started }, "plan generation failed");
      return this.fallback(reason, snapshot, today, stored);
    }
  }

  /**
   * Liefert den letzten gueltigen Plan statt eines frischen. Er laeuft vorher noch einmal durch die
   * Sicherheitsschicht, und zwar gegen den heutigen Zustand: Ein Plan von gestern darf heute nicht
   * deshalb ausgeliefert werden, weil er damals harmlos war (z. B. harte Einheit bei schlechter Erholung).
   */
  private fallback(reason: FallbackReason, snapshot: Snapshot, today: string, stored: StoredPlan | null): PlanResult {
    if (stored === null) {
      this.deps.logger.warn({ reason }, "no plan available and no earlier plan to fall back to");
      throw new PlanUnavailableError(reason);
    }
    const checked = sanitizePlan(stored.plan, snapshot);
    if (checked.blocked !== null) {
      this.deps.logger.warn({ reason, blocked: checked.blocked }, "stored plan no longer usable");
      throw new PlanUnavailableError(reason);
    }
    this.deps.logger.warn({ reason, planDate: stored.date }, "serving last valid plan as fallback");
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

  private async latestOrNull(): Promise<StoredPlan | null> {
    try {
      return await this.deps.store.latest();
    } catch (error) {
      this.deps.logger.error({ err: error }, "could not read stored plan");
      return null;
    }
  }

  private async saveQuietly(record: StoredPlan): Promise<void> {
    try {
      await this.deps.store.save(record);
    } catch (error) {
      // Der Plan ist gueltig und soll die App auch erreichen, wenn das Speichern scheitert.
      this.deps.logger.error({ err: error }, "could not store plan");
    }
  }
}

/** Kalendertag YYYY-MM-DD in der gegebenen Zeitzone. */
export function localDate(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}

/** Fingerabdruck des Zustands ohne den Erzeugungszeitpunkt, der sich bei jedem Aufruf aendert. */
export function snapshotHash(snapshot: Snapshot): string {
  const { generated_at: _ignored, ...rest } = snapshot;
  return createHash("sha256").update(JSON.stringify(rest)).digest("hex");
}
