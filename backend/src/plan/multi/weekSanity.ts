import { LimitUnit, SportDefinition } from "../../sports/types";
import { Intensity, SessionType } from "../vocabulary";
import { SnapshotV2 } from "../snapshot";
import { addDays, weekdayName } from "../calendar";
import { dayLimits, DayLimitsV2, dayMinutesCap, hardOn, lower, MULTI_RULES, painRestriction, RANK, recentBefore, sportLimits, SportLimitsNow, testBlackoutReason } from "./limits";
import { Availability, FixedDay, MacroWeekTargetV2, MissedSession, MultiWeekPlanRaw, RecentTraining, ReplanReason, Supplements, TestSettings, WeekSessionRaw } from "./schemas";
import { DayWeather, severeWeather } from "../weather";
import { EXERCISE_RULES, EXTRA_RULES, normalizeWeekExtras, perWeek, strengthBlackout, WeekExtra } from "./extras";
import { amountToMeters, amountToMinutes, floorAmount, formatAmount, plannedSports, roundAmount, sportName } from "./sports";
import { fixedSport, scheduleDay, trainingDaysPerWeek, weeklyMinutes } from "./schedule";
import { chooseTest, TestPlan, TestRef, testRef } from "./tests";
import { inOpenWaterBlock, openWaterAllowed, openWaterBlocked, raceInOpenWater } from "./openWater";

/**
 * Sicherheitsschicht fuer den Wochenplan ueber mehrere Sportarten (die naechsten 7 oder 14 Tage, je Block von 7 Tagen). Reiner Code: korrigiert
 * deterministisch oder blockt. Regeln (docs/multisport-planning.md): genau die angefragten Tage; keine Zeit heisst
 * Ruhetag; hoechstens zwei Einheiten und eine harte je Tag; je Sportart Einheitengrenze, Wochengrenze und Zahl der
 * Einheiten; die Grenzen fuer heute; hoechstens zwei harte Tage ueber alle Sportarten, nie hintereinander (auch nicht
 * nach einem harten Tag vor dem Plan, Tests mit Vollbelastung zaehlen als harter Tag und gehen vor); Leistungstests nur,
 * wenn sie passen, hoechstens einer je Tag und je Sportart, nie an zwei Tagen hintereinander; jeder Tag hoechstens die
 * Haelfte der Wochenstunden (mit Wochenraster: dessen Minuten); Ruhetage und feste Sportarten des Wochenrasters; nicht
 * mehr Trainingstage als im Ziel; mindestens ein Ruhetag; hoechstens die Wochenstunden; etwa 80 % der Zeit locker.
 */
export interface WeekContextV2 {
  today: string;
  /** Die geplanten Tage ab `from_date` (7 oder 14), aufsteigend; die Wochengrenzen gelten je Block von 7 Tagen. */
  dates: string[];
  unavailable: string[];
  /**
   * Feste Tage (vom Athleten geaendert oder heute schon geplant): Sie bleiben genau so, zaehlen aber fuer die Grenzen der
   * Woche (Umfang, Einheiten, Trainingstage, harte Tage). Claude plant die anderen Tage um sie herum.
   */
  fixed?: FixedDay[];
  /** Training vor dem ersten geplanten Tag (Information fuer Claude, harte Einheiten zaehlen fuer "nie hintereinander"). */
  recent: RecentTraining[];
  /**
   * Rueckmeldungen mit Beschwerden, auch von heute (vom ersten geplanten Tag): Sie bremsen die Sportart fuer einige Tage
   * (`painRestriction`). Fehlt das Feld, gelten die Beschwerden aus `recent`.
   */
  reports?: RecentTraining[];
  /** Geplante Einheiten der letzten Tage, die ausgefallen sind (Information fuer Claude). */
  missed?: MissedSession[];
  /** Anlass der Neuplanung. */
  reason?: ReplanReason;
  /** Das Equipment des Athleten (fuer drinnen: Rolle, Laufband); fehlt die Angabe, ist alles erlaubt. */
  equipment?: readonly string[];
  /** Freie Minuten je Tag laut Kalender. */
  availability?: Availability[];
  /** Wettervorhersage je Tag. */
  weather?: DayWeather[];
  /** Wie oft pro Woche Kraft und Mobilitaet dazukommen. */
  supplements?: Supplements;
  macroWeeks?: MacroWeekTargetV2[];
  testSettings?: TestSettings;
  /** Tests, die schon vor diesen Tagen geplant sind (im Block davor): kein zweiter derselben Sportart, keiner am Tag danach. */
  priorTests?: { date: string; sport: string }[];
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
  /** Schliesst direkt an die erste Einheit des Tages an (Koppeltraining). */
  brick: boolean;
  /** Drinnen (Rolle, Laufband). */
  indoor: boolean;
  /** Im Freiwasser (See, Meer) statt im Becken. */
  open_water: boolean;
}

