import { assessGoal } from "./goal";
import { dailyLimits, DailyLimits, DEFAULT_LIMITS, SanityLimits } from "./sanity";
import { Intensity } from "./plan";
import { Snapshot } from "./snapshot";
import { WeekDay, WeekPlan, weekdayName } from "./week";

/**
 * Sicherheitsschicht fuer den Wochenplan. Wie sanitizePlan beim Tagesplan: reiner Code, korrigiert
 * Claudes Wochenplan deterministisch oder blockt ihn. Die Zahlen aus `weekLimits` gehen vorab auch an
 * Claude (Prompt), damit der Plan von Anfang an hineinpasst.
 *
 * Regeln: Tage und Daten stimmen, "keine Zeit" ist ein Ruhetag, die Grenzen fuer heute gelten, keine
 * Einheit ueber dem Einheiten-Limit, hoechstens zwei harte Tage und nie nacheinander, hoechstens fuenf
 * Einheiten pro Woche (schon geschwommene Tage zaehlen mit), mindestens ein Ruhetag in einer vollen
 * Woche, Wochenumfang unter der Wochengrenze.
 */
export interface WeekContext {
  /** Heute (Kalendertag des Athleten). */
  today: string;
  /** Die zu planenden Tage, aufsteigend (ab `from_date` bis Sonntag). */
  dates: string[];
  /** Tage, an denen der Athlet keine Zeit hat. */
  unavailable: string[];
  /** Was in dieser Woche vor dem ersten geplanten Tag schon geschwommen wurde (zaehlt zum Wochenumfang). */
  swumBefore: { date: string; meters: number }[];
  /** Was in den sieben Tagen vor dem ersten geplanten Tag geschwommen wurde, nur als Information fuer Claude (die Vorwoche beim rollenden Plan). */
  recentSwim?: { date: string; meters: number }[];
}

export interface WeekLimits {
  /** Hoechstens so viele Meter pro Einheit. */
  sessionCapMeters: number;
  /** Hoechstens so viele Meter ueber alle zu planenden Tage zusammen. */
  weeklyRemainingMeters: number;
  /** Hoechstens so viele Trainingstage in den zu planenden Tagen. */
  maxSessions: number;
  maxHardDays: number;
  /** Die Grenzen fuer heute, wenn heute zu den geplanten Tagen gehoert, sonst `null`. */
  today: DailyLimits | null;
}

export interface WeekSanityResult {
  plan: WeekPlan;
  adjustments: string[];
  /** Grund, warum der Plan unbrauchbar ist, sonst `null`. */
  blocked: string | null;
}

const RANK: Record<Intensity, number> = { rest: 0, easy: 1, moderate: 2, hard: 3 };
const STEP = 25;
const MAX_FOCUS_LENGTH = 80;
const MAX_HARD_DAYS = 2;

