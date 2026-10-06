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

/** Die Anfrage passt nicht (etwa ein Tag ausserhalb der Vorschau); die Route antwortet mit 400. */
export class PlanRequestError extends Error {
  constructor(
    readonly path: string,
    message: string
  ) {
    super(message);
    this.name = "PlanRequestError";
  }
}

/** Claude scheiterte und es gibt keinen frueheren Plan, den man ausliefern koennte. */
export class PlanUnavailableError extends Error {
  /** `detail`: was genau scheiterte (etwa warum die Sicherheitsschicht blockierte), nur fuer Log und Bewertung, nie fuer die App. */
  constructor(
    readonly reason: FallbackReason,
    readonly detail?: string
  ) {
    super(`Kein Plan verfügbar (${reason}${detail === undefined ? "" : `: ${detail}`})`);
    this.name = "PlanUnavailableError";
  }
}
