import { SessionType } from "./vocabulary";

/** Preise in US-Dollar pro Million Token (Stand 25.09.2026, Anthropic-Preisliste). */
export const PRICES_PER_MILLION_TOKENS: Record<string, { input: number; output: number }> = {
  "claude-opus-5-5": { input: 4, output: 20 },
  "claude-opus-5": { input: 5, output: 25 },
  "claude-sonnet-5-5": { input: 2, output: 10 },
  "claude-sonnet-5": { input: 2, output: 10 },
  "claude-haiku-4-5": { input: 1, output: 5 }
};

/** Geschaetzte Kosten eines Aufrufs in US-Dollar, `null` bei unbekanntem Modell. Ohne Cache-Rabatt. */
export function estimateCostUsd(model: string, usage: { inputTokens: number; outputTokens: number }): number | null {
  const price = PRICES_PER_MILLION_TOKENS[model];
  if (price === undefined) return null;
  return (usage.inputTokens * price.input + usage.outputTokens * price.output) / 1_000_000;
}

/** Deutsche Namen der Einheitentypen, wie die App sie zeigt (`PlanFormatting.sessionType`). */
export const SESSION_TYPE_LABEL: Record<SessionType, string> = {
  technique: "Technik",
  endurance: "Ausdauer",
  threshold: "Schwelle",
  intervals: "Intervalle",
  recovery: "Regeneration",
  test: "Test",
  rest: "Ruhetag"
};
