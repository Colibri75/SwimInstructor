import { LimitUnit, SportDefinition } from "../../sports/types";
import { Intensity, SessionType } from "../plan";
import { SnapshotV2 } from "../snapshot";
import { addDays, weekdayName } from "../week";
import { dayLimits, DayLimitsV2, dayMinutesCap, hardOn, lower, MULTI_RULES, RANK, sportLimits, SportLimitsNow, testBlackoutReason } from "./limits";
import { MacroWeekTargetV2, MultiWeekPlanRaw, RecentTraining, TestSettings, WeekSessionRaw } from "./schemas";
import { amountToMeters, amountToMinutes, floorAmount, formatAmount, plannedSports, roundAmount, sportName } from "./sports";
import { fixedSport, scheduleDay, trainingDaysPerWeek, weeklyMinutes } from "./schedule";
import { chooseTest, TestPlan, TestRef, testRef } from "./tests";

/**
 * Sicherheitsschicht fuer den Wochenplan ueber mehrere Sportarten (die naechsten sieben Tage). Reiner Code: korrigiert
 * deterministisch oder blockt. Regeln (docs/multisport-planning.md): genau die angefragten Tage; keine Zeit heisst
 * Ruhetag; hoechstens zwei Einheiten und eine harte je Tag; je Sportart Einheitengrenze, Wochengrenze und Zahl der
 * Einheiten; die Grenzen fuer heute; hoechstens zwei harte Tage ueber alle Sportarten, nie hintereinander (auch nicht
 * nach einem harten Tag vor dem Plan, Tests mit Vollbelastung zaehlen als harter Tag und gehen vor); Leistungstests nur,
 * wenn sie passen, hoechstens einer je Tag und je Sportart, nie an zwei Tagen hintereinander; jeder Tag hoechstens die
 * Haelfte der Wochenstunden (mit Wochenraster: dessen Minuten); Ruhetage und feste Sportarten des Wochenrasters; nicht
 * mehr Trainingstage als im Ziel; mindestens ein Ruhetag; hoechstens die Wochenstunden.
 */
export interface WeekContextV2 {
  today: string;
  /** Die sieben Tage ab `from_date`, aufsteigend. */
  dates: string[];
  unavailable: string[];
  /** Training vor dem ersten geplanten Tag (Information fuer Claude, harte Einheiten zaehlen fuer "nie hintereinander"). */
  recent: RecentTraining[];
  macroWeeks?: MacroWeekTargetV2[];
  testSettings?: TestSettings;
}

export interface WeekSessionV2 {
  sport: string;
  session_type: SessionType;
  intensity: Intensity;
  /** In der Einheit der Sportart (`unit`: "meters" oder "minutes", wie im Gesamtplan). */
  amount: number;
  unit: LimitUnit;
  minutes: number;
  distance_meters: number;
  focus: string;
  test: TestRef | null;
}

export interface WeekDayV2 {
  date: string;
  focus: string;
  sessions: WeekSessionV2[];
}

export interface WeekPlanV2 {
  rationale: string;
  total_minutes: number;
  days: WeekDayV2[];
}

export interface WeekSanityResultV2 {
  plan: WeekPlanV2;
  adjustments: string[];
  blocked: string | null;
}

export interface WeekLimitsV2 {
  sports: Map<string, SportLimitsNow>;
  maxHardDays: number;
  maxTrainingDays: number;
  maxMinutes: number;
  /** Hoechstens so viele Minuten an einem Tag ohne Wochenraster (heute gilt die Grenze in `today`). */
  maxDayMinutes: number;
  /** Je geplantem Tag hoechstens so viele Minuten: aus dem Wochenraster, sonst `maxDayMinutes`. */
  dayMinutes: Map<string, number>;
  /** Die Grenzen fuer heute, wenn heute zu den Tagen gehoert. */
  today: DayLimitsV2 | null;
  /** Der Tag vor dem Plan war hart: der erste Tag darf es nicht sein. */
  hardBefore: boolean;
}

export function weekLimitsV2(snapshot: SnapshotV2, context: WeekContextV2): WeekLimitsV2 {
  const first = context.dates[0] ?? context.today;
  const hardDaysAgo = snapshot.load.days_since_last_hard_session;
  return {
    sports: new Map(plannedSports(snapshot).map((sport) => [sport.id, sportLimits(snapshot, sport)])),
    maxHardDays: MULTI_RULES.maxHardDaysPerWeek,
    maxTrainingDays: trainingDaysPerWeek(snapshot),
    maxMinutes: weeklyMinutes(snapshot),
    maxDayMinutes: dayMinutesCap(snapshot),
    dayMinutes: new Map(context.dates.map((date) => [date, dayMinutesCap(snapshot, date)])),
    today: context.dates.includes(context.today) ? dayLimits(snapshot, context.today, context.recent) : null,
    hardBefore: hardOn(context.recent, addDays(first, -1)) || (first === context.today && hardDaysAgo === 1)
  };
}

