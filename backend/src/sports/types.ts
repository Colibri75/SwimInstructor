import { StepMeasure, StepTarget } from "./vocabulary";

/**
 * Alles, was eine Sportart dem Backend beibringt. Der Kern (Schemas, Prompts, Sicherheitsschicht) fragt nie
 * "welche Sportart ist das?", sondern immer die Definition: Eine neue Sportart ist eine neue Definition unter
 * modules/ plus Tests. Die Definitionen wachsen mit dem Umbau (Prompt-Regeln, Sicherheitsregeln, Lastfaktor);
 * hier stehen zunaechst die Angaben, die App und Server teilen.
 */
export interface SportDefinition {
  /** Kennung, z. B. "swim": Kleinbuchstaben, Ziffern, Unterstrich, beginnt mit einem Buchstaben, 2 bis 32 Zeichen. */
  readonly id: string;
  /** Deutscher Name, z. B. "Schwimmen". */
  readonly displayName: string;
  readonly measures: readonly StepMeasure[];
  readonly targets: readonly StepTarget[];
}
