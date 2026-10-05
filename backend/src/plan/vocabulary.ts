/**
 * Wortschatz der Plaene: Einheitentypen, Intensitaeten und Hilfsmittel. Die Schemas der Antworten stehen in
 * `multi/schemas.ts`, die Grenzen pruefen die Sicherheitsschichten in `multi/`.
 */
export const SESSION_TYPES = ["rest", "recovery", "technique", "endurance", "threshold", "intervals", "test"] as const;
export const INTENSITIES = ["rest", "easy", "moderate", "hard"] as const;
/** Hilfsmittel, die ein Schritt verlangen kann. Die App uebersetzt die Werte in deutsche Namen. */
export const EQUIPMENT = ["pull_buoy", "paddles", "fins", "snorkel", "kickboard", "ankle_band"] as const;

export type Equipment = (typeof EQUIPMENT)[number];
export type Intensity = (typeof INTENSITIES)[number];
export type SessionType = (typeof SESSION_TYPES)[number];

/** Deutsche Namen, fuer Hinweise der Sicherheitsschicht und die Nutzernachricht. */
export const EQUIPMENT_LABELS: Record<Equipment, string> = {
  pull_buoy: "Pull Buoy",
  paddles: "Paddles",
  fins: "Flossen",
  snorkel: "Schnorchel",
  kickboard: "Kickboard",
  ankle_band: "Beinband"
};