interface Draft {
  sport: SportDefinition;
  limits: SportLimitsNow;
  session_type: SessionType;
  intensity: Intensity;
  amount: number;
  focus: string;
  testId: string | null;
  test: TestPlan | null;
}

interface DraftDay {
  date: string;
  focus: string;
  sessions: Draft[];
}

function label(date: string): string {
  return `${weekdayName(date)}, ${date.slice(8, 10)}.${date.slice(5, 7)}.`;
}

function minutesOf(draft: Draft): number {
  return draft.test?.minutes ?? amountToMinutes(draft.sport, draft.amount, draft.limits.speed);
}

const isHard = (draft: Draft) => draft.intensity === "hard";

/** Aus einem Test (oder einer harten Einheit) wird eine normale Einheit mit hoechstens `max`. */
/** Schwerpunkt einer Einheit und eines Tages, wenn ein Leistungstest zur lockeren Einheit wird. */
const EASY_INSTEAD_OF_TEST = "Locker statt Leistungstest";

function soften(draft: Draft, max: Intensity): Draft {
  const harsh = draft.session_type === "intervals" || draft.session_type === "threshold" || draft.session_type === "test";
  const focus = draft.session_type === "test" ? EASY_INSTEAD_OF_TEST : draft.focus;
  return { ...draft, session_type: harsh ? "endurance" : draft.session_type, intensity: lower(draft.intensity, max), test: null, testId: null, focus };
}

/** Der Schwerpunkt eines Tages, der einen Test ankuendigte, den es nicht mehr gibt. */
function focusWithoutTest(focus: string, sessions: readonly Draft[]): string {
  return /test/i.test(focus) && !sessions.some((draft) => draft.session_type === "test") ? EASY_INSTEAD_OF_TEST : focus;
}

