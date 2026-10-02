import { TrainingPlan } from "./plan";
import { DailyLimits } from "./sanity";
import { WeekPlan, weekdayName } from "./week";
import { WeekLimits } from "./weekSanity";

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

const INTENSITY_LABEL = { rest: "Ruhetag", easy: "locker", moderate: "moderat", hard: "hart" } as const;

function formatPace(seconds: number | null): string {
  return seconds === null ? "–" : `${seconds} s/100 m`;
}

/** Stellt einen Plan als Markdown dar, fuer den Szenario-Test und die manuelle Bewertung. */
export function formatPlan(plan: TrainingPlan): string {
  const lines = [
    `**${plan.session_type}**, ${INTENSITY_LABEL[plan.intensity]}, ${plan.total_distance_meters} m, ca. ${plan.estimated_duration_minutes} min`,
    "",
    plan.rationale
  ];

  if (plan.sets.length > 0) {
    lines.push("", "| Abschnitt | Umfang | Pace | Pause | Equipment | Uhr | Hinweis |", "|---|---|---|---|---|---|---|");
    for (const set of plan.sets) {
      const volume = `${set.repetitions} × ${set.distance_meters} m`;
      lines.push(`| ${set.name} | ${volume} | ${formatPace(set.target_pace_seconds_per_hundred_meters)} | ${set.rest_seconds} s | ${set.equipment.join(", ") || "–"} | ${set.cue || "–"} | ${set.instructions} |`);
    }
  }
  if (plan.coach_notes.length > 0) {
    lines.push("", ...plan.coach_notes.map((note) => `- ${note}`));
  }
  return lines.join("\n");
}

/** Die Grenzen fuer heute als eine Zeile, fuer die manuelle Bewertung der Szenarien. */
export function formatLimits(limits: DailyLimits): string {
  if (limits.restReason !== null) return `Pflicht-Ruhetag (${limits.restReason})`;
  const parts = [`höchstens ${limits.maxDistanceMeters} m`];
  if (limits.maxIntensity !== "hard") parts.push(`Intensität höchstens ${INTENSITY_LABEL[limits.maxIntensity]}`);
  parts.push(`Pace nicht schneller als ${limits.fastestPace} s/100 m`);
  return parts.join(", ");
}

/** Einen Wochenplan als Markdown, fuer die manuelle Bewertung. */
export function formatWeekPlan(week: WeekPlan): string {
  const total = week.days.reduce((sum, day) => sum + day.target_distance_meters, 0);
  const lines = [`**${total} m in ${week.days.filter((d) => d.intensity !== "rest").length} Einheiten**`, "", week.rationale, "", "| Tag | Typ | Intensität | Umfang | Dauer | Schwerpunkt |", "|---|---|---|---|---|---|"];
  for (const day of week.days) {
    lines.push(`| ${weekdayName(day.date)} ${day.date} | ${day.session_type} | ${INTENSITY_LABEL[day.intensity]} | ${day.target_distance_meters} m | ${day.estimated_duration_minutes} min | ${day.focus} |`);
  }
  return lines.join("\n");
}

/** Die Wochengrenzen als eine Zeile, fuer die manuelle Bewertung. */
export function formatWeekLimits(limits: WeekLimits): string {
  return `höchstens ${limits.weeklyRemainingMeters} m, keine Einheit über ${limits.sessionCapMeters} m, höchstens ${limits.maxSessions} Trainingstage, höchstens ${limits.maxHardDays} harte Einheiten`;
}

