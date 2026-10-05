import { SessionStep, SportDefinition, SportPlanningContext } from "../../sports/types";
import { StepTarget } from "../../sports/vocabulary";
import { Intensity } from "../vocabulary";
import { MULTI_RULES } from "./limits";
import { StepRaw } from "./schemas";

/**
 * Schritte einer Einheit: in die Masse und Raster der Sportart bringen, Ziele pruefen, auf eine Grenze kuerzen. Alles
 * aus den Angaben des Moduls (`SportPlanning`), ohne eine Sportart beim Namen zu kennen.
 */

/** Gefuehlte Anstrengung (1 bis 10) je Pulszone, wenn eine Pulszone nicht verwendbar ist (Friel/TrainerRoad). */
const ZONE_TO_EFFORT = [2, 3, 5, 7, 9];
/** Gefuehlte Anstrengung je Intensitaet, wenn ein Tempo- oder Wattziel wegfaellt. */
const INTENSITY_EFFORT: Record<Intensity, number> = { rest: 1, easy: 3, moderate: 5, hard: 8 };
/** Obergrenzen fuer Zonen- und Anstrengungsziele bei lockeren und mittleren Einheiten. */
const MAX_ZONE: Record<Intensity, number> = { rest: 1, easy: 2, moderate: 3, hard: 5 };
const MAX_EFFORT: Record<Intensity, number> = { rest: 2, easy: 4, moderate: 6, hard: 10 };

/** Ziele, deren Wert eine ganze Zahl ist (Zone, Anstrengung, Watt, Frequenzen). Pace bleibt auf Sekunden gerundet. */
const ROUND_DIGITS: Partial<Record<StepTarget, number>> = { speed: 1 };

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

/** Ein Schritt im Raster der Sportart; `null`, wenn er weder Strecke noch Dauer hat. */
export function normalizeStep(raw: StepRaw, sport: SportDefinition, speed: number, available?: ReadonlySet<string>): { step: SessionStep | null; removedEquipment: string[] } {
  const planning = sport.planning;
  let measure: "distance" | "duration" = raw.measure;
  let distance = raw.distance_meters;
  let duration = raw.duration_seconds;
  if (measure === "distance" && (distance === null || distance <= 0)) measure = "duration";
  else if (measure === "duration" && (duration === null || duration <= 0)) measure = "distance";
  if (measure === "distance" && (distance === null || distance <= 0)) return { step: null, removedEquipment: [] };
  if (measure === "duration" && (duration === null || duration <= 0)) return { step: null, removedEquipment: [] };
  // Ein Mass, in dem die Sportart nicht plant, wird mit dem Trainingstempo umgerechnet.
  if (!planning.stepMeasures.includes(measure)) {
    if (measure === "distance") {
      duration = (distance as number) / speed;
      distance = null;
      measure = "duration";
    } else {
      distance = (duration as number) * speed;
      duration = null;
      measure = "distance";
    }
  }

  let repetitions = Math.max(Math.round(raw.repetitions), 1);
  if (measure === "distance") {
    const raw_ = distance as number;
    const step = planning.distanceStepMeters;
    let aligned = clamp(Math.round(raw_ / step) * step, planning.minStepMeters, planning.maxStepMeters);
    aligned = Math.max(Math.round(aligned / step) * step, step);
    // Wie beim Schwimmen: aus 4 x 25 m werden 2 x 50 m, die Strecke des Schritts bleibt etwa gleich.
    if (aligned !== raw_) repetitions = Math.max(Math.round((repetitions * raw_) / aligned), 1);
    distance = aligned;
    duration = null;
  } else {
    duration = clamp(Math.round((duration as number) / 5) * 5, planning.minStepSeconds, planning.maxStepSeconds);
    distance = null;
  }

  const known = new Set(Object.keys(planning.equipment));
  const removedEquipment: string[] = [];
  const equipment = [...new Set(raw.equipment)].filter((item) => {
    const ok = known.has(item) && (available === undefined || available.has(item));
    if (!ok && known.has(item)) removedEquipment.push(item);
    return ok;
  });

  return {
    step: {
      name: raw.name.trim().slice(0, 100) || "Schritt",
      repetitions: Math.min(repetitions, MULTI_RULES.maxRepetitions),
      measure,
      distance_meters: distance,
      duration_seconds: duration,
      target_type: raw.target_type,
      target_value: raw.target_value,
      rest_seconds: clamp(Math.round(raw.rest_seconds), 0, MULTI_RULES.maxRestSeconds),
      instructions: raw.instructions.trim().slice(0, MULTI_RULES.maxInstructionLength),
      cue: raw.cue.trim().slice(0, MULTI_RULES.maxCueLength),
      equipment: equipment.slice(0, MULTI_RULES.maxEquipmentPerStep)
    },
    removedEquipment
  };
}

/**
 * Prueft das Ziel eines Schritts: erlaubt und im Bereich des Moduls (sonst auf den Bereich gesetzt), passend zur
 * Intensitaet der Einheit. Ein Ziel, das fuer den Athleten nicht in Frage kommt (z. B. Puls ohne Zonen, Watt ohne FTP),
 * wird zur gefuehlten Anstrengung, wenn die Sportart sie kennt, sonst entfaellt es.
 */