export function weekLimits(snapshot: Snapshot, context: WeekContext, limits: SanityLimits = DEFAULT_LIMITS): WeekLimits {
  const includesToday = context.dates.includes(context.today);

  let sessionCap = Math.min(
    Math.max(snapshot.volume.longest_session_meters * limits.maxSessionGrowthFactor, limits.minSessionCapMeters),
    limits.absoluteMaxSessionMeters
  );
  let weeklyCap = Math.max(snapshot.volume.average_weekly_meters * limits.maxWeeklyGrowthFactor, limits.minWeeklyCapMeters);

  // Die Zustandsgrenzen (Erholung, Umfangsspitze, Pause) beschreiben heute. Fuer eine kommende Woche
  // gelten sie nicht: Bis dahin ist der Zustand ein anderer, und die naechste Planung kennt ihn.
  if (includesToday) {
    if (snapshot.flags.includes("recovery_poor") || snapshot.recovery.status === "poor") weeklyCap *= limits.recoveryPoorDistanceFactor;
    if (snapshot.flags.includes("volume_spike")) weeklyCap *= limits.volumeSpikeDistanceFactor;
    if (snapshot.flags.includes("training_pause")) {
      sessionCap = Math.min(sessionCap, limits.pauseCapMeters);
      weeklyCap = Math.min(weeklyCap, limits.pauseCapMeters * 3);
    }
    // Zuspitzen: In den letzten zwei Wochen vor dem Ziel sinkt der Umfang unter den Wochenschnitt. Die
    // Zielwoche muss den Versuch auf die Zieldistanz (mit Einschwimmen) tragen koennen.
    const phase = assessGoal(snapshot).phase;
    if (phase === "taper" && snapshot.volume.average_weekly_meters > 0) {
      weeklyCap = Math.min(weeklyCap, Math.max(snapshot.volume.average_weekly_meters * limits.taperWeeklyFactor, limits.minMeaningfulSessionMeters * 2));
    } else if (phase === "peak_week" && snapshot.volume.average_weekly_meters > 0) {
      const floor = Math.max(snapshot.goal.distance_meters * 1.2, limits.minMeaningfulSessionMeters * 2);
      weeklyCap = Math.min(weeklyCap, Math.max(snapshot.volume.average_weekly_meters * limits.peakWeekWeeklyFactor, floor));
    }
  }

  const swumMeters = context.swumBefore.reduce((sum, day) => sum + day.meters, 0);
  const swumDays = context.swumBefore.filter((day) => day.meters > 0).length;
  return {
    sessionCapMeters: Math.floor(sessionCap),
    weeklyRemainingMeters: Math.max(Math.floor(weeklyCap - swumMeters), 0),
    maxSessions: Math.max(limits.maxSessionsPerSevenDays - swumDays, 0),
    maxHardDays: MAX_HARD_DAYS,
    today: includesToday ? dailyLimits(snapshot, limits) : null
  };
}

export function sanitizeWeek(
  input: WeekPlan,
  snapshot: Snapshot,
  context: WeekContext,
  limits: SanityLimits = DEFAULT_LIMITS
): WeekSanityResult {
  const problem = findProblem(input, limits);
  if (problem) return { plan: input, adjustments: [], blocked: problem };

  const adjustments: string[] = [];
  const week = weekLimits(snapshot, context, limits);

  // 1. Genau die angefragten Tage, jeder einmal, in der Reihenfolge der Daten.
  const byDate = new Map<string, WeekDay>();
  for (const day of input.days) {
    if (context.dates.includes(day.date) && !byDate.has(day.date)) byDate.set(day.date, day);
  }
  const missing = context.dates.filter((date) => !byDate.has(date));
  if (missing.length > 0) {
    adjustments.push(`${missing.length} fehlende Tage als Ruhetag ergänzt (${missing.map(label).join(", ")})`);
  }
  let days = context.dates.map((date) => normalizeDay(byDate.get(date) ?? restDay(date, "Ruhetag"), limits, adjustments, week.sessionCapMeters));

  // 2. Keine Zeit: Ruhetag.
  days = days.map((day) => {
    if (!context.unavailable.includes(day.date)) return day;
    if (isRest(day)) return { ...day, focus: "Keine Zeit" };
    adjustments.push(`${label(day.date)}: keine Zeit, als Ruhetag gesetzt`);
    return restDay(day.date, "Keine Zeit");
  });

  // 3. Die Grenzen fuer heute.
  if (week.today !== null) {
    const today = week.today;
    days = days.map((day) => (day.date === context.today ? applyToday(day, today, adjustments, limits) : day));
  }

  // 4. Harte Tage: hoechstens zwei, nie an aufeinanderfolgenden Tagen.
  let hardCount = 0;
  let previousHard = false;
  days = days.map((day) => {
    if (day.intensity !== "hard") {
      previousHard = false;
      return day;
    }
    if (hardCount >= week.maxHardDays || previousHard) {
      adjustments.push(
        `${label(day.date)}: harte Einheit auf "moderate" gesenkt (${previousHard ? "nicht an zwei Tagen nacheinander" : "höchstens zwei harte Tage pro Woche"})`
      );
      previousHard = false;
      return downgrade(day, "moderate");
    }
    hardCount += 1;
    previousHard = true;
    return day;
  });

  // 5. Zu viele Einheiten: die kuerzesten werden Ruhetage.
  const sessions = (): WeekDay[] => days.filter((day) => !isRest(day));
  while (sessions().length > week.maxSessions) {
    const shortest = [...sessions()].sort((a, b) => a.target_distance_meters - b.target_distance_meters || b.date.localeCompare(a.date))[0];
    adjustments.push(`${label(shortest.date)}: als Ruhetag gesetzt (höchstens ${limits.maxSessionsPerSevenDays} Einheiten pro Woche)`);
    days = days.map((day) => (day.date === shortest.date ? restDay(day.date, "Ruhetag") : day));
  }

  // 6. Wochenumfang.
  const total = sumDistance(days);
  if (total > week.weeklyRemainingMeters) {
    const factor = week.weeklyRemainingMeters / total;
    adjustments.push(`Wochenumfang von ${total} m auf höchstens ${week.weeklyRemainingMeters} m gekürzt`);
    days = days.map((day) => scale(day, factor, limits));
  }

  // 7. Eine volle Woche braucht mindestens einen Ruhetag.
  if (context.dates.length >= 6 && days.every((day) => !isRest(day))) {
    const shortest = [...days].sort((a, b) => a.target_distance_meters - b.target_distance_meters || b.date.localeCompare(a.date))[0];
    adjustments.push(`${label(shortest.date)}: als Ruhetag gesetzt (mindestens ein Ruhetag pro Woche)`);
    days = days.map((day) => (day.date === shortest.date ? restDay(day.date, "Ruhetag") : day));
  }

  const rationale = withNote(input.rationale.trim().slice(0, limits.maxRationaleLength), adjustments, limits);
  return { plan: { rationale, days }, adjustments, blocked: null };
}

