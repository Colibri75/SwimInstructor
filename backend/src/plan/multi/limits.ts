import { SportDefinition, SportStateValues, TrainingStatus } from "../../sports/types";
import { daysBetween, MacroPhase, mondayOf } from "../macro";
import { Intensity } from "../plan";
import { SnapshotV2 } from "../snapshot";
import { addDays } from "../week";
import { RecentTraining } from "./schemas";
import { fixedSport, isFitnessGoal, scheduleDay, weeklyMinutes } from "./schedule";
import { floorAmount, formatAmount, plannedSports, raceAmount, raceSeconds, sportName, stateAmounts, stateOf, trainingSpeed } from "./sports";

/**
 * Die Grenzen der Planung fuer mehrere Sportarten, aus dem Snapshot berechnet. Dieselben Zahlen gehen an Claude
 * (Prompt) und pruefen den Plan danach (Sicherheitsschicht): eine Quelle, damit beides nie auseinanderlaeuft.
 *
 * Je Sportart gelten die Grenzen ihres Moduls (`SportPlanning.limits`), uebergreifend die Regeln hier. Startwerte aus
 * dem Trainingswissen (docs/multisport-planning.md), justierbar im Betatest.
 */
export const MULTI_RULES = {
  maxSessionsPerDay: 2,
  maxHardSessionsPerDay: 1,
  /** Harte Tage ueber alle Sportarten in 7 Tagen, nie zwei hintereinander. */
  maxHardDaysPerWeek: 2,
  /** Schlechte Erholung: Umfang heute hoechstens so viel der Grenze. */
  recoveryPoorFactor: 0.5,
  /** Ein Tag hat hoechstens diesen Anteil der Wochenstunden des Ziels, mindestens aber `minDayMinutesCap`. */
  dayShareOfWeeklyHours: 0.5,
  minDayMinutesCap: 45,
  /** Entlastungswoche: hoechstens so viel der letzten normalen Woche (30 % weniger, Trainerpraxis 3:1). */
  deloadFactor: 0.7,
  /** Nach so vielen Belastungswochen hintereinander kommt eine Entlastungswoche. */
  maxLoadingWeeks: 3,
  /** Zuspitzen (Bosquet 2007: etwa 2 Wochen, Umfang 41 bis 60 % weniger, Intensitaet bleibt). */
  longRaceSeconds: 4 * 3600,
  taperFactorsLong: [0.75, 0.55] as readonly number[],
  taperFactorsShort: [0.6] as readonly number[],
  /** Aufbauphase (zielspezifisch) vor dem Zuspitzen, in Wochen. */
  specificWeeks: 8,
  /** Zielwoche: hoechstens dieser Anteil des Hoehepunkts, mindestens aber das 1,2-Fache des Wettkampfs. */
  goalWeekFactor: 0.5,
  goalWeekRaceFactor: 1.2,
  /** Kein Leistungstest in den letzten 14 Tagen vor dem Ziel. */
  testBlackoutDays: 14,
  /** So lange gilt ein selbst angegebenes Startniveau; danach zaehlt nur noch, was Health aufgezeichnet hat. */
  startingLevelValidDays: 28,
  defaultTestIntervalWeeks: 6,
  maxTestsPerWeek: 2,
  maxRationaleLength: 1200,
  maxFocusLength: 80,
  maxNotes: 5,
  maxNoteLength: 300,
  maxInstructionLength: 600,
  maxCueLength: 40,
  maxStepsPerSession: 20,
  maxRepetitions: 100,
  maxRestSeconds: 900,
  maxEquipmentPerStep: 3,
  maxChanges: 8,
  maxChangeLength: 200,
  /** Laenge der Bilanz einer Fortschreibung. */
  maxSummaryLength: 600,
  maxAdjustmentLines: 12
};

export const RANK: Record<Intensity, number> = { rest: 0, easy: 1, moderate: 2, hard: 3 };

export function lower(a: Intensity, b: Intensity): Intensity {
  return RANK[a] <= RANK[b] ? a : b;
}

