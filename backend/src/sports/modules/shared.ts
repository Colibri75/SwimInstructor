import { SessionStep, SportPlanningContext, SportStateValues, TargetRange } from "../types";
import { StepTarget } from "../vocabulary";

/**
 * Bausteine, die mehrere Module fuer ihre Zielwerte nutzen. Sie kennen keine Sportart, nur Zahlen.
 */

/** Durchschnittliche Pace der letzten 4 Wochen in Sekunden pro `perMeters` (inklusive Pausen), ohne Daten `undefined`. */
export function recentPaceSeconds(state: SportStateValues, perMeters: number): number | undefined {
  if (state.average_weekly_meters <= 0 || state.average_weekly_minutes <= 0) return undefined;
  return (state.average_weekly_minutes * 60) / (state.average_weekly_meters / perMeters);
}

/**
 * Erlaubter Bereich fuer ein Pace-Ziel (Sekunden pro Strecke, kleiner ist schneller): nicht schneller als ein Anteil
 * der aktuellen Pace und nicht schneller als ein Anteil der Zielpace. Ohne aktuelle Pace gilt nur die Zielpace mal
 * `unknownGoalFactor` (vorsichtig, langsamer als das Ziel). Ohne beides gibt es kein Pace-Ziel (`null`).
 */
export function paceRange(options: {
  recent: number | undefined;
  goal: number | undefined;
  recentFactor: number;
  goalFactor: number;
  unknownGoalFactor: number;
  absoluteFastest: number;
  slowest: number;
}): TargetRange | null {
  const { recent, goal } = options;
  let fastest: number;
  if (recent !== undefined) fastest = Math.max(recent * options.recentFactor, goal === undefined ? 0 : goal * options.goalFactor);
  else if (goal !== undefined) fastest = goal * options.unknownGoalFactor;
  else return null;
  const min = Math.min(Math.max(Math.round(fastest), options.absoluteFastest), options.slowest);
  return { min, max: options.slowest };
}

/**
 * Ziel nach Zonen (z. B. Pulszonen 1 bis 5): nur, wenn die App fuer dieses Ziel Zonen gerechnet hat. Ohne Zonen kann
 * die Uhr kein Zonenziel anzeigen, der Kern ersetzt es dann durch die gefuehlte Anstrengung.
 */
export function zoneRange(context: SportPlanningContext, target: StepTarget, zones = 5): TargetRange | null {
  return context.performance?.zoneTargets.includes(target) === true ? { min: 1, max: zones } : null;
}

/** Ein Leistungswert aus dem Snapshot, egal welcher Herkunft; `undefined`, wenn unbekannt. */
export function performanceValue(context: SportPlanningContext, metric: string): number | undefined {
  return context.performance?.values[metric]?.value;
}

/** Ein Schritt nach Dauer mit gefuehlter Anstrengung als Ziel (Bausteine der Testeinheiten). */
export function effortStep(name: string, minutes: number, effort: number, cue: string, instructions: string, repetitions = 1, restSeconds = 0): SessionStep {
  return {
    name,
    repetitions,
    measure: "duration",
    distance_meters: null,
    duration_seconds: Math.round(minutes * 60),
    target_type: "perceived_effort",
    target_value: effort,
    rest_seconds: restSeconds,
    instructions,
    cue,
    equipment: []
  };
}

/** Wie `effortStep`, nach Strecke. */
export function effortDistanceStep(name: string, meters: number, effort: number, cue: string, instructions: string, repetitions = 1, restSeconds = 0): SessionStep {
  return { ...effortStep(name, 0, effort, cue, instructions, repetitions, restSeconds), measure: "distance", distance_meters: meters, duration_seconds: null };
}
