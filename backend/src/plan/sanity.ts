import { Equipment, EQUIPMENT_LABELS, Intensity, PlanSet, TrainingPlan } from "./plan";
import { Snapshot } from "./snapshot";

/**
 * Sicherheitsschicht zwischen Claude und der App. Claude kann danebenliegen (zu grosse Spruenge, zu
 * wenig Erholung, unrealistische Zeiten). Diese Schicht ist reiner Code ohne Netzwerk, korrigiert
 * solche Plaene deterministisch oder blockt sie, wenn sie nicht mehr zu retten sind.
 *
 * Alle Schwellen stehen in `DEFAULT_LIMITS` und sind Startwerte, die sich mit echten Daten justieren
 * lassen. Die Regeln sind in der README (Abschnitt M5) beschrieben.
 */
export interface SanityLimits {
  /** Eine Einheit darf hoechstens so viel laenger sein wie die laengste der letzten 4 Wochen. */
  maxSessionGrowthFactor: number;
  /** Untergrenze fuer das Einheiten-Limit, damit auch ohne Historie geschwommen werden darf. */
  minSessionCapMeters: number;
  absoluteMaxSessionMeters: number;
  /** Wochenumfang inklusive heute darf hoechstens so viel ueber dem Wochenschnitt liegen. */
  maxWeeklyGrowthFactor: number;
  minWeeklyCapMeters: number;
  /** Ab so vielen Einheiten in 7 Tagen ist ein Ruhetag Pflicht. */
  maxSessionsPerSevenDays: number;
  /** Nach einer Trainingspause darf eine Einheit hoechstens so lang sein. */
  pauseCapMeters: number;
  recoveryPoorDistanceFactor: number;
  volumeSpikeDistanceFactor: number;
  /** Kleinste sinnvolle Einheit: Bleibt weniger als das uebrig, wird daraus ein Ruhetag. */
  minMeaningfulSessionMeters: number;
  /** Beim Zuspitzen (8 bis 14 Tage vor dem Ziel) hoechstens dieser Anteil des Wochenschnitts pro 7 Tage. */
  taperWeeklyFactor: number;
  /** In der Zielwoche (hoechstens 7 Tage vor dem Ziel) hoechstens dieser Anteil, mindestens aber 1,2 mal die Zieldistanz. */
  peakWeekWeeklyFactor: number;
  /**
   * Schnellste erlaubte Zielpace relativ zur aktuellen Pace. Die aktuelle Pace im Snapshot ist
   * Gesamtzeit durch Distanz inklusive Pausen, das echte Schwimmtempo ist also schneller. Der Faktor
   * ist deshalb locker gewaehlt und faengt nur unsinnige Vorgaben ab.
   */
  fastestVsRecentFactor: number;
  fastestVsGoalFactor: number;
  /** Ohne Pace-Historie: nicht schneller als Zielpace mal diesen Faktor. */
  unknownPaceVsGoalFactor: number;
  slowestPace: number;
  minRepDistance: number;
  maxRepDistance: number;
  maxRepetitions: number;
  maxRestSeconds: number;
  maxSets: number;
  minDurationMinutes: number;
  maxDurationMinutes: number;
  maxRationaleLength: number;
  maxInstructionLength: number;
  maxEquipmentPerSet: number;
  /** Laenge der Kurzbeschreibung fuer die Uhr. */
  maxCueLength: number;
  maxNotes: number;
  maxNoteLength: number;
}

export const DEFAULT_LIMITS: SanityLimits = {
  maxSessionGrowthFactor: 1.25,
  minSessionCapMeters: 1000,
  absoluteMaxSessionMeters: 4500,
  maxWeeklyGrowthFactor: 1.3,
  minWeeklyCapMeters: 1500,
  maxSessionsPerSevenDays: 5,
  pauseCapMeters: 800,
  recoveryPoorDistanceFactor: 0.5,
  volumeSpikeDistanceFactor: 0.6,
  minMeaningfulSessionMeters: 400,
  taperWeeklyFactor: 0.85,
  peakWeekWeeklyFactor: 0.7,
  fastestVsRecentFactor: 0.6,
  fastestVsGoalFactor: 0.9,
  unknownPaceVsGoalFactor: 1.3,
  slowestPace: 600,
  /** Kein Satz (keine Wiederholung) ist kuerzer; Saetze sind Vielfache von 50 m (ein 25-m- und ein 50-m-Becken gehen auf). */
  minRepDistance: 50,
  maxRepDistance: 3800,
  maxRepetitions: 100,
  maxRestSeconds: 600,
  maxSets: 20,
  minDurationMinutes: 5,
  maxDurationMinutes: 180,
  maxRationaleLength: 1200,
  maxInstructionLength: 600,
  maxEquipmentPerSet: 3,
  maxCueLength: 40,
  maxNotes: 5,
  maxNoteLength: 300
};

