import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { PlanGenerationError } from "./errors";
import { TrainingPlanSchema } from "./plan";
import { buildUserMessage, SYSTEM_PROMPT } from "./prompt";
import { Snapshot } from "./snapshot";

export interface GeneratedPlan {
  /** Das geparste, aber noch nicht gegen das Plan-Schema geprueftes JSON von Claude. */
  raw: unknown;
  /** Modell, das die Antwort tatsaechlich lieferte (bei Server-Fallback ein anderes als angefragt). */
  model: string;
  usage: { inputTokens: number; outputTokens: number };
}

/** Naht fuer Tests: Der Service kennt nur dieses Interface, nie das Anthropic-SDK. */
export interface PlanGenerator {
  generate(input: { snapshot: Snapshot; date: string }): Promise<GeneratedPlan>;
}

export interface ClaudeOptions {
  model: string;
  timeoutMs: number;
  effort: "low" | "medium" | "high" | "xhigh" | "max";
  /** Server-seitiger Fallback, wenn Claudes Sicherheitsklassifikatoren eine Anfrage ablehnen. */
  serverFallback: boolean;
}

const MAX_TOKENS = 16_000;

export class ClaudePlanGenerator implements PlanGenerator {
  constructor(
    private readonly client: Anthropic,
    private readonly options: ClaudeOptions
  ) {}

  async generate({ snapshot, date }: { snapshot: Snapshot; date: string }): Promise<GeneratedPlan> {
    let response;
    try {
      response = await this.client.beta.messages.create(
        {
          model: this.options.model,
          max_tokens: MAX_TOKENS,
          thinking: { type: "adaptive" },
          // Forcierte Tool-Aufrufe sind auf diesem Modell nicht erlaubt: Das JSON kommt daher ueber
          // strukturierte Ausgaben (output_config.format), nicht ueber ein erzwungenes Tool.
          output_config: { effort: this.options.effort, format: zodOutputFormat(TrainingPlanSchema) },
          ...(this.options.serverFallback ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const } : {}),
          system: SYSTEM_PROMPT,
          messages: [{ role: "user", content: buildUserMessage(snapshot, date) }]
        },
        // Keine SDK-Wiederholungen: Eine Wiederholung nach Timeout wuerde doppelt kosten und die
        // Gesamtzeit ueber das Zeitlimit des Reverse-Proxys (90 s) treiben. Der Service faellt stattdessen
        // auf den letzten gueltigen Plan zurueck, die App kann es erneut versuchen.
        { timeout: this.options.timeoutMs, maxRetries: 0 }
      );
    } catch (error) {
      throw classify(error);
    }

    if (response.stop_reason === "refusal") {
      throw new PlanGenerationError("refusal", `Claude hat abgelehnt (${response.stop_details?.category ?? "ohne Kategorie"})`);
    }
    if (response.stop_reason === "max_tokens") {
      throw new PlanGenerationError("truncated", "Antwort wurde wegen max_tokens abgeschnitten");
    }

    const text = response.content
      .flatMap((block) => (block.type === "text" ? [block.text] : []))
      .join("")
      .trim();
    if (text === "") throw new PlanGenerationError("empty_response", "Antwort enthält keinen Text");

    let raw: unknown;
    try {
      raw = JSON.parse(text);
    } catch (error) {
      throw new PlanGenerationError("invalid_json", "Antwort ist kein gültiges JSON", { cause: error });
    }

    return {
      raw,
      model: response.model,
      usage: { inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens }
    };
  }
}

/** Ordnet SDK-Fehler den Ausfallgruenden zu, vom Spezifischen zum Allgemeinen (Timeout ist eine Verbindungsstoerung). */
function classify(error: unknown): PlanGenerationError {
  const message = error instanceof Error ? error.message : String(error);
  if (error instanceof Anthropic.APIConnectionTimeoutError) return new PlanGenerationError("timeout", message, { cause: error });
  if (error instanceof Anthropic.APIConnectionError) return new PlanGenerationError("unreachable", message, { cause: error });
  if (error instanceof Anthropic.RateLimitError) return new PlanGenerationError("rate_limited", message, { cause: error });
  if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
    return new PlanGenerationError("auth", message, { cause: error });
  }
  if (error instanceof Anthropic.BadRequestError) return new PlanGenerationError("bad_request", message, { cause: error });
  if (error instanceof Anthropic.APIError && (error.status === undefined || error.status >= 500)) {
    return new PlanGenerationError("upstream_error", message, { cause: error });
  }
  return new PlanGenerationError("unknown", message, { cause: error });
}