// --- Bausteine ---

function findProblem(plan: WeekPlan, limits: SanityLimits): string | null {
  if (plan.rationale.trim() === "") return "Begründung fehlt";
  if (plan.days.length === 0) return "Wochenplan ohne Tage";
  if (plan.days.length > 14) return `zu viele Tage (${plan.days.length})`;
  for (const day of plan.days) {
    if (![day.target_distance_meters, day.estimated_duration_minutes].every(Number.isFinite)) return "Zahlenwert in einem Tag ungültig";
    if (day.target_distance_meters < 0 || day.target_distance_meters > limits.absoluteMaxSessionMeters * 3) {
      return `unrealistischer Umfang (${day.target_distance_meters} m)`;
    }
  }
  return null;
}

function label(date: string): string {
  return `${weekdayName(date)}, ${date.slice(8, 10)}.${date.slice(5, 7)}.`;
}

function isRest(day: WeekDay): boolean {
  return day.session_type === "rest" || day.intensity === "rest" || day.target_distance_meters === 0;
}

function restDay(date: string, focus: string): WeekDay {
  return { date, session_type: "rest", intensity: "rest", target_distance_meters: 0, estimated_duration_minutes: 0, focus };
}

function roundToStep(value: number): number {
  return Math.round(value / STEP) * STEP;
}

