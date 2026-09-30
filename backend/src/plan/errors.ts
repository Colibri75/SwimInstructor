/** Warum die Plan-Erzeugung bei Claude scheiterte (siehe ClaudePlanGenerator). */
export type GenerationFailure =
  | "refusal"
  | "truncated"
  | "empty_response"
  | "invalid_json"
  | "timeout"
  | "unreachable"
  | "rate_limited"
  | "upstream_error"
  | "auth"
  | "bad_request"
  | "unknown";

/** Warum der Service statt eines frischen Plans den letzten gueltigen auslieferte. */
export type FallbackReason = GenerationFailure | "not_configured" | "budget_exceeded" | "schema_invalid" | "sanity_blocked";

export class PlanGenerationError extends Error {
  constructor(
    readonly reason: GenerationFailure,
    message: string,
    options?: { cause?: unknown }
  ) {
    super(message, options);
    this.name = "PlanGenerationError";
  }
}

/** Claude scheiterte und es gibt keinen frueheren Plan, den man ausliefern koennte. */
export class PlanUnavailableError extends Error {
  constructor(readonly reason: FallbackReason) {
    super(`Kein Plan verfügbar (${reason})`);
    this.name = "PlanUnavailableError";
  }
}