export function checkTarget(step: SessionStep, sport: SportDefinition, context: SportPlanningContext, intensity: Intensity): { step: SessionStep; changed: boolean } {
  const type = step.target_type;
  const value = step.target_value;
  if (type === null || value === null || !Number.isFinite(value)) {
    const changed = type !== null || value !== null;
    return { step: { ...step, target_type: null, target_value: null }, changed };
  }
  const range = sport.targets.includes(type) ? sport.planning.targetRange(type, context) : null;
  if (range !== null) {
    let next = clamp(value, range.min, range.max);
    if (type === "heart_rate_zone") next = Math.min(next, Math.max(MAX_ZONE[intensity], range.min));
    if (type === "perceived_effort") next = Math.min(next, Math.max(MAX_EFFORT[intensity], range.min));
    const digits = ROUND_DIGITS[type] ?? 0;
    next = Math.round(next * 10 ** digits) / 10 ** digits;
    return { step: { ...step, target_value: next }, changed: next !== value };
  }
  const effortRange = sport.targets.includes("perceived_effort") ? sport.planning.targetRange("perceived_effort", context) : null;
  if (effortRange === null) return { step: { ...step, target_type: null, target_value: null }, changed: true };
  const effort = type === "heart_rate_zone" ? (ZONE_TO_EFFORT[clamp(Math.round(value), 1, 5) - 1] ?? 5) : INTENSITY_EFFORT[intensity];
  const next = clamp(Math.min(effort, MAX_EFFORT[intensity]), effortRange.min, effortRange.max);
  return { step: { ...step, target_type: "perceived_effort", target_value: next }, changed: true };
}

/** Umfang eines Schritts je Wiederholung in der Einheit der Sportart (bei Minuten inklusive Pause). */
function perRepetition(step: SessionStep, sport: SportDefinition, speed: number): number {
  const seconds = step.measure === "duration" ? (step.duration_seconds ?? 0) : (step.distance_meters ?? 0) / speed;
  if (sport.planning.limitUnit === "meters") return step.measure === "distance" ? (step.distance_meters ?? 0) : seconds * speed;
  return (seconds + step.rest_seconds) / 60;
}

export function stepsAmount(steps: readonly SessionStep[], sport: SportDefinition, speed: number): number {
  return steps.reduce((sum, step) => sum + step.repetitions * perRepetition(step, sport, speed), 0);
}

/** Minuten eines Schritts je Wiederholung, inklusive Pause. */
function minutesPerRepetition(step: SessionStep, speed: number): number {
  const seconds = step.measure === "duration" ? (step.duration_seconds ?? 0) : (step.distance_meters ?? 0) / speed;
  return (seconds + step.rest_seconds) / 60;
}

/**
 * Kuerzt den groessten Schritt so lange, bis die Einheit in die Grenze passt: erst Wiederholungen, dann die Laenge,
 * zuletzt faellt er weg. Ein- und Auslaufen bleiben dadurch meist erhalten, weil der Hauptteil zuerst schrumpft. Die
 * Grenze gilt fuer den Umfang in der Einheit der Sportart oder (`by` "minutes") fuer die Dauer mit Pausen.
 */
export function trimSteps(steps: readonly SessionStep[], sport: SportDefinition, speed: number, cap: number, by: "amount" | "minutes" = "amount"): SessionStep[] {
  const planning = sport.planning;
  const per = (step: SessionStep) => (by === "minutes" ? minutesPerRepetition(step, speed) : perRepetition(step, sport, speed));
  const result = steps.map((step) => ({ ...step }));
  for (let guard = 0; guard < 10_000 && result.length > 0; guard += 1) {
    const excess = result.reduce((sum, step) => sum + step.repetitions * per(step), 0) - cap;
    if (excess <= 1e-6) break;
    let largest = 0;
    result.forEach((step, index) => {
      if (step.repetitions * per(step) > result[largest].repetitions * per(result[largest])) largest = index;
    });
    const step = result[largest];
    const perRep = per(step);
    if (step.repetitions > 1 && perRep > 0) {
      step.repetitions = Math.max(1, step.repetitions - Math.ceil(excess / perRep));
      continue;
    }
    // Ueberschuss in Sekunden bzw. Metern dieses Schritts.
    const excessSeconds = by === "minutes" || planning.limitUnit === "minutes" ? excess * 60 : excess / speed;
    if (step.measure === "duration") {
      const shorter = (step.duration_seconds ?? 0) - Math.ceil(excessSeconds / 5) * 5;
      if (shorter < planning.minStepSeconds) result.splice(largest, 1);
      else step.duration_seconds = shorter;
    } else {
      const excessMeters = planning.limitUnit === "meters" ? excess : excessSeconds * speed;
      const shorter = (step.distance_meters ?? 0) - Math.ceil(excessMeters / planning.distanceStepMeters) * planning.distanceStepMeters;
      if (shorter < planning.minStepMeters) result.splice(largest, 1);
      else step.distance_meters = shorter;
    }
  }
  return result;
}