export interface SanityResult {
  /** Der korrigierte Plan. Bei `blocked` der unveraenderte Eingangsplan, er darf nicht genutzt werden. */
  plan: TrainingPlan;
  /** Jede vorgenommene Korrektur auf Deutsch, damit die App sie anzeigen und das Log sie nennen kann. */
  adjustments: string[];
  /** Grund, warum der Plan unbrauchbar ist und verworfen werden muss, sonst `null`. */
  blocked: string | null;
}

const RANK: Record<Intensity, number> = { rest: 0, easy: 1, moderate: 2, hard: 3 };
/** Jede Distanz ist ein Vielfaches davon: passt fuer ein 25-m- und ein 50-m-Becken. */
const DISTANCE_STEP = 50;

/**
 * Die Grenzen fuer heute, abgeleitet aus dem Zustand. Dieselben Zahlen gehen an Claude (Prompt, damit
 * der Plan von Anfang an hineinpasst) und pruefen den Plan hinterher (sanitizePlan). Eine Quelle,
 * damit beides nie auseinanderlaeuft.
 */
export interface DailyLimits {
  /** Grund fuer einen Pflicht-Ruhetag, sonst `null`. */
  restReason: string | null;
  maxIntensity: Intensity;
  intensityReasons: string[];
  maxDistanceMeters: number;
  /** Schnellste erlaubte Zielpace in Sekunden pro 100 m. */
  fastestPace: number;
}

export function dailyLimits(snapshot: Snapshot, limits: SanityLimits = DEFAULT_LIMITS): DailyLimits {
  const maxDistanceMeters = Math.floor(allowedDistance(snapshot, limits));
  const restReason =
    requiredRestReason(snapshot, limits) ?? (maxDistanceMeters < limits.minMeaningfulSessionMeters ? "Wochenumfang ausgeschöpft" : null);
  const cap = intensityCap(snapshot);
  return {
    restReason,
    maxIntensity: cap.max,
    intensityReasons: cap.reasons,
    maxDistanceMeters,
    fastestPace: Math.round(fastestAllowedPace(snapshot, limits))
  };
}

export interface SanityOptions {
  /** Das Equipment, das der Athlet hat. Fehlt die Angabe, ist jedes erlaubt. */
  availableEquipment?: readonly Equipment[];
}

export function sanitizePlan(input: TrainingPlan, snapshot: Snapshot, limits: SanityLimits = DEFAULT_LIMITS, options: SanityOptions = {}): SanityResult {
  const problem = findStructuralProblem(input, limits);
  if (problem) return { plan: input, adjustments: [], blocked: problem };

  const adjustments: string[] = [];
  let plan = normalize(input, limits, adjustments);

  if (isRestDay(plan)) return done(asRestDay(plan, null), adjustments);

  // Hilfsmittel, die der Athlet nicht hat, fliegen raus (Claude soll sie gar nicht erst planen).
  if (options.availableEquipment) {
    const available = new Set<string>(options.availableEquipment);
    const removed = new Set<Equipment>();
    plan = {
      ...plan,
      sets: plan.sets.map((set) => ({
        ...set,
        equipment: set.equipment.filter((item) => {
          if (available.has(item)) return true;
          removed.add(item);
          return false;
        })
      }))
    };
    if (removed.size > 0) {
      adjustments.push(`Hilfsmittel entfernt, die du nicht hast: ${[...removed].map((item) => EQUIPMENT_LABELS[item]).join(", ")}`);
    }
  }

  const computedTotal = totalDistance(plan.sets);
  if (computedTotal !== input.total_distance_meters) {
    adjustments.push(`Gesamtdistanz korrigiert: ${input.total_distance_meters} m auf ${computedTotal} m (Summe der Abschnitte)`);
  }

  const today = dailyLimits(snapshot, limits);

  // 1. Pflicht-Ruhetag
  if (today.restReason !== null) {
    adjustments.push(`Ruhetag erzwungen: ${today.restReason}`);
    return done(asRestDay(plan, today.restReason), adjustments);
  }

  // 2. Intensitaet begrenzen
  if (RANK[plan.intensity] > RANK[today.maxIntensity]) {
    adjustments.push(`Intensität von "${plan.intensity}" auf "${today.maxIntensity}" gesenkt: ${today.intensityReasons.join(", ")}`);
    plan = downgradeIntensity(plan, today.maxIntensity);
  }

  // 3. Umfang begrenzen
  const before = totalDistance(plan.sets);
  if (before > today.maxDistanceMeters) {
    const trimmed = trimToDistance(plan.sets, today.maxDistanceMeters, limits.minRepDistance);
    const after = totalDistance(trimmed);
    if (after < limits.minMeaningfulSessionMeters) {
      const reason = "zu wenig sicherer Restumfang";
      adjustments.push(`Ruhetag erzwungen: ${reason}`);
      return done(asRestDay(plan, reason), adjustments);
    }
    adjustments.push(`Umfang von ${before} m auf ${after} m gekürzt (Grenze für heute: ${today.maxDistanceMeters} m)`);
    plan = {
      ...plan,
      sets: trimmed,
      estimated_duration_minutes: clampMinutes(Math.round((plan.estimated_duration_minutes * after) / before), limits)
    };
  }

  // 4. Zielpace begrenzen
  let paceClamped = false;
  plan = {
    ...plan,
    sets: plan.sets.map((set) => {
      const pace = set.target_pace_seconds_per_hundred_meters;
      if (pace !== null && pace < today.fastestPace) {
        paceClamped = true;
        return { ...set, target_pace_seconds_per_hundred_meters: today.fastestPace };
      }
      return set;
    })
  };
  if (paceClamped) adjustments.push(`Zielpace auf höchstens ${today.fastestPace} s/100 m begrenzt (nicht schneller als realistisch)`);

  plan = { ...plan, total_distance_meters: totalDistance(plan.sets) };
  return done(withAdjustmentNote(plan, adjustments, limits), adjustments);
}