/**
 * Ein selbst angegebenes Startniveau, wie es zaehlt: die Angabe (auf die Grenzen des Moduls gekappt) mal dem Anteil
 * fuer den Trainingsstand.
 */
export interface DeclaredLevel {
  status: Exclude<TrainingStatus, "beginner">;
  /** Anteil der Angabe, der gilt (z. B. 0,7 nach 2 bis 8 Wochen Pause). */
  factor: number;
  /** Wie angegeben (gekappt), in der Einheit der Sportart. */
  reportedWeekly: number;
  reportedLongest: number;
  /** Was davon gilt. */
  weekly: number;
  longest: number;
}

/**
 * Das Startniveau des Athleten fuer eine Sportart, wenn es gilt: angegeben, nicht aelter als `startingLevelValidDays`,
 * kein Einsteiger und ein Anteil ueber 0 (beim Laufen zaehlt eine Angabe nach langer Pause nicht).
 */
export function declaredLevel(snapshot: SnapshotV2, sport: SportDefinition): DeclaredLevel | null {
  const entry = snapshot.starting_levels?.find((level) => level.sport === sport.id);
  if (entry === undefined || entry.status === "beginner") return null;
  const ageDays = (Date.parse(snapshot.generated_at) - Date.parse(entry.reported_at)) / 86_400_000;
  if (!(ageDays >= -1 && ageDays <= MULTI_RULES.startingLevelValidDays)) return null;
  const factor = sport.planning.startingLevel.factors[entry.status];
  if (!(factor > 0)) return null;
  const limits = sport.planning.limits;
  const reportedLongest = Math.min(entry.longest_session, limits.absoluteMaxSession);
  const reportedWeekly = Math.min(entry.weekly_amount, limits.absoluteMaxSession * limits.maxSessionsPerWeek);
  return {
    status: entry.status,
    factor,
    reportedWeekly,
    reportedLongest,
    weekly: reportedWeekly * factor,
    longest: reportedLongest * factor
  };
}

/** Die Grenzen einer Sportart nach ihrem Verlauf, alle in der Einheit der Sportart. */
export interface SportLimitsNow {
  sport: SportDefinition;
  state: SportStateValues;
  /** Trainingstempo in m/s (fuer Umrechnungen zwischen Strecke und Dauer). */
  speed: number;
  /** Lange keine Einheit dieser Sportart (oder noch nie) und kein Startniveau angegeben: kurz und locker wieder einsteigen. */
  pause: boolean;
  /** Hoechstens so viel pro Einheit. */
  sessionCap: number;
  /** Hoechstens so viel in 7 Tagen. */
  weeklyCap: number;
  /** Was die letzten 7 Tage schon hatten. */
  lastSeven: number;
  /** Wochenschnitt, mit dem geplant wird: der hoehere aus den letzten 4 Wochen und dem angegebenen Startniveau. */
  average: number;
  /** Laengste Einheit, mit der geplant wird, ebenso. */
  longest: number;
  /** Aus Health (letzte 4 Wochen), ohne Angabe. */
  recordedAverage: number;
  recordedLongest: number;
  /** Das selbst angegebene Startniveau, wenn es gilt. */
  declared: DeclaredLevel | null;
}

export function sportLimits(snapshot: SnapshotV2, sport: SportDefinition): SportLimitsNow {
  const limits = sport.planning.limits;
  const state = stateOf(snapshot, sport.id);
  const recorded = stateAmounts(sport, state);
  const declared = declaredLevel(snapshot, sport);
  const longest = Math.max(recorded.longest, declared?.longest ?? 0);
  const average = Math.max(recorded.average, declared?.weekly ?? 0);
  const days = state.days_since_last_session;
  // Mit Startniveau sagt der angegebene Trainingsstand, wie es nach einer Pause weitergeht (der Anteil oben), nicht
  // die Luecke in Health: Wer ohne Uhr trainiert, ist sonst immer im Wiedereinstieg.
  const pause = declared === null && (days === undefined || days > limits.pauseAfterDays);
  let sessionCap = Math.min(Math.max(longest * limits.sessionGrowthFactor, limits.minSessionCap), limits.absoluteMaxSession);
  let weeklyCap = Math.max(average * limits.weeklyGrowthFactor, limits.minWeeklyCap);
  if (pause) {
    sessionCap = Math.min(sessionCap, limits.pauseSessionCap);
    weeklyCap = Math.min(weeklyCap, limits.pauseSessionCap * Math.min(limits.maxSessionsPerWeek, 3));
  }
  return {
    sport,
    state,
    speed: trainingSpeed(sport, state),
    pause,
    sessionCap: floorAmount(sport, sessionCap),
    weeklyCap: floorAmount(sport, weeklyCap),
    lastSeven: recorded.lastSeven,
    average,
    longest,
    recordedAverage: recorded.average,
    recordedLongest: recorded.longest,
    declared
  };
}