export function sanitizeWeekV2(input: MultiWeekPlanRaw, snapshot: SnapshotV2, context: WeekContextV2): WeekSanityResultV2 {
  const problem = findProblem(input);
  if (problem !== null) return { plan: { rationale: input.rationale, total_minutes: 0, days: [] }, adjustments: [], blocked: problem };

  const notes: string[] = [];
  const week = weekLimitsV2(snapshot, context);
  const unplanned = new Set<string>();

  // 1. Genau die angefragten Tage, jeder einmal.
  const byDate = new Map<string, MultiWeekPlanRaw["days"][number]>();
  for (const day of input.days) if (context.dates.includes(day.date) && !byDate.has(day.date)) byDate.set(day.date, day);
  const missing = context.dates.filter((date) => !byDate.has(date));
  if (missing.length > 0) notes.push(`${missing.length} fehlende Tage als Ruhetag ergänzt (${missing.map(label).join(", ")})`);

  let days: DraftDay[] = context.dates.map((date) => {
    const raw = byDate.get(date);
    const focus = raw?.focus.trim().slice(0, MULTI_RULES.maxFocusLength) ?? "";
    let sessions = (raw?.sessions ?? []).flatMap((session) => toDraft(session, week, unplanned));
    // 2. Keine Zeit oder Ruhetag laut Wochenraster: Ruhetag. An einem Tag mit fester Sportart nur diese.
    if (context.unavailable.includes(date)) {
      if (sessions.length > 0) notes.push(`${label(date)}: keine Zeit, als Ruhetag gesetzt`);
      return { date, focus: "Keine Zeit", sessions: [] };
    }
    if (scheduleDay(snapshot, date)?.trains === false) {
      if (sessions.length > 0) notes.push(`${label(date)}: Ruhetag laut Wochenraster`);
      return { date, focus: "Ruhetag", sessions: [] };
    }
    const fixed = fixedSport(snapshot, date);
    if (fixed !== undefined && sessions.some((draft) => draft.sport.id !== fixed)) {
      notes.push(`${label(date)}: laut Wochenraster nur ${sportName(fixed)}, andere Sportarten gestrichen`);
      sessions = sessions.filter((draft) => draft.sport.id === fixed);
    }
    // 3. Hoechstens zwei Einheiten am Tag, die laengsten bleiben.
    if (sessions.length > MULTI_RULES.maxSessionsPerDay) {
      notes.push(`${label(date)}: auf ${MULTI_RULES.maxSessionsPerDay} Einheiten gekürzt`);
      const keep = [...sessions].sort((a, b) => minutesOf(b) - minutesOf(a)).slice(0, MULTI_RULES.maxSessionsPerDay);
      sessions = sessions.filter((session) => keep.includes(session));
    }
    return { date, focus, sessions };
  });
  if (unplanned.size > 0) notes.push(`Einheiten von Sportarten ohne Schwerpunkt entfernt (${[...unplanned].map(sportName).join(", ")})`);

  // 4. Je Einheit: Grenze der Sportart, Wiedereinstieg locker, kleinste sinnvolle Einheit.
  days = days.map((day) => ({ ...day, sessions: day.sessions.flatMap((draft) => limitSession(draft, day.date, notes)) }));

  // 5. Leistungstests (fuer heute mit den Grenzen von heute), danach die Grenzen fuer heute fuer alle anderen Einheiten.
  days = placeTests(days, snapshot, context, week, notes);
  const today = week.today;
  if (today !== null) days = days.map((day) => (day.date === context.today ? applyToday(day, today, notes) : day));

  // 6. Jeder Tag hoechstens die Tagesgrenze (eine Testeinheit bleibt ganz).
  days = days.map((day) => {
    const cap = day.date === context.today && today !== null ? today.maxMinutes : (week.dayMinutes.get(day.date) ?? week.maxDayMinutes);
    if (dayMinutes(day) <= cap) return day;
    notes.push(`${label(day.date)}: Tagesumfang von ${Math.round(dayMinutes(day))} min auf höchstens ${cap} min gekürzt`);
    return scaleSessions([day], () => true, cap, minutesOf)[0];
  });

  // 7. Hoechstens eine harte Einheit am Tag (ein Test geht vor), hoechstens zwei harte Tage, nie hintereinander.
  days = days.map((day) => {
    const hard = day.sessions.filter(isHard);
    if (hard.length <= MULTI_RULES.maxHardSessionsPerDay) return day;
    const keep = hard.find((draft) => draft.test !== null) ?? hard[0];
    notes.push(`${label(day.date)}: nur eine harte Einheit am Tag, die anderen auf "moderate" gesenkt`);
    return { ...day, sessions: day.sessions.map((draft) => (isHard(draft) && draft !== keep ? soften(draft, "moderate") : draft)) };
  });
  days = limitHardDays(days, week, notes);

  // 8. Je Sportart: Zahl der Einheiten und Wochengrenze.
  for (const [sportId, limits] of week.sports) {
    const max = limits.sport.planning.limits.maxSessionsPerWeek;
    for (;;) {
      const own = days.flatMap((day) => day.sessions.filter((draft) => draft.sport.id === sportId).map((draft) => ({ day, draft })));
      if (own.length <= max) break;
      const smallest = [...own].sort((a, b) => Number(a.draft.test !== null) - Number(b.draft.test !== null) || a.draft.amount - b.draft.amount)[0];
      notes.push(`${label(smallest.day.date)}: ${limits.sport.displayName} gestrichen (höchstens ${max} Einheiten pro Woche)`);
      days = days.map((day) => (day === smallest.day ? { ...day, sessions: day.sessions.filter((draft) => draft !== smallest.draft) } : day));
    }
    const total = days.reduce((sum, day) => sum + day.sessions.filter((draft) => draft.sport.id === sportId).reduce((s, draft) => s + draft.amount, 0), 0);
    if (total > limits.weeklyCap) {
      notes.push(`${limits.sport.displayName}: Wochenumfang von ${formatAmount(limits.sport, total)} auf höchstens ${formatAmount(limits.sport, limits.weeklyCap)} gekürzt`);
      days = scaleSessions(days, (draft) => draft.sport.id === sportId, limits.weeklyCap, (draft) => draft.amount);
    }
  }

  // 9. Nicht mehr Trainingstage als im Ziel, und in einer vollen Woche mindestens ein Ruhetag.
  const maxDays = Math.min(week.maxTrainingDays, context.dates.length >= 6 ? context.dates.length - 1 : context.dates.length);
  for (;;) {
    const training = days.filter((day) => day.sessions.length > 0);
    if (training.length <= maxDays) break;
    const lightest = [...training].sort(
      (a, b) => Number(a.sessions.some((d) => d.test !== null)) - Number(b.sessions.some((d) => d.test !== null)) || dayMinutes(a) - dayMinutes(b) || b.date.localeCompare(a.date)
    )[0];
    notes.push(`${label(lightest.date)}: als Ruhetag gesetzt (${training.length > week.maxTrainingDays ? `höchstens ${week.maxTrainingDays} Trainingstage` : "mindestens ein Ruhetag pro Woche"})`);
    days = days.map((day) => (day === lightest ? { ...day, focus: "Ruhetag", sessions: [] } : day));
  }

  // 10. Hoechstens die Wochenstunden des Ziels.
  const minutes = days.reduce((sum, day) => sum + dayMinutes(day), 0);
  if (minutes > week.maxMinutes) {
    notes.push(`Gesamtumfang von ${Math.round(minutes)} min auf höchstens ${week.maxMinutes} min gekürzt (Wochenstunden des Ziels)`);
    days = scaleSessions(days, () => true, week.maxMinutes, minutesOf);
  }

  const result = days.map(finalizeDay);
  const adjustments = notes.slice(0, MULTI_RULES.maxAdjustmentLines);
  if (notes.length > MULTI_RULES.maxAdjustmentLines) adjustments.push(`… und ${notes.length - MULTI_RULES.maxAdjustmentLines} weitere Korrekturen`);
  return {
    plan: {
      rationale: withNote(input.rationale, notes),
      total_minutes: result.reduce((sum, day) => sum + day.sessions.reduce((s, session) => s + session.minutes, 0), 0),
      days: result
    },
    adjustments,
    blocked: null
  };
}