export interface WeekDayV2 {
  date: string;
  focus: string;
  sessions: WeekSessionV2[];
  /** Kraft- und Mobilitaetsbloecke. */
  extras: WeekExtra[];
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
  brick: boolean;
  indoor: boolean;
  openWater: boolean;
}

interface DraftDay {
  date: string;
  focus: string;
  sessions: Draft[];
  extras: WeekExtra[];
}

/** Weniger freie Zeit laut Kalender: der Tag gilt als "keine Zeit". */
export const MIN_FREE_MINUTES = 20;

/** Drinnen moeglich: Die Sportart kennt drinnen und der Athlet hat das Hilfsmittel (ohne Angabe: alles erlaubt). */
export function indoorAllowed(sport: SportDefinition, equipment: readonly string[] | undefined): boolean {
  const indoor = sport.planning.indoor;
  return indoor !== null && (equipment === undefined || equipment.includes(indoor.equipment));
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

/** So viele Tage hat ein Block, fuer den die Wochengrenzen gelten (Umfang, Einheiten, Trainingstage, harte Tage, Ruhetag). */
export const WEEK_BLOCK_DAYS = 7;

/**
 * Prueft den Plan Block fuer Block (je `WEEK_BLOCK_DAYS` Tage, bei 14 Tagen also zwei): Jeder Block bekommt die
 * Wochengrenzen, und was der Block davor plant, zaehlt fuer den naechsten wie Training vor dem Plan (die Spanne von
 * 7 Tagen ueber die Blockgrenze, harte Tage nie hintereinander, kein zweiter Test derselben Sportart).
 */
export function sanitizeWeekV2(input: MultiWeekPlanRaw, snapshot: SnapshotV2, context: WeekContextV2): WeekSanityResultV2 {
  const problem = findProblem(input, context.dates.length);
  if (problem !== null) return { plan: { rationale: input.rationale, total_minutes: 0, days: [] }, adjustments: [], blocked: problem };

  const notes: string[] = [];
  const result: WeekDayV2[] = [];
  const reports = context.reports ?? context.recent;
  let recent = context.recent;
  let priorTests = context.priorTests ?? [];
  for (let start = 0; start < context.dates.length; start += WEEK_BLOCK_DAYS) {
    const dates = context.dates.slice(start, start + WEEK_BLOCK_DAYS);
    const block = sanitizeBlock(input, snapshot, { ...context, dates, recent, reports, priorTests }, notes);
    result.push(...block);
    recent = [...recent, ...block.flatMap(plannedAsRecent)];
    priorTests = [...priorTests, ...block.flatMap((day) => day.sessions.filter((session) => session.test !== null).map((session) => ({ date: day.date, sport: session.sport })))];
  }

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

/** Ein geplanter Tag als Training vor dem naechsten Block (fuer die 7-Tage-Spanne und "nie zwei harte Tage hintereinander"). */
function plannedAsRecent(day: WeekDayV2): RecentTraining[] {
  return day.sessions.map((session) => ({
    date: day.date,
    sport: session.sport,
    minutes: session.minutes,
    meters: session.distance_meters,
    hard: session.intensity === "hard"
  }));
}

/** Die Regeln fuer einen Block von hoechstens `WEEK_BLOCK_DAYS` Tagen; Korrekturen landen in `notes`. */
function sanitizeBlock(input: MultiWeekPlanRaw, snapshot: SnapshotV2, context: WeekContextV2, notes: string[]): WeekDayV2[] {
  const unplanned = new Set<string>();
  // Feste Tage: stehen schon, ihr Umfang geht von den Grenzen der Woche ab.
  const base = weekLimitsV2(snapshot, context);
  const pinned = fixedDays(context, base);
  const week = reserveFixed(base, pinned);

  // 1. Genau die angefragten Tage, jeder einmal.
  const byDate = new Map<string, MultiWeekPlanRaw["days"][number]>();
  for (const day of input.days) if (context.dates.includes(day.date) && !byDate.has(day.date)) byDate.set(day.date, day);
  const missing = context.dates.filter((date) => !byDate.has(date));
  if (missing.length > 0) notes.push(`${missing.length} fehlende Tage als Ruhetag ergänzt (${missing.map(label).join(", ")})`);

  const free = new Map((context.availability ?? []).map((entry) => [entry.date, entry.minutes]));
  let days: DraftDay[] = context.dates.map((date) => {
    const raw = byDate.get(date);
    const focus = raw?.focus.trim().slice(0, MULTI_RULES.maxFocusLength) ?? "";
    let sessions = (raw?.sessions ?? []).flatMap((session) => toDraft(session, week, unplanned));
    const extras = normalizeWeekExtras(raw?.extras, context.supplements);
    // Ein fester Tag ist fuer die Pruefung leer; seine Einheiten kommen am Ende zurueck.
    if (pinned.has(date)) return { date, focus: "", sessions: [], extras: [] };
    // 2. Keine Zeit (auch laut Kalender) oder Ruhetag laut Wochenraster: Ruhetag. An einem Tag mit fester Sportart nur diese.
    if (context.unavailable.includes(date)) {
      if (sessions.length > 0) notes.push(`${label(date)}: keine Zeit, als Ruhetag gesetzt`);
      return { date, focus: "Keine Zeit", sessions: [], extras: [] };
    }
    const freeMinutes = free.get(date);
    if (freeMinutes !== undefined && freeMinutes < MIN_FREE_MINUTES) {
      if (sessions.length > 0 || extras.length > 0) notes.push(`${label(date)}: laut Kalender keine Zeit, als Ruhetag gesetzt`);
      return { date, focus: "Keine Zeit", sessions: [], extras: [] };
    }
    if (scheduleDay(snapshot, date)?.trains === false) {
      if (sessions.length > 0) notes.push(`${label(date)}: Ruhetag laut Wochenraster`);
      return { date, focus: "Ruhetag", sessions: [], extras: extras.filter((extra) => extra.kind === "mobility") };
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
    return { date, focus, sessions: fixBricks(sessions, date, notes), extras };
  });
  if (unplanned.size > 0) notes.push(`Einheiten von Sportarten ohne Schwerpunkt entfernt (${[...unplanned].map(sportName).join(", ")})`);

  // 4. Je Einheit: Beschwerden der letzten Tage, Grenze der Sportart, Wiedereinstieg locker, kleinste sinnvolle Einheit.
  const reports = context.reports ?? context.recent;
  days = days.map((day) => ({
    ...day,
    sessions: fixBricks(
      day.sessions
        .flatMap((draft) => applyPain(draft, day.date, reports, notes))
        .flatMap((draft) => limitSession(draft, day.date, notes))
        .map((draft) => placeIndoor(draft, day.date, context, notes))
        .map((draft) => placeOpenWater(draft, day.date, context, notes)),
      day.date,
      []
    )
  }));

  // 5. Leistungstests (fuer heute mit den Grenzen von heute), danach die Grenzen fuer heute fuer alle anderen Einheiten.
  days = placeTests(days, snapshot, context, week, notes);
  const today = week.today;
  if (today !== null) days = days.map((day) => (day.date === context.today ? applyToday(day, today, notes) : day));

  // 6. Jeder Tag hoechstens die Tagesgrenze (eine Testeinheit bleibt ganz).
  days = days.map((day) => {
    const ruleCap = day.date === context.today && today !== null ? today.maxMinutes : (week.dayMinutes.get(day.date) ?? week.maxDayMinutes);
    const cap = Math.min(ruleCap, free.get(day.date) ?? Infinity);
    if (dayMinutes(day) <= cap) return day;
    notes.push(`${label(day.date)}: Tagesumfang von ${Math.round(dayMinutes(day))} min auf höchstens ${cap} min gekürzt${cap < ruleCap ? " (freie Zeit laut Kalender)" : ""}`);
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
  days = limitHardDays(days, week, notes, new Set([...pinned.values()].filter((day) => day.sessions.some(isHard)).map((day) => day.date)));

  // 8. Je Sportart: Zahl der Einheiten und Wochengrenze.
  for (const [sportId, limits] of week.sports) {
    const max = Math.max(limits.sport.planning.limits.maxSessionsPerWeek - fixedCount(pinned, sportId), 0);
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

  // 8b. Jede Spanne von 7 Tagen, auch ueber den Planbeginn: das Training davor zaehlt mit (wie im Tagesplan am Tag selbst).
  days = limitRollingWindow(days, base, pinned, snapshot, context, free, notes);

  // 9. Nicht mehr Trainingstage als im Ziel, und in einer vollen Woche mindestens ein Ruhetag.
  const fixedTraining = [...pinned.values()].filter((day) => day.sessions.length > 0).length;
  const maxDays = Math.max(Math.min(week.maxTrainingDays, context.dates.length >= 6 ? context.dates.length - 1 : context.dates.length) - fixedTraining, 0);
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

  // 11. Etwa 80 % locker: zu viel Intensitaet senkt mittlere Einheiten auf locker, die laengsten zuerst.
  days = limitIntensity(days, notes);

  // 12. Ziel im Freiwasser: in den letzten Wochen davor mindestens eine Freiwasser-Einheit (wenn Zugang und Wetter passen).
  days = ensureOpenWater(days, snapshot, context, notes);

  // 13. Kraft und Mobilitaet: so oft wie gewuenscht, Kraft nicht vor einem harten Tag und nicht kurz vor dem Ziel, in der Tageszeit.
  days = placeExtras(days, snapshot, context, week, free, notes);

  // 14. Die festen Tage zurueck, wie der Athlet sie festgelegt hat.
  days = days.map((day) => pinned.get(day.date) ?? day);

  return days.map(finalizeDay);
}

// --- Bausteine ---

function findProblem(input: MultiWeekPlanRaw, requested: number): string | null {
  if (input.rationale.trim() === "") return "Begründung fehlt";
  if (input.days.length === 0) return "Wochenplan ohne Tage";
  if (input.days.length > Math.max(requested, WEEK_BLOCK_DAYS) * 2) return `zu viele Tage (${input.days.length})`;
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
      test: null,
      brick: session.brick === true,
      indoor: session.indoor === true,
      openWater: session.open_water === true && !isTest
    }
  ];
}

/** Beschwerden nach einer Einheit: Sportart pausiert, nur locker oder kuerzer (siehe `painRestriction`). */
function applyPain(draft: Draft, date: string, reports: readonly RecentTraining[], notes: string[]): Draft[] {
  const pain = painRestriction(reports, draft.sport.id, date);
  if (pain === null) return [draft];
  const sport = draft.sport;
  if (pain.blocked) {
    notes.push(`${label(date)}: ${sport.displayName} gestrichen (${pain.reason})`);
    return [];
  }
  let result = draft;
  if (RANK[result.intensity] > RANK[pain.maxIntensity]) {
    notes.push(`${label(date)}: ${sport.displayName} auf "${pain.maxIntensity}" gesenkt (${pain.reason})`);
    result = soften(result, pain.maxIntensity);
  }
  if (pain.amountFactor < 1 && result.test === null) {
    const cap = floorAmount(sport, draft.limits.sessionCap * pain.amountFactor);
    if (result.amount > cap) {
      notes.push(`${label(date)}: ${sport.displayName} von ${formatAmount(sport, result.amount)} auf ${formatAmount(sport, cap)} gekürzt (${pain.reason})`);
      result = { ...result, amount: cap };
    }
  }
  return [result];
}

/**
 * Koppeltraining nur fuer die zweite Einheit des Tages und nur direkt nach einer Sportart, nach der die Sportart das
 * erlaubt (`brickAfter`). Sonst wird es eine eigene Einheit; `notes` bekommt den Hinweis (leer: still korrigieren, etwa
 * wenn die erste Einheit gestrichen wurde).
 */
function fixBricks(sessions: Draft[], date: string, notes: string[]): Draft[] {
  return sessions.map((draft, index) => {
    if (!draft.brick) return draft;
    const previous = index === 1 ? sessions[0] : undefined;
    if (previous !== undefined && draft.sport.planning.brickAfter.includes(previous.sport.id)) return draft;
    const allowed = draft.sport.planning.brickAfter.map(sportName).join(" oder ");
    notes.push(`${label(date)}: ${draft.sport.displayName} als eigene Einheit (Koppeltraining nur direkt nach ${allowed || "keiner Sportart"})`);
    return { ...draft, brick: false };
  });
}

/**
 * Drinnen nur, wo die Sportart es kennt und der Athlet das Hilfsmittel hat. Bei Gewitter, Sturm, Starkregen oder
 * Glaette kommt eine wetterabhaengige Einheit nach drinnen, wenn das geht.
 */
function placeIndoor(draft: Draft, date: string, context: WeekContextV2, notes: string[]): Draft {
  const sport = draft.sport;
  const allowed = indoorAllowed(sport, context.equipment);
  if (draft.indoor && !allowed) {
    notes.push(`${label(date)}: ${sport.displayName} draußen (${sport.planning.indoor === null ? "drinnen gibt es nicht" : `kein ${sport.planning.indoor.displayName} angegeben`})`);
    return { ...draft, indoor: false };
  }
  const weather = context.weather?.find((day) => day.date === date);
  const severe = weather !== undefined && sport.planning.weatherSensitive ? severeWeather(weather) : null;
  if (severe !== null && !draft.indoor && allowed && sport.planning.indoor !== null) {
    notes.push(`${label(date)}: ${severe}, ${sport.displayName} drinnen (${sport.planning.indoor.displayName})`);
    return { ...draft, indoor: true };
  }
  return draft;
}

/** Freiwasser nur, wo die Sportart es kennt, der Athlet Zugang hat und das Wetter passt (sonst ins Becken). */
function placeOpenWater(draft: Draft, date: string, context: WeekContextV2, notes: string[]): Draft {
  if (!draft.openWater) return draft;
  const venue = draft.sport.planning.openWater;
  if (venue === null || !openWaterAllowed(draft.sport, context.equipment)) {
    notes.push(`${label(date)}: ${draft.sport.displayName} im Becken (${venue === null ? "Freiwasser gibt es nicht" : "kein Zugang zu Freiwasser angegeben"})`);
    return { ...draft, openWater: false };
  }
  const blocked = openWaterBlocked(context.weather?.find((day) => day.date === date));
  if (blocked !== null) {
    notes.push(`${label(date)}: ${blocked}, ${draft.sport.displayName} im Becken`);
    return { ...draft, openWater: false };
  }
  return draft;
}

/**
 * Ein Ziel im Freiwasser braucht Gewoehnung (Orientierung, Start, kein Abstossen an der Wand): Liegt die Woche in den
 * letzten Wochen davor und plant sie die Sportart ohne Freiwasser, kommt die laengste passende Einheit dorthin.
 */
function ensureOpenWater(days: DraftDay[], snapshot: SnapshotV2, context: WeekContextV2, notes: string[]): DraftDay[] {
  let result = days;
  for (const discipline of snapshot.training_goal.disciplines) {
    const own = result.flatMap((day) => day.sessions.filter((draft) => draft.sport.id === discipline.sport).map((draft) => ({ day, draft })));
    if (own.length === 0 || own.some(({ draft }) => draft.openWater)) continue;
    const sport = own[0].draft.sport;
    if (!raceInOpenWater(snapshot, sport.id) || !openWaterAllowed(sport, context.equipment)) continue;
    const candidates = own.filter(
      ({ day, draft }) => draft.test === null && inOpenWaterBlock(snapshot, day.date) && openWaterBlocked(context.weather?.find((entry) => entry.date === day.date)) === null
    );
    const chosen = [...candidates].sort((a, b) => RANK[a.draft.intensity] - RANK[b.draft.intensity] || b.draft.amount - a.draft.amount)[0];
    if (chosen === undefined) continue;
    notes.push(`${label(chosen.day.date)}: ${sport.displayName} im Freiwasser (Ziel im Freiwasser)`);
    result = result.map((day) =>
      day === chosen.day ? { ...day, sessions: day.sessions.map((draft) => (draft === chosen.draft ? { ...draft, openWater: true } : draft)) } : day
    );
  }
  return result;
}

/** Kraft und Mobilitaet nach den Regeln in `extras.ts`. */
function placeExtras(days: DraftDay[], snapshot: SnapshotV2, context: WeekContextV2, week: WeekLimitsV2, free: ReadonlyMap<string, number>, notes: string[]): DraftDay[] {
  const counts = new Map<string, number>();
  return days.map((day, index) => {
    const nextHard = days[index + 1]?.sessions.some(isHard) ?? false;
    const extras = day.extras.flatMap((extra) => {
      const name = EXTRA_RULES[extra.kind].displayName;
      if (extra.kind === "strength") {
        if (strengthBlackout(snapshot, day.date)) {
          notes.push(`${label(day.date)}: kein Krafttraining in den letzten ${EXERCISE_RULES.noStrengthDaysBeforeGoal} Tagen vor dem Ziel`);
          return [];
        }
        if (day.date === context.today && week.today?.restReason != null) {
          notes.push(`${label(day.date)}: kein Krafttraining (${week.today.restReason})`);
          return [];
        }
        if (nextHard) {
          notes.push(`${label(day.date)}: kein Krafttraining am Tag vor einer harten Einheit`);
          return [];
        }
      }
      const used = counts.get(extra.kind) ?? 0;
      if (used >= perWeek(context.supplements, extra.kind)) {
        notes.push(`${label(day.date)}: ${name} gestrichen (höchstens ${perWeek(context.supplements, extra.kind)}-mal pro Woche)`);
        return [];
      }
      counts.set(extra.kind, used + 1);
      return [extra];
    });
    // In der Tageszeit: was nicht mehr passt, faellt weg (Mobilitaet zuletzt).
    const cap = Math.min(
      day.date === context.today && week.today !== null ? week.today.maxMinutes : (week.dayMinutes.get(day.date) ?? week.maxDayMinutes),
      free.get(day.date) ?? Infinity
    );
    let room = cap - dayMinutes(day);
    const kept = [...extras]
      .sort((a, b) => (a.kind === b.kind ? 0 : a.kind === "mobility" ? -1 : 1))
      .filter((extra) => {
        if (extra.minutes <= room) {
          room -= extra.minutes;
          return true;
        }
        notes.push(`${label(day.date)}: ${EXTRA_RULES[extra.kind].displayName} gestrichen (Tageszeit ausgeschöpft)`);
        return false;
      });
    return { ...day, extras: extras.filter((extra) => kept.includes(extra)) };
  });
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
function limitHardDays(days: DraftDay[], week: WeekLimitsV2, notes: string[], fixedHard: ReadonlySet<string> = new Set()): DraftDay[] {
  const result = [...days];
  // Harte feste Tage stehen schon: Sie zaehlen mit und duerfen keine harten Nachbarn bekommen.
  const hard = new Set<number>(days.flatMap((day, index) => (fixedHard.has(day.date) ? [index] : [])));
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

/**
 * Die Wochengrenze einer Sportart gilt fuer jede Spanne von 7 Tagen: Was vor dem Plan trainiert wurde (`recent`) und was
 * die Tage davor im Plan haben (feste Tage eingeschlossen), zaehlt fuer einen Tag mit. Heute prueft `applyToday` mit den
 * Werten aus Health. Passt ein Test an seinem Tag nicht, kommt er auf einen spaeteren Tag mit einer lockeren Einheit
 * derselben Sportart (Tausch), an dem er passt; sonst wird er eine lockere Einheit. Andere Einheiten werden gekuerzt.
 */
function limitRollingWindow(
  days: DraftDay[],
  base: WeekLimitsV2,
  pinned: ReadonlyMap<string, DraftDay>,
  snapshot: SnapshotV2,
  context: WeekContextV2,
  free: ReadonlyMap<string, number>,
  notes: string[]
): DraftDay[] {
  const result = [...days];
  for (const [sportId, limits] of base.sports) {
    const sport = limits.sport;
    const own = (day: DraftDay) => day.sessions.filter((draft) => draft.sport.id === sportId);
    const amountOn = (date: string) => {
      const day = pinned.get(date) ?? result.find((entry) => entry.date === date);
      return day === undefined ? 0 : own(day).reduce((sum, draft) => sum + draft.amount, 0);
    };
    const usedBefore = (date: string) => {
      let used = recentBefore(sport, context.recent, date);
      for (let back = 1; back <= 6; back += 1) used += amountOn(addDays(date, -back));
      return used;
    };
    for (let index = 0; index < result.length; index += 1) {
      const day = result[index];
      if (day.date === context.today || pinned.has(day.date) || own(day).length === 0) continue;
      const used = usedBefore(day.date);
      const allowed = Math.max(limits.weeklyCap - used, 0);
      const why = `in 7 Tagen höchstens ${formatAmount(sport, limits.weeklyCap)}, davon schon ${formatAmount(sport, used)}`;
      const test = own(day).find((draft) => draft.test !== null);
      if (test !== undefined && test.amount > allowed) {
        const moved = moveTest(result, index, test, limits.weeklyCap, usedBefore, base, pinned, snapshot, context, free);
        if (moved !== null) {
          notes.push(`${label(day.date)}: Leistungstest ${sport.displayName} auf ${label(result[moved].date)} verlegt (${why})`);
        } else {
          notes.push(`${label(day.date)}: kein Leistungstest ${sport.displayName} (${why}), lockere Einheit statt dessen`);
          const sessions = day.sessions.map((draft) => (draft === test ? soften(draft, "easy") : draft));
          result[index] = { ...day, focus: focusWithoutTest(day.focus, sessions), sessions };
        }
      }
      const current = result[index];
      const total = own(current).reduce((sum, draft) => sum + draft.amount, 0);
      if (total <= allowed) continue;
      const [scaled] = scaleSessions([current], (draft) => draft.sport.id === sportId, allowed, (draft) => draft.amount);
      const left = own(scaled).reduce((sum, draft) => sum + draft.amount, 0);
      notes.push(`${label(current.date)}: ${sport.displayName} ${left > 0 ? `von ${formatAmount(sport, total)} auf ${formatAmount(sport, left)} gekürzt` : "gestrichen"} (${why})`);
      result[index] = { ...scaled, focus: scaled.sessions.length > 0 ? scaled.focus : "Ruhetag" };
    }
  }
  return result;
}

/**
 * Tauscht den Test von Tag `index` mit einer lockeren Einheit derselben Sportart an einem spaeteren Tag, an dem er in
 * die 7 Tage passt und die Regeln fuer Tests und harte Tage halten. Liefert den neuen Tag des Tests oder `null`.
 */
function moveTest(
  days: DraftDay[],
  index: number,
  test: Draft,
  weeklyCap: number,
  usedBefore: (date: string) => number,
  week: WeekLimitsV2,
  pinned: ReadonlyMap<string, DraftDay>,
  snapshot: SnapshotV2,
  context: WeekContextV2,
  free: ReadonlyMap<string, number>
): number | null {
  const from = days[index];
  const sessionsOn = (at: number) => {
    const day = days[at];
    if (day === undefined) return [];
    return pinned.get(day.date)?.sessions ?? day.sessions;
  };
  const hardAt = (at: number) => (at < 0 ? week.hardBefore : at !== index && sessionsOn(at).some(isHard));
  const testAt = (at: number) => at >= 0 && at !== index && sessionsOn(at).some((draft) => draft.test !== null);
  for (let at = index + 1; at < days.length; at += 1) {
    const target = days[at];
    if (pinned.has(target.date)) continue;
    const swap = target.sessions.find((draft) => draft.sport.id === test.sport.id && draft.test === null && !isHard(draft) && !draft.brick);
    if (swap === undefined || test.brick) continue;
    if (testBlackoutReason(snapshot, target.date) !== null) continue;
    if (target.sessions.some((draft) => draft !== swap && (isHard(draft) || draft.test !== null))) continue;
    if (testAt(at - 1) || testAt(at + 1)) continue;
    if (isHard(test) && (hardAt(at - 1) || hardAt(at + 1))) continue;
    const minutes = dayMinutes(target) - minutesOf(swap) + minutesOf(test);
    const cap = Math.min(week.dayMinutes.get(target.date) ?? week.maxDayMinutes, free.get(target.date) ?? Infinity);
    if (minutes > cap) continue;
    // Probeweise tauschen und das Fenster am neuen Tag pruefen. Der Schwerpunkt beider Tage kommt danach aus den Einheiten.
    const swapped = placeOpenWater(placeIndoor(swap, from.date, context, []), from.date, context, []);
    const before = [days[index], days[at]];
    days[index] = { ...from, focus: "", sessions: from.sessions.map((draft) => (draft === test ? swapped : draft)) };
    days[at] = { ...target, focus: "", sessions: target.sessions.map((draft) => (draft === swap ? test : draft)) };
    const ownThere = days[at].sessions.filter((draft) => draft.sport.id === test.sport.id).reduce((sum, draft) => sum + draft.amount, 0);
    if (usedBefore(target.date) + ownThere <= weeklyCap) return at;
    [days[index], days[at]] = before;
  }
  return null;
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
  let previousTestDay: string | null = (context.priorTests ?? []).reduce<string | null>((last, test) => (last === null || test.date > last ? test.date : last), null);
  const testedSports = new Set<string>((context.priorTests ?? []).map((test) => test.sport));
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

/** Intensive Minuten einer Woche: der Hauptteil jeder mittleren oder harten Einheit (`MULTI_RULES.intenseShareOfSession`). */
export function intenseMinutes(sessions: readonly { intensity: Intensity; minutes: number }[]): number {
  return sessions.reduce((sum, session) => sum + (RANK[session.intensity] >= RANK.moderate ? session.minutes * MULTI_RULES.intenseShareOfSession : 0), 0);
}

/**
 * Hoechstens `maxIntenseShareOfWeek` der Wochenminuten intensiv. Darueber werden mittlere Einheiten (keine Tests)
 * locker, die laengsten zuerst; harte Einheiten regelt schon die Zahl der harten Tage. Erst ab
 * `minSessionsForIntensityShare` Einheiten: Bei ein oder zwei Einheiten sagt ein Anteil wenig.
 */
function limitIntensity(days: DraftDay[], notes: string[]): DraftDay[] {
  if (days.reduce((sum, day) => sum + day.sessions.length, 0) < MULTI_RULES.minSessionsForIntensityShare) return days;
  const measure = () => {
    const all = days.flatMap((day) => day.sessions.map((draft) => ({ intensity: draft.intensity, minutes: minutesOf(draft) })));
    return { intense: intenseMinutes(all), total: all.reduce((sum, entry) => sum + entry.minutes, 0) };
  };
  const candidates = days
    .flatMap((day) => day.sessions.filter((draft) => draft.intensity === "moderate" && draft.test === null).map((draft) => ({ day, draft })))
    .sort((a, b) => minutesOf(b.draft) - minutesOf(a.draft));
  for (const { day, draft } of candidates) {
    const { intense, total } = measure();
    if (total <= 0 || intense <= total * MULTI_RULES.maxIntenseShareOfWeek) break;
    notes.push(`${label(day.date)}: ${draft.sport.displayName} auf "easy" gesenkt (etwa ${Math.round((1 - MULTI_RULES.maxIntenseShareOfWeek) * 100)} % der Woche locker)`);
    days = days.map((other) => (other.date === day.date ? { ...other, sessions: other.sessions.map((item) => (item === draft ? soften(item, "easy") : item)) } : other));
  }
  return days;
}

/** Die festen Tage der Anfrage als Entwurf (nur Tage im Plan und mit Zeit), je Datum. */
function fixedDays(context: WeekContextV2, week: WeekLimitsV2): Map<string, DraftDay> {
  const result = new Map<string, DraftDay>();
  for (const day of context.fixed ?? []) {
    if (!context.dates.includes(day.date) || context.unavailable.includes(day.date) || result.has(day.date)) continue;
    const sessions = day.sessions.flatMap((session) =>
      toDraft(
        {
          sport: session.sport,
          session_type: session.session_type,
          intensity: session.intensity,
          amount: session.amount,
          focus: session.focus,
          test_id: session.test_id ?? null,
          brick: session.brick ?? false,
          indoor: session.indoor ?? false,
          open_water: session.open_water ?? false
        },
        week,
        new Set()
      )
    );
    const extras = (day.extras ?? []).map((extra) => ({ kind: extra.kind, minutes: extra.minutes, focus: extra.focus.trim().slice(0, MULTI_RULES.maxFocusLength) }));
    result.set(day.date, { date: day.date, focus: day.focus?.trim().slice(0, MULTI_RULES.maxFocusLength) ?? "", sessions, extras });
  }
  return result;
}

/** Was die festen Tage verbrauchen, steht den anderen Tagen nicht mehr zur Verfuegung. */
function reserveFixed(week: WeekLimitsV2, fixed: ReadonlyMap<string, DraftDay>): WeekLimitsV2 {
  if (fixed.size === 0) return week;
  const drafts = [...fixed.values()].flatMap((day) => day.sessions);
  const sports = new Map(
    [...week.sports].map(([id, limits]): [string, SportLimitsNow] => {
      const used = drafts.filter((draft) => draft.sport.id === id).reduce((sum, draft) => sum + draft.amount, 0);
      return [id, used > 0 ? { ...limits, weeklyCap: Math.max(limits.weeklyCap - used, 0) } : limits];
    })
  );
  const minutes = drafts.reduce((sum, draft) => sum + minutesOf(draft), 0);
  return { ...week, sports, maxMinutes: Math.max(week.maxMinutes - minutes, 0) };
}

function fixedCount(fixed: ReadonlyMap<string, DraftDay>, sportId: string): number {
  return [...fixed.values()].reduce((sum, day) => sum + day.sessions.filter((draft) => draft.sport.id === sportId).length, 0);
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
      test: draft.test === null ? null : testRef(draft.test.test),
      brick: draft.brick,
      indoor: draft.indoor,
      open_water: draft.openWater && draft.test === null
    })
  );
  const focus = day.focus !== "" && (sessions.length > 0 || day.focus === "Keine Zeit") ? day.focus : sessions.length > 0 ? sessions.map((session) => session.focus).join(" + ").slice(0, MULTI_RULES.maxFocusLength) : "Ruhetag";
  return { date: day.date, focus, sessions, extras: day.extras };
}

export function withNote(rationale: string, notes: string[]): string {
  const text = rationale.trim().slice(0, MULTI_RULES.maxRationaleLength);
  if (notes.length === 0) return text;
  const note = `Hinweis: Zur Sicherheit angepasst (${notes.slice(0, 3).join("; ")}${notes.length > 3 ? `; und ${notes.length - 3} weitere` : ""}).`;
  const room = Math.max(MULTI_RULES.maxRationaleLength - note.length - 1, 0);
  return `${text.slice(0, room).trimEnd()} ${note}`.trim().slice(0, MULTI_RULES.maxRationaleLength);
}