const STATUS_TEXT: Record<DeclaredLevel["status"], string> = {
  regular: "trainiert regelmäßig",
  short_break: "Pause von 2 bis 8 Wochen",
  long_break: "Pause über 8 Wochen"
};

/**
 * Das angegebene Startniveau als Satz fuer die Nutzernachricht (leer ohne Angabe), damit Claude die Grenzen erklaeren
 * kann: "Startniveau selbst angegeben: 6000 m pro Woche, längste Einheit 2500 m, Pause von 2 bis 8 Wochen; davon gelten
 * 70 % (4200 m pro Woche, längste 1750 m). Aufgezeichnet in Health: 570 m pro Woche, längste 1175 m."
 */
export function declaredLevelText(limits: SportLimitsNow): string {
  const declared = limits.declared;
  if (declared === null) return "";
  const sport = limits.sport;
  const share = declared.factor < 1
    ? `; davon gelten ${Math.round(declared.factor * 100)} % (${formatAmount(sport, declared.weekly)} pro Woche, längste ${formatAmount(sport, declared.longest)})`
    : "";
  return (
    `Startniveau selbst angegeben: ${formatAmount(sport, declared.reportedWeekly)} pro Woche, längste Einheit ` +
    `${formatAmount(sport, declared.reportedLongest)}, ${STATUS_TEXT[declared.status]}${share}. Aufgezeichnet in Health: ` +
    `${formatAmount(sport, limits.recordedAverage)} pro Woche, längste ${formatAmount(sport, limits.recordedLongest)}.`
  );
}

/** Grenzen einer Sportart fuer heute. */
export interface SportDayLimits {
  /** Grund, warum die Sportart heute nicht geht, sonst `null`. */
  blockedReason: string | null;
  maxAmount: number;
  maxIntensity: Intensity;
  intensityReasons: string[];
  /** Woraus `maxAmount` entsteht, damit Claude die Grenze in der Begruendung erklaeren kann. */
  sessionCap: number;
  weeklyCap: number;
  lastSeven: number;
  /** Wegen schlechter Erholung gekuerzt. */
  reducedForRecovery: boolean;
}

/**
 * Hoechstens so viele Minuten an einem Tag: an einem Trainingstag des Wochenrasters dessen Minuten, sonst die Haelfte
 * der Wochenstunden, mindestens 45 Minuten.
 */
export function dayMinutesCap(snapshot: SnapshotV2, date?: string): number {
  const scheduled = date !== undefined ? scheduleDay(snapshot, date) : undefined;
  if (scheduled !== undefined && scheduled.trains) return scheduled.max_minutes;
  return Math.round(Math.max(weeklyMinutes(snapshot) * MULTI_RULES.dayShareOfWeeklyHours, MULTI_RULES.minDayMinutesCap));
}

/** Die Grenzen fuer heute ueber alle Sportarten. */
export interface DayLimitsV2 {
  /** Grund fuer einen Pflicht-Ruhetag, sonst `null`. */
  restReason: string | null;
  maxIntensity: Intensity;
  intensityReasons: string[];
  /** Hoechstens so viele Minuten ueber alle Einheiten des Tages. */
  maxMinutes: number;
  sports: Map<string, SportDayLimits>;
  /** Grund, warum heute gar kein Leistungstest geht, sonst `null` (ein Test mit Vollbelastung braucht ausserdem "hard"). */
  testBlockedReason: string | null;
}