// --- Bausteine ---

function findProblem(input: MultiWeekPlanRaw): string | null {
  if (input.rationale.trim() === "") return "Begründung fehlt";
  if (input.days.length === 0) return "Wochenplan ohne Tage";
  if (input.days.length > 14) return `zu viele Tage (${input.days.length})`;
  for (const day of input.days) {
    if (day.sessions.length > 6) return "zu viele Einheiten an einem Tag";
    for (const session of day.sessions) {
      if (!Number.isFinite(session.amount)) return "Zahlenwert in einer Einheit ungültig";
    }
  }
  return null;
}

function toDraft(session: WeekSessionRaw, week: WeekLimitsV2, unplanned: Set<string>): Draft[] {
  const limits = week.sports.get(session.sport);
  if (limits === undefined) {
    unplanned.add(session.sport);
    return [];
  }
  const isTest = session.session_type === "test" || (session.test_id ?? null) !== null;
  if (!isTest && (session.session_type === "rest" || session.intensity === "rest" || session.amount <= 0)) return [];
  const sport = limits.sport;
  return [
    {
      sport,
      limits,
      session_type: isTest ? "test" : session.session_type,
      intensity: session.intensity === "rest" ? "easy" : session.intensity,
      amount: roundAmount(sport, Math.max(session.amount, 0)),
      focus: session.focus.trim().slice(0, MULTI_RULES.maxFocusLength) || sport.displayName,
      testId: isTest ? (session.test_id ?? null) : null,
      test: null
    }
  ];
}

function limitSession(draft: Draft, date: string, notes: string[]): Draft[] {
  const { sport, limits } = draft;
  const minimum = sport.planning.limits.minSession;
  if (draft.session_type === "test") return [draft];
  let result = draft;
  if (limits.pause && RANK[result.intensity] > RANK.easy) {
    notes.push(`${label(date)}: ${sport.displayName} locker (Wiedereinstieg nach Pause)`);
    result = soften(result, "easy");
  }
  if (result.amount > limits.sessionCap) {
    notes.push(`${label(date)}: ${sport.displayName} von ${formatAmount(sport, result.amount)} auf ${formatAmount(sport, limits.sessionCap)} gekürzt (Grenze pro Einheit)`);
    result = { ...result, amount: limits.sessionCap };
  }
  if (result.amount < minimum) {
    if (result.amount * 2 >= minimum && minimum <= limits.sessionCap) {
      notes.push(`${label(date)}: ${sport.displayName} von ${formatAmount(sport, result.amount)} auf ${formatAmount(sport, minimum)} angehoben (kleinste sinnvolle Einheit)`);
      return [{ ...result, amount: minimum }];
    }
    notes.push(`${label(date)}: ${sport.displayName} unter ${formatAmount(sport, minimum)} gestrichen`);
    return [];
  }
  return [result];
}