/**
 * Die Begruendung stammt von Claude und nennt die Zahlen des urspruenglichen Plans (z. B. "1700 m").
 * Nach einer Korrektur waere sie sonst falsch. Der Hinweis haengt die Korrekturen an, damit Plan und
 * Begruendung zusammenpassen, auch wenn die App das Feld `adjustments` nicht anzeigt. Rein formale
 * Korrekturen (falsche Summe) gehoeren nicht in die Begruendung.
 */
const FORMAL_ADJUSTMENT_PREFIX = "Gesamtdistanz korrigiert";
const FORMAL_SHORT_SETS_PREFIX = "Sätze auf Vielfache von 50 m gebracht";

function withAdjustmentNote(plan: TrainingPlan, adjustments: string[], limits: SanityLimits): TrainingPlan {
  const substantive = adjustments.filter((adjustment) => !adjustment.startsWith(FORMAL_ADJUSTMENT_PREFIX) && !adjustment.startsWith(FORMAL_SHORT_SETS_PREFIX));
  if (substantive.length === 0) return plan;

  const note = `Hinweis: Zur Sicherheit angepasst (${substantive.join("; ")}).`;
  const room = Math.max(limits.maxRationaleLength - note.length - 1, 0);
  return { ...plan, rationale: `${plan.rationale.slice(0, room).trimEnd()} ${note}`.trim() };
}

function done(plan: TrainingPlan, adjustments: string[]): SanityResult {
  return { plan, adjustments, blocked: null };
}

// --- Strukturpruefung ---

/** Gibt einen Grund zurueck, wenn der Plan so kaputt ist, dass Korrigieren nicht mehr vertrauenswuerdig waere. */
function findStructuralProblem(plan: TrainingPlan, limits: SanityLimits): string | null {
  if (plan.rationale.trim() === "") return "Begründung fehlt";
  if (plan.sets.length > limits.maxSets) return `zu viele Abschnitte (${plan.sets.length})`;
  if (!Number.isFinite(plan.total_distance_meters) || plan.total_distance_meters < 0) return "Gesamtdistanz ungültig";
  if (!Number.isFinite(plan.estimated_duration_minutes) || plan.estimated_duration_minutes < 0) return "Dauer ungültig";

  for (const set of plan.sets) {
    if (![set.repetitions, set.distance_meters, set.rest_seconds].every(Number.isFinite)) return "Zahlenwert in einem Abschnitt ungültig";
    if (set.repetitions < 1 || set.distance_meters < 1 || set.rest_seconds < 0) return "Abschnitt mit unmöglichen Werten";
    const pace = set.target_pace_seconds_per_hundred_meters;
    if (pace !== null && (!Number.isFinite(pace) || pace <= 0)) return "Zielpace ungültig";
  }

  const restLike = plan.session_type === "rest" || plan.intensity === "rest";
  if (!restLike && plan.sets.length === 0) return "Plan ohne Abschnitte";

  const total = totalDistance(plan.sets);
  if (total > limits.absoluteMaxSessionMeters * 3) return `unrealistischer Umfang (${total} m)`;
  return null;
}