/** War der Tag vor `date` laut Verlauf hart? */
export function hardOn(recent: readonly RecentTraining[], date: string): boolean {
  return recent.some((entry) => entry.date === date && entry.hard === true);
}

export function dayLimits(snapshot: SnapshotV2, today: string, recent: readonly RecentTraining[] = []): DayLimitsV2 {
  const restReason = snapshot.flags.includes("overreaching_risk")
    ? "Erholungswerte schlecht bei hoher Belastung (Übertrainingsrisiko)"
    : scheduleDay(snapshot, today)?.trains === false
      ? "Ruhetag laut Wochenraster"
      : null;
  const fixed = fixedSport(snapshot, today);
  const poor = snapshot.flags.includes("recovery_poor") || snapshot.recovery.status === "poor";

  let maxIntensity = "hard" as Intensity;
  const intensityReasons: string[] = [];
  const cap = (limit: Intensity, reason: string) => {
    maxIntensity = lower(maxIntensity, limit);
    intensityReasons.push(reason);
  };
  if (poor) cap("easy", "Erholung schlecht");
  else if (snapshot.recovery.status === "moderate") cap("moderate", "Erholung mäßig");
  const hardDaysAgo = snapshot.load.days_since_last_hard_session;
  if (hardOn(recent, today) || hardOn(recent, addDays(today, -1)) || (hardDaysAgo !== undefined && hardDaysAgo <= 1)) {
    cap("moderate", "gestern oder heute schon eine harte Einheit");
  } else {
    const hardDays = new Set(recent.filter((entry) => entry.hard === true && entry.date < today && entry.date >= addDays(today, -6)).map((entry) => entry.date));
    if (hardDays.size >= MULTI_RULES.maxHardDaysPerWeek) cap("moderate", `schon ${hardDays.size} harte Tage in den letzten 7 Tagen`);
  }

  const sports = new Map<string, SportDayLimits>();
  for (const sport of plannedSports(snapshot)) {
    const limits = sportLimits(snapshot, sport);
    let maxAmount = Math.min(limits.sessionCap, limits.weeklyCap - limits.lastSeven);
    if (poor) maxAmount *= MULTI_RULES.recoveryPoorFactor;
    maxAmount = floorAmount(sport, Math.max(maxAmount, 0));
    const reasons = [...intensityReasons];
    let sportMax = maxIntensity;
    if (limits.pause) {
      sportMax = lower(sportMax, "easy");
      reasons.push("Wiedereinstieg nach Pause");
    }
    const blockedReason =
      fixed !== undefined && fixed !== sport.id
        ? `laut Wochenraster heute nur ${sportName(fixed)}`
        : maxAmount < sport.planning.limits.minSession
        ? limits.weeklyCap - limits.lastSeven < sport.planning.limits.minSession
          ? "Wochenumfang ausgeschöpft"
          : "zu wenig sicherer Umfang"
        : null;
    sports.set(sport.id, {
      blockedReason,
      maxAmount,
      maxIntensity: sportMax,
      intensityReasons: reasons,
      sessionCap: limits.sessionCap,
      weeklyCap: limits.weeklyCap,
      lastSeven: limits.lastSeven,
      reducedForRecovery: poor
    });
  }

  const maxMinutes = Math.round(dayMinutesCap(snapshot, today) * (poor ? MULTI_RULES.recoveryPoorFactor : 1));
  const testBlockedReason = restReason ?? testBlackoutReason(snapshot, today);
  return { restReason, maxIntensity, intensityReasons, maxMinutes, sports, testBlockedReason };
}

/** Kein Leistungstest in den letzten 14 Tagen vor dem Ziel (der Tag selbst zaehlt mit). */
export function testBlackoutReason(snapshot: SnapshotV2, date: string): string | null {
  if (isFitnessGoal(snapshot)) return null;
  const goalDay = goalDayOf(snapshot);
  if (goalDay < snapshot.generated_at.slice(0, 10)) return null;
  const days = daysBetween(date, goalDay);
  return days >= 0 && days <= MULTI_RULES.testBlackoutDays ? "kein Test in den letzten 14 Tagen vor dem Ziel" : null;
}