/**
 * Hoechstens `maxHardDays` harte Tage, nie zwei hintereinander, auch nicht direkt nach einem harten Tag vor dem Plan.
 * Tage mit einem Test kommen zuerst zum Zug, dann die uebrigen in der Reihenfolge der Tage. Was nicht passt, wird
 * leichter: ein Test zur lockeren Einheit, eine harte Einheit "moderate".
 */
function limitHardDays(days: DraftDay[], week: WeekLimitsV2, notes: string[]): DraftDay[] {
  const result = [...days];
  const hard = new Set<number>();
  const neighbourHard = (index: number) => (index === 0 ? week.hardBefore : hard.has(index - 1)) || hard.has(index + 1);
  for (const testsFirst of [true, false]) {
    result.forEach((day, index) => {
      const session = day.sessions.find(isHard);
      if (session === undefined || (session.test !== null) !== testsFirst) return;
      const neighbour = neighbourHard(index);
      if (!neighbour && hard.size < week.maxHardDays) {
        hard.add(index);
        return;
      }
      const why = neighbour ? "nicht an zwei Tagen nacheinander" : `höchstens ${week.maxHardDays} harte Tage`;
      notes.push(
        session.test !== null
          ? `${label(day.date)}: kein Leistungstest ${session.sport.displayName} (${why}), lockere Einheit statt dessen`
          : `${label(day.date)}: harte Einheit auf "moderate" gesenkt (${why})`
      );
      const sessions = day.sessions.map((draft) => (isHard(draft) ? soften(draft, draft.test !== null ? "easy" : "moderate") : draft));
      result[index] = { ...day, focus: focusWithoutTest(day.focus, sessions), sessions };
    });
  }
  return result;
}

function applyToday(day: DraftDay, today: DayLimitsV2, notes: string[]): DraftDay {
  if (today.restReason !== null) {
    if (day.sessions.length > 0) notes.push(`${label(day.date)}: Ruhetag erzwungen (${today.restReason})`);
    return { ...day, focus: "Ruhetag", sessions: [] };
  }
  const sessions = day.sessions.flatMap((draft) => {
    const limits = today.sports.get(draft.sport.id);
    if (limits === undefined) return [];
    if (limits.blockedReason !== null) {
      notes.push(`${label(day.date)}: ${draft.sport.displayName} gestrichen (${limits.blockedReason})`);
      return [];
    }
    let result = draft;
    if (RANK[result.intensity] > RANK[limits.maxIntensity] && result.session_type !== "test") {
      notes.push(`${label(day.date)}: ${draft.sport.displayName} auf "${limits.maxIntensity}" gesenkt (${limits.intensityReasons.join(", ")})`);
      result = soften(result, limits.maxIntensity);
    }
    if (result.amount > limits.maxAmount && result.session_type !== "test") {
      notes.push(`${label(day.date)}: ${draft.sport.displayName} von ${formatAmount(draft.sport, result.amount)} auf ${formatAmount(draft.sport, limits.maxAmount)} gekürzt (Grenze für heute)`);
      result = { ...result, amount: limits.maxAmount };
    }
    return [result];
  });
  return { ...day, sessions };
}

