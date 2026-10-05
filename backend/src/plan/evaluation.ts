/**
 * Gemeinsame Form der automatischen Pruefungen fuer die Bewertung (`npm run eval:multisport`): Sie zeigen, wo man
 * hinschauen sollte, und ersetzen nicht das Urteil, ob ein Plan sinnvoll ist. Die Pruefungen selbst stehen in
 * `multi/evaluation.ts`.
 */
export interface EvalCheck {
  name: string;
  ok: boolean;
  detail: string;
}

/** Eine Zeile je Pruefung fuer den Bericht. */
export function formatChecks(checks: EvalCheck[]): string {
  if (checks.length === 0) return "Keine automatischen Prüfungen für dieses Szenario.";
  return checks.map((check) => `- [${check.ok ? "x" : " "}] ${check.name}: ${check.detail}`).join("\n");
}