function normalizeDay(day: WeekDay, limits: SanityLimits, adjustments: string[], sessionCap: number): WeekDay {
  const focus = day.focus.trim().slice(0, MAX_FOCUS_LENGTH);
  if (day.session_type === "rest" || day.intensity === "rest" || day.target_distance_meters === 0) {
    return restDay(day.date, focus === "" ? "Ruhetag" : focus);
  }

  let distance = roundToStep(day.target_distance_meters);
  if (distance < limits.minMeaningfulSessionMeters) {
    // Eine halbe Einheit ist meist eine zu vorsichtig geplante: auf das Minimum anheben, wenn die
    // Einheitengrenze es zulaesst. Alles darunter ist keine Einheit und wird ein Ruhetag.
    if (distance * 2 >= limits.minMeaningfulSessionMeters && limits.minMeaningfulSessionMeters <= sessionCap) {
      adjustments.push(`${label(day.date)}: Einheit von ${distance} m auf ${limits.minMeaningfulSessionMeters} m angehoben (kleinste sinnvolle Einheit)`);
      distance = limits.minMeaningfulSessionMeters;
    } else {
      adjustments.push(`${label(day.date)}: Einheit unter ${limits.minMeaningfulSessionMeters} m als Ruhetag gesetzt`);
      return restDay(day.date, "Ruhetag");
    }
  }
  const capped = Math.min(distance, Math.floor(sessionCap / STEP) * STEP);
  if (capped < distance) {
    adjustments.push(`${label(day.date)}: Umfang von ${distance} m auf ${capped} m gekürzt (Grenze pro Einheit)`);
  }
  return {
    ...day,
    target_distance_meters: capped,
    estimated_duration_minutes: Math.min(Math.max(Math.round(day.estimated_duration_minutes), limits.minDurationMinutes), limits.maxDurationMinutes),
    focus: focus === "" ? "Training" : focus
  };
}

function downgrade(day: WeekDay, max: Intensity): WeekDay {
  const harsh = day.session_type === "intervals" || day.session_type === "threshold" || day.session_type === "test";
  return { ...day, intensity: max, session_type: harsh ? "endurance" : day.session_type };
}

function applyToday(day: WeekDay, today: DailyLimits, adjustments: string[], limits: SanityLimits): WeekDay {
  if (today.restReason !== null) {
    if (!isRest(day)) adjustments.push(`${label(day.date)}: Ruhetag erzwungen (${today.restReason})`);
    return restDay(day.date, isRest(day) ? day.focus : "Ruhetag");
  }
  if (isRest(day)) return day;

  let result = day;
  if (RANK[result.intensity] > RANK[today.maxIntensity]) {
    adjustments.push(`${label(day.date)}: Intensität auf "${today.maxIntensity}" gesenkt (${today.intensityReasons.join(", ")})`);
    result = downgrade(result, today.maxIntensity);
  }
  if (result.target_distance_meters > today.maxDistanceMeters) {
    const capped = Math.floor(today.maxDistanceMeters / STEP) * STEP;
    if (capped < limits.minMeaningfulSessionMeters) {
      adjustments.push(`${label(day.date)}: Ruhetag erzwungen (zu wenig sicherer Restumfang)`);
      return restDay(day.date, "Ruhetag");
    }
    adjustments.push(`${label(day.date)}: Umfang von ${result.target_distance_meters} m auf ${capped} m gekürzt (Grenze für heute)`);
    result = {
      ...result,
      estimated_duration_minutes: Math.max(Math.round((result.estimated_duration_minutes * capped) / result.target_distance_meters), 5),
      target_distance_meters: capped
    };
  }
  return result;
}

function scale(day: WeekDay, factor: number, limits: SanityLimits): WeekDay {
  if (isRest(day)) return day;
  const distance = Math.floor((day.target_distance_meters * factor) / STEP) * STEP;
  if (distance < limits.minMeaningfulSessionMeters) return restDay(day.date, "Ruhetag");
  return {
    ...day,
    target_distance_meters: distance,
    estimated_duration_minutes: Math.max(Math.round((day.estimated_duration_minutes * distance) / day.target_distance_meters), limits.minDurationMinutes)
  };
}

function sumDistance(days: WeekDay[]): number {
  return days.reduce((sum, day) => sum + day.target_distance_meters, 0);
}

/** Wie beim Tagesplan: Die Begruendung nennt Zahlen des urspruenglichen Plans, die Korrekturen gehoeren dazu. */
function withNote(rationale: string, adjustments: string[], limits: SanityLimits): string {
  if (adjustments.length === 0) return rationale;
  const note = `Hinweis: Zur Sicherheit angepasst (${adjustments.join("; ")}).`;
  const room = Math.max(limits.maxRationaleLength - note.length - 1, 0);
  return `${rationale.slice(0, room).trimEnd()} ${note}`.trim().slice(0, limits.maxRationaleLength);
}