function isRestDay(plan: TrainingPlan): boolean {
  return plan.session_type === "rest" || plan.intensity === "rest";
}

// --- Normalisieren (Korrekturen an Formalien, ohne Hinweis in der Begruendung) ---

function normalize(plan: TrainingPlan, limits: SanityLimits, adjustments: string[]): TrainingPlan {
  let merged = 0;
  const sets = plan.sets
    .map((raw) => {
      const set = alignToPoolLengths(raw, limits);
      if (set !== raw) merged += 1;
      return set;
    })
    .map((set) => ({
    ...set,
    name: set.name.trim().slice(0, 100),
    instructions: set.instructions.trim().slice(0, limits.maxInstructionLength),
    cue: set.cue.trim().slice(0, limits.maxCueLength),
    equipment: [...new Set(set.equipment)].slice(0, limits.maxEquipmentPerSet),
    repetitions: clamp(Math.round(set.repetitions), 1, limits.maxRepetitions),
    distance_meters: clamp(roundToStep(set.distance_meters), limits.minRepDistance, limits.maxRepDistance),
    rest_seconds: clamp(Math.round(set.rest_seconds), 0, limits.maxRestSeconds),
    target_pace_seconds_per_hundred_meters:
      set.target_pace_seconds_per_hundred_meters !== null && set.target_pace_seconds_per_hundred_meters > limits.slowestPace
        ? null
        : set.target_pace_seconds_per_hundred_meters
  }));
  if (merged > 0) adjustments.push(`${FORMAL_SHORT_SETS_PREFIX} (${merged} ${merged === 1 ? "Abschnitt" : "Abschnitte"}, passt für 25-m- und 50-m-Becken)`);

  return {
    ...plan,
    rationale: plan.rationale.trim().slice(0, limits.maxRationaleLength),
    coach_notes: plan.coach_notes
      .map((note) => note.trim().slice(0, limits.maxNoteLength))
      .filter((note) => note !== "")
      .slice(0, limits.maxNotes),
    estimated_duration_minutes: clampMinutes(plan.estimated_duration_minutes, limits),
    sets
  };
}

/**
 * Saetze sind Vielfache von 50 m, damit der Plan fuer ein 25-m- und ein 50-m-Becken aufgeht. Eine andere
 * Satzlaenge (25 m, 75 m, 130 m ...) wird auf das naechste Vielfache gebracht und die Zahl der Wiederholungen so
 * angepasst, dass die Strecke des Abschnitts etwa gleich bleibt (4 x 25 m wird 2 x 50 m, 3 x 75 m wird 2 x 100 m).
 */
function alignToPoolLengths(set: PlanSet, limits: SanityLimits): PlanSet {
  const step = DISTANCE_STEP;
  if (Number.isInteger(set.distance_meters) && set.distance_meters >= limits.minRepDistance && set.distance_meters % step === 0) return set;
  const distance = Math.max(roundToStep(set.distance_meters), limits.minRepDistance);
  const total = Math.max(Math.round(set.repetitions), 1) * set.distance_meters;
  return { ...set, distance_meters: distance, repetitions: Math.max(Math.round(total / distance), 1) };
}

function asRestDay(plan: TrainingPlan, reason: string | null): TrainingPlan {
  return {
    ...plan,
    session_type: "rest",
    intensity: "rest",
    // Die Begruendung des urspruenglichen Plans passt zu einem Ruhetag nicht mehr.
    rationale: reason === null ? plan.rationale : `Heute ist Ruhe angesagt: ${reason}.`,
    total_distance_meters: 0,
    estimated_duration_minutes: 0,
    sets: []
  };
}

// --- Regeln ---

function requiredRestReason(snapshot: Snapshot, limits: SanityLimits): string | null {
  if (snapshot.flags.includes("overreaching_risk")) return "Erholungswerte schlecht bei hoher Belastung (Übertrainingsrisiko)";
  if (snapshot.volume.sessions_last_seven_days >= limits.maxSessionsPerSevenDays) {
    return `schon ${snapshot.volume.sessions_last_seven_days} Einheiten in den letzten 7 Tagen, ein Ruhetag ist fällig`;
  }
  return null;
}