/** Setzt die Testeinheiten ein oder macht aus einem unpassenden Test eine normale Einheit. */
function placeTests(days: DraftDay[], snapshot: SnapshotV2, context: WeekContextV2, week: WeekLimitsV2, notes: string[]): DraftDay[] {
  let previousTestDay: string | null = null;
  const testedSports = new Set<string>();
  // Tests werden nie gekuerzt: zusammen passen sie in die Wochenstunden.
  let testMinutes = 0;
  return days.map((day) => {
    let testToday = false;
    const sessions = day.sessions.map((draft) => {
      if (draft.session_type !== "test") return draft;
      const isToday = day.date === context.today && week.today !== null;
      const dayLimitsForSport = isToday ? week.today?.sports.get(draft.sport.id) : undefined;
      const blocked =
        (context.testSettings?.offer === false ? "Leistungstests sind abgeschaltet" : null) ??
        testBlackoutReason(snapshot, day.date) ??
        (isToday ? (week.today?.testBlockedReason ?? null) : null) ??
        (testToday ? "höchstens ein Test pro Tag" : null) ??
        (testedSports.has(draft.sport.id) ? "höchstens ein Test je Sportart pro Woche" : null) ??
        (previousTestDay !== null && previousTestDay === addDays(day.date, -1) ? "nicht an zwei Tagen nacheinander" : null);
      let test: TestPlan | null = null;
      let reason = blocked;
      if (blocked === null) {
        const chosen = chooseTest(draft.limits, {
          requested: draft.testId,
          settings: context.testSettings,
          maxAmount: Math.min(draft.limits.sessionCap, draft.limits.weeklyCap, dayLimitsForSport?.maxAmount ?? Infinity),
          maxMinutes: Math.min(isToday && week.today !== null ? week.today.maxMinutes : (week.dayMinutes.get(day.date) ?? week.maxDayMinutes), week.maxMinutes - testMinutes),
          maxIntensity: dayLimitsForSport?.maxIntensity ?? (draft.limits.pause ? "easy" : "hard"),
          intensityReason: dayLimitsForSport?.intensityReasons.join(", ") ?? "Wiedereinstieg nach Pause"
        });
        test = chosen.plan;
        reason = chosen.reason;
      }
      if (test === null) {
        notes.push(`${label(day.date)}: kein Leistungstest ${draft.sport.displayName} (${reason ?? "passt nicht"}), lockere Einheit statt dessen`);
        const fallback = soften(draft, "easy");
        return { ...fallback, amount: Math.min(fallback.amount, floorAmount(draft.sport, draft.limits.sessionCap)) };
      }
      testToday = true;
      testedSports.add(draft.sport.id);
      testMinutes += test.minutes;
      return { ...draft, session_type: "test" as const, intensity: test.intensity, amount: Math.round(test.amount), testId: test.test.id, test, focus: test.test.displayName };
    });
    if (testToday) previousTestDay = day.date;
    const kept = sessions.filter((draft) => draft.amount >= draft.sport.planning.limits.minSession || draft.test !== null);
    return { ...day, focus: focusWithoutTest(day.focus, kept), sessions: kept };
  });
}

function dayMinutes(day: DraftDay): number {
  return day.sessions.reduce((sum, draft) => sum + minutesOf(draft), 0);
}

/** Kuerzt die passenden Einheiten (ohne Tests) anteilig, bis `measure` ueber alle Tage hoechstens `cap` ergibt. */
function scaleSessions(days: DraftDay[], matches: (draft: Draft) => boolean, cap: number, measure: (draft: Draft) => number): DraftDay[] {
  const all = days.flatMap((day) => day.sessions.filter(matches));
  const fixed = all.filter((draft) => draft.test !== null).reduce((sum, draft) => sum + measure(draft), 0);
  const flexible = all.filter((draft) => draft.test === null).reduce((sum, draft) => sum + measure(draft), 0);
  const factor = flexible > 0 ? Math.max(cap - fixed, 0) / flexible : 1;
  if (factor >= 1) return days;
  return days.map((day) => ({
    ...day,
    sessions: day.sessions.flatMap((draft) => {
      if (!matches(draft) || draft.test !== null) return [draft];
      const amount = floorAmount(draft.sport, draft.amount * factor);
      return amount >= draft.sport.planning.limits.minSession ? [{ ...draft, amount }] : [];
    })
  }));
}

function finalizeDay(day: DraftDay): WeekDayV2 {
  const sessions = day.sessions.map(
    (draft): WeekSessionV2 => ({
      sport: draft.sport.id,
      session_type: draft.session_type,
      intensity: draft.intensity,
      amount: draft.amount,
      unit: draft.sport.planning.limitUnit,
      minutes: Math.round(minutesOf(draft)),
      distance_meters: Math.round((draft.test?.meters ?? amountToMeters(draft.sport, draft.amount, draft.limits.speed)) / 50) * 50,
      focus: draft.focus,
      test: draft.test === null ? null : testRef(draft.test.test)
    })
  );
  const focus = day.focus !== "" && (sessions.length > 0 || day.focus === "Keine Zeit") ? day.focus : sessions.length > 0 ? sessions.map((session) => session.focus).join(" + ").slice(0, MULTI_RULES.maxFocusLength) : "Ruhetag";
  return { date: day.date, focus, sessions };
}

export function withNote(rationale: string, notes: string[]): string {
  const text = rationale.trim().slice(0, MULTI_RULES.maxRationaleLength);
  if (notes.length === 0) return text;
  const note = `Hinweis: Zur Sicherheit angepasst (${notes.slice(0, 3).join("; ")}${notes.length > 3 ? `; und ${notes.length - 3} weitere` : ""}).`;
  const room = Math.max(MULTI_RULES.maxRationaleLength - note.length - 1, 0);
  return `${text.slice(0, room).trimEnd()} ${note}`.trim().slice(0, MULTI_RULES.maxRationaleLength);
}