// --- Phasen bis zum Ziel ---

/** Wochen Zuspitzen: 2 bei einem Wettkampf ab etwa 4 Stunden, sonst 1; keine bei einem Fitnessziel. */
export function taperWeeks(snapshot: SnapshotV2): number {
  if (isFitnessGoal(snapshot)) return 0;
  return raceSeconds(snapshot) >= MULTI_RULES.longRaceSeconds ? MULTI_RULES.taperFactorsLong.length : MULTI_RULES.taperFactorsShort.length;
}

export function taperFactors(snapshot: SnapshotV2): readonly number[] {
  return taperWeeks(snapshot) === MULTI_RULES.taperFactorsLong.length ? MULTI_RULES.taperFactorsLong : MULTI_RULES.taperFactorsShort;
}

/** Wochen von der Woche `weekStart` bis zur Zielwoche (0 = Zielwoche). */
export function weeksToGoal(weekStart: string, goalDay: string): number {
  return Math.round(daysBetween(weekStart, mondayOf(goalDay)) / 7);
}

/** Phase einer Woche fuer den Plan ueber mehrere Sportarten: Zuspitzen je nach Wettkampfdauer 1 oder 2 Wochen. */
export function multiPhase(weekStart: string, goalDay: string, today: string, taper: number): MacroPhase {
  if (goalDay < today) return "maintain";
  const weeks = weeksToGoal(weekStart, goalDay);
  if (weeks <= 0) return "goal_week";
  if (weeks <= taper) return "taper";
  if (weeks <= taper + MULTI_RULES.specificWeeks) return "specific";
  return "base";
}

/**
 * Phase einer Woche fuer das Ziel des Snapshots. Ein Fitnessziel hat kein Zuspitzen und keine Zielwoche: Bis zum Ende
 * des Planungszeitraums ist jede Woche Aufbau (mit dem Ziel, den Wochenumfang des Wochenrasters zu erreichen und zu
 * halten), danach erhaltend.
 */
export function phaseOf(snapshot: SnapshotV2, weekStart: string, today: string): MacroPhase {
  const goalDay = goalDayOf(snapshot);
  if (isFitnessGoal(snapshot)) return goalDay < today ? "maintain" : "base";
  return multiPhase(weekStart, goalDay, today, taperWeeks(snapshot));
}

export function goalDayOf(snapshot: SnapshotV2): string {
  return snapshot.training_goal.target_date.slice(0, 10);
}

/** Eine Disziplin, deren laengste Einheit sich bis zum Ziel nicht sicher auf die Wettkampflaenge aufbauen laesst. */
export interface RealismGap {
  sport: SportDefinition;
  longest: number;
  race: number;
  /** Wochen, die der Aufbau mit dem Wachstum des Moduls braucht. */
  needed: number;
  /** Wochen bis zum Zuspitzen. */
  available: number;
}

/** Die Disziplinen des Ziels, fuer die die Zeit bis zum Ziel nicht reicht (leer, wenn das Ziel vorbei ist). */
export function realismGaps(snapshot: SnapshotV2, today: string): RealismGap[] {
  const goalDay = goalDayOf(snapshot);
  if (goalDay < today) return [];
  const available = Math.max(Math.max(weeksToGoal(mondayOf(today), goalDay), 0) - taperWeeks(snapshot), 0);
  return plannedSports(snapshot).flatMap((sport) => {
    const race = raceAmount(snapshot, sport);
    if (race <= 0) return [];
    const longest = sportLimits(snapshot, sport).longest;
    const start = Math.max(longest, sport.planning.limits.minSession);
    const needed = start >= race ? 0 : Math.ceil(Math.log(race / start) / Math.log(sport.planning.limits.macroGrowthFactor));
    return needed > available ? [{ sport, longest, race, needed, available }] : [];
  });
}