function intensityCap(snapshot: Snapshot): { max: Intensity; reasons: string[] } {
  let max: Intensity = "hard";
  const reasons: string[] = [];
  const apply = (limit: Intensity, reason: string): void => {
    if (RANK[limit] < RANK[max]) max = limit;
    reasons.push(reason);
  };

  const hardDaysAgo = snapshot.load.days_since_last_hard_session;
  if (snapshot.flags.includes("recovery_poor") || snapshot.recovery.status === "poor") apply("easy", "Erholung schlecht");
  else if (snapshot.recovery.status === "moderate") apply("moderate", "Erholung mäßig");
  if (snapshot.flags.includes("training_pause")) apply("easy", "Wiedereinstieg nach Trainingspause");
  if (snapshot.flags.includes("volume_spike")) apply("moderate", "Umfang zuletzt stark gestiegen");
  if (hardDaysAgo !== undefined && hardDaysAgo <= 1) apply("moderate", "gestern oder heute schon eine harte Einheit");

  return { max, reasons };
}

function downgradeIntensity(plan: TrainingPlan, max: Intensity): TrainingPlan {
  const harsh = plan.session_type === "intervals" || plan.session_type === "threshold" || plan.session_type === "test";
  return {
    ...plan,
    intensity: max,
    session_type: harsh ? "endurance" : plan.session_type,
    // Zielzeiten gehoerten zur haerteren Einheit und passen nicht mehr.
    sets: plan.sets.map((set) => ({ ...set, target_pace_seconds_per_hundred_meters: null }))
  };
}

/** Wie viele Meter heute hoechstens erlaubt sind. */
function allowedDistance(snapshot: Snapshot, limits: SanityLimits): number {
  const sessionCap = Math.min(
    Math.max(snapshot.volume.longest_session_meters * limits.maxSessionGrowthFactor, limits.minSessionCapMeters),
    limits.absoluteMaxSessionMeters
  );
  const weeklyCap = Math.max(snapshot.volume.average_weekly_meters * limits.maxWeeklyGrowthFactor, limits.minWeeklyCapMeters);
  let cap = Math.min(sessionCap, weeklyCap - snapshot.volume.last_seven_days_meters);

  const candidates = [cap];
  if (snapshot.flags.includes("recovery_poor") || snapshot.recovery.status === "poor") {
    candidates.push(cap * limits.recoveryPoorDistanceFactor);
  }
  if (snapshot.flags.includes("volume_spike")) candidates.push(cap * limits.volumeSpikeDistanceFactor);
  if (snapshot.flags.includes("training_pause")) candidates.push(limits.pauseCapMeters);
  cap = Math.min(...candidates);
  return Math.max(cap, 0);
}

function fastestAllowedPace(snapshot: Snapshot, limits: SanityLimits): number {
  const goal = snapshot.goal.target_pace_seconds_per_hundred_meters;
  const recent = snapshot.pace.recent_pace_seconds_per_hundred_meters;
  if (recent === undefined) return goal * limits.unknownPaceVsGoalFactor;
  return Math.max(goal * limits.fastestVsGoalFactor, recent * limits.fastestVsRecentFactor);
}

/**
 * Kuerzt den groessten Abschnitt so lange, bis der Plan in die Grenze passt. Einschwimmen und
 * Ausschwimmen bleiben dadurch meist erhalten, weil der Hauptsatz zuerst schrumpft.
 */
function trimToDistance(sets: PlanSet[], maxMeters: number, minRepMeters: number): PlanSet[] {
  const result = sets.map((set) => ({ ...set }));
  for (let guard = 0; guard < 10_000 && totalDistance(result) > maxMeters && result.length > 0; guard++) {
    const excess = totalDistance(result) - maxMeters;
    let largest = 0;
    result.forEach((set, index) => {
      if (set.repetitions * set.distance_meters > result[largest].repetitions * result[largest].distance_meters) largest = index;
    });
    const set = result[largest];

    if (set.repetitions > 1) {
      set.repetitions = Math.max(1, set.repetitions - Math.ceil(excess / set.distance_meters));
    } else {
      const shorter = set.distance_meters - Math.ceil(excess / DISTANCE_STEP) * DISTANCE_STEP;
      if (shorter < minRepMeters) result.splice(largest, 1);
      else set.distance_meters = shorter;
    }
  }
  return result;
}

// --- Hilfsfunktionen ---

function totalDistance(sets: PlanSet[]): number {
  return sets.reduce((sum, set) => sum + set.repetitions * set.distance_meters, 0);
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function roundToStep(value: number): number {
  return Math.round(value / DISTANCE_STEP) * DISTANCE_STEP;
}

function clampMinutes(value: number, limits: SanityLimits): number {
  return clamp(Math.round(value), limits.minDurationMinutes, limits.maxDurationMinutes);
}
