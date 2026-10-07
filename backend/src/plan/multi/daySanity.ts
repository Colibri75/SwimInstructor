import { SPORTS } from "../../sports/registry";
import { LimitUnit, SessionStep, SportDefinition } from "../../sports/types";
import { Intensity, SessionType } from "../vocabulary";
import { SnapshotV2 } from "../snapshot";
import { dayLimits, DayLimitsV2, lower, MULTI_RULES, RANK, sportLimits, SportLimitsNow } from "./limits";
import { DaySessionRaw, ExtraKind, EXTRA_KINDS, MultiDayPlanRaw, RecentTraining, Supplements, TestSettings } from "./schemas";
import { DayWeather, severeWeather } from "../weather";
import { DayExtra, EXERCISE_RULES, EXTRA_RULES, normalizeDayExtras, perWeek, strengthBlackout } from "./extras";
import { formatAmount, planningContext, sportName } from "./sports";
import { checkTarget, normalizeStep, stepsAmount, trimSteps } from "./steps";
import { chooseTest, stepsTotals, TestRef, testRef } from "./tests";
import { indoorAllowed, withNote } from "./weekSanity";
import { openWaterAllowed, openWaterBlocked } from "./openWater";

/**
 * Sicherheitsschicht fuer den Tagesplan ueber mehrere Sportarten. Reiner Code: korrigiert Claudes Plan
 * deterministisch oder blockt ihn, wenn er nicht mehr zu retten ist.
 *
 * Regeln: Pflicht-Ruhetag bei Uebertrainingsrisiko; hoechstens zwei Einheiten und eine harte; je Sportart die Grenze
 * fuer heute (Einheit, Woche, Erholung, Wiedereinstieg locker); Schritte im Raster der Sportart; Ziele nur, wenn sie
 * fuer den Athleten in Frage kommen, im Bereich des Moduls und passend zur Intensitaet; ein Leistungstest bekommt die
 * Schritte aus dem Modul, wenn er heute passt, sonst wird er eine lockere Einheit; der Tag hat hoechstens die Haelfte
 * der Wochenstunden.
 */
export interface DayOptionsV2 {
  /** Heute (Kalendertag des Athleten). */
  date: string;
  /** Das Equipment des Athleten; fehlt die Angabe, ist jedes erlaubt. */
  equipment?: readonly string[];
  recent?: readonly RecentTraining[];
  testSettings?: TestSettings;
  /** Wie oft pro Woche Kraft und Mobilitaet dazukommen; ohne Angabe keine. */
  supplements?: Supplements;
  /** Die Arten, die der Wochenplan fuer heute vorsieht; ohne Vorgabe jede gewuenschte. */
  plannedExtras?: readonly ExtraKind[];
  /** Freie Minuten heute laut Kalender. */
  availableMinutes?: number;
  /** Wetter heute. */
  weather?: DayWeather;
  /** Vorschau fuer einen kommenden Tag: Das 7-Tage-Fenster rechnet ab diesem Tag (aus `recent`). */
  preview?: boolean;
}

export interface DaySessionV2 {
  sport: string;
  session_type: SessionType;
  intensity: Intensity;
  focus: string;
  test: TestRef | null;
  /** Umfang in der Einheit der Sportart (`unit`: "meters" oder "minutes", wie im Gesamtplan). */
  amount: number;
  unit: LimitUnit;
  distance_meters: number;
  duration_minutes: number;
  /** Schliesst direkt an die erste Einheit des Tages an (Koppeltraining). */
  brick: boolean;
  /** Drinnen (Rolle, Laufband). */
  indoor: boolean;
  /** Im Freiwasser (See, Meer) statt im Becken. */
  open_water: boolean;
  steps: SessionStep[];
}

export interface DayPlanV2 {
  rationale: string;
  sessions: DaySessionV2[];
  /** Kraft- und Mobilitaetsbloecke mit Uebungen. */
  extras: DayExtra[];
  coach_notes: string[];
}

export interface DaySanityResultV2 {
  plan: DayPlanV2;
  adjustments: string[];
  blocked: string | null;
}

interface Draft {
  sport: SportDefinition;
  limits: SportLimitsNow;
  session_type: SessionType;
  intensity: Intensity;
  focus: string;
  test: TestRef | null;
  steps: SessionStep[];
  brick: boolean;
  indoor: boolean;
  openWater: boolean;
}

const FORMAL_PREFIX = "Formal:";

export function sanitizeDayV2(input: MultiDayPlanRaw, snapshot: SnapshotV2, options: DayOptionsV2): DaySanityResultV2 {
  const problem = findProblem(input);
  if (problem !== null) return { plan: { rationale: input.rationale, sessions: [], extras: [], coach_notes: [] }, adjustments: [], blocked: problem };

  const notes: string[] = [];
  const today = dayLimits(snapshot, options.date, options.recent ?? [], options.preview === true);
  const available = options.equipment === undefined ? undefined : new Set(options.equipment);
  const coachNotes = input.coach_notes
    .map((note) => note.trim().slice(0, MULTI_RULES.maxNoteLength))
    .filter((note) => note !== "")
    .slice(0, MULTI_RULES.maxNotes);

  // Kraft und Mobilitaet: gewuenscht, vom Wochenplan vorgesehen, Kraft nicht kurz vor dem Ziel und nicht an einem Ruhetag.
  const wanted = new Set(EXTRA_KINDS.filter((kind) => perWeek(options.supplements, kind) > 0 && (options.plannedExtras === undefined || options.plannedExtras.includes(kind))));
  if (wanted.has("strength") && (strengthBlackout(snapshot, options.date) || today.restReason !== null)) wanted.delete("strength");
  let extras = normalizeDayExtras(input.extras, wanted);
  const dropped = (input.extras ?? []).filter((extra) => !extras.some((kept) => kept.kind === extra.kind)).map((extra) => EXTRA_RULES[extra.kind].displayName);
  if (dropped.length > 0) notes.push(`${[...new Set(dropped)].join(" und ")} heute gestrichen (nicht vorgesehen)`);

  if (today.restReason !== null) {
    if (input.sessions.length > 0) notes.push(`Ruhetag erzwungen: ${today.restReason}`);
    return done(`Heute ist Ruhe angesagt: ${today.restReason}.`, [], extras, coachNotes, notes, true);
  }

  // 1. Sportarten des Plans, Formalien der Schritte.
  const unplanned = new Set<string>();
  const removedEquipment = new Set<string>();
  let drafts = input.sessions.flatMap((raw) => toDraft(raw, snapshot, available, unplanned, removedEquipment, notes));
  if (unplanned.size > 0) notes.push(`Einheiten von Sportarten ohne Schwerpunkt entfernt (${[...unplanned].map(sportName).join(", ")})`);
  if (removedEquipment.size > 0) notes.push(`Hilfsmittel entfernt, die du nicht hast: ${[...removedEquipment].join(", ")}`);
  if (drafts.length > MULTI_RULES.maxSessionsPerDay) {
    notes.push(`Auf ${MULTI_RULES.maxSessionsPerDay} Einheiten gekürzt`);
    const keep = [...drafts].sort((a, b) => minutesOf(b) - minutesOf(a)).slice(0, MULTI_RULES.maxSessionsPerDay);
    drafts = drafts.filter((draft) => keep.includes(draft));
  }
  drafts = drafts.map((draft) => placeOpenWater(placeIndoor(draft, options, notes), options, notes));

  // 2. Leistungstests: Schritte aus dem Modul oder eine lockere Einheit.
  let testDone = false;
  drafts = drafts.flatMap((draft) => {
    if (draft.session_type !== "test") return [draft];
    const limits = today.sports.get(draft.sport.id);
    const blocked =
      (options.testSettings?.offer === false ? "Leistungstests sind abgeschaltet" : null) ??
      today.testBlockedReason ??
      (testDone ? "höchstens ein Test pro Tag" : null) ??
      limits?.blockedReason ??
      null;
    const chosen =
      blocked === null && limits !== undefined
        ? chooseTest(draft.limits, {
            requested: draft.test?.id,
            settings: options.testSettings,
            maxAmount: limits.maxAmount,
            maxMinutes: today.maxMinutes,
            maxIntensity: limits.maxIntensity,
            intensityReason: limits.intensityReasons.join(", ")
          })
        : { plan: null, reason: blocked };
    if (chosen.plan === null) {
      notes.push(`Kein Leistungstest ${draft.sport.displayName} heute (${chosen.reason ?? "passt nicht"}), lockere Einheit statt dessen`);
      const easy = soften({ ...draft, test: null, focus: "Locker statt Leistungstest" }, "easy");
      return easy.steps.length > 0 ? [easy] : [];
    }
    testDone = true;
    return [
      {
        ...draft,
        session_type: "test" as const,
        intensity: chosen.plan.intensity,
        focus: chosen.plan.test.displayName,
        test: testRef(chosen.plan.test),
        steps: chosen.plan.steps.map((step) => ({ ...step, equipment: [...step.equipment] }))
      }
    ];
  });

  // 3. Je Sportart: Grenze fuer heute und Intensitaet.
  drafts = drafts.flatMap((draft) => applySportLimits(draft, today, notes));

  // 4. Hoechstens eine harte Einheit (ein Test geht vor).
  const hard = drafts.filter((draft) => draft.intensity === "hard");
  if (hard.length > MULTI_RULES.maxHardSessionsPerDay) {
    const keep = hard.find((draft) => draft.test !== null) ?? hard[0];
    notes.push('Nur eine harte Einheit am Tag, die andere auf "moderate" gesenkt');
    drafts = drafts.map((draft) => (draft.intensity === "hard" && draft !== keep ? soften(draft, "moderate") : draft));
  }

  // 5. Der Tag hat hoechstens die Haelfte der Wochenstunden (oder die freie Zeit laut Kalender): die groessten Einheiten
  // (ohne Test) werden gekuerzt.
  const maxMinutes = Math.min(today.maxMinutes, options.availableMinutes ?? Infinity);
  const total = drafts.reduce((sum, draft) => sum + minutesOf(draft), 0);
  if (total > maxMinutes) {
    const fixed = drafts.filter((draft) => draft.test !== null).reduce((sum, draft) => sum + minutesOf(draft), 0);
    const flexible = total - fixed;
    const factor = flexible > 0 ? Math.max(maxMinutes - fixed, 0) / flexible : 0;
    notes.push(`Tagesumfang von ${Math.round(total)} min auf höchstens ${maxMinutes} min gekürzt${maxMinutes < today.maxMinutes ? " (freie Zeit laut Kalender)" : ""}`);
    drafts = drafts.flatMap((draft) => {
      if (draft.test !== null) return [draft];
      const steps = trimSteps(draft.steps, draft.sport, draft.limits.speed, minutesOf(draft) * factor, "minutes");
      return stepsAmount(steps, draft.sport, draft.limits.speed) >= draft.sport.planning.limits.minSession ? [{ ...draft, steps }] : [];
    });
  }

  // 6. Ziele pruefen (nach allen Aenderungen an der Intensitaet).
  let targetsChanged = false;
  drafts = drafts.map((draft) => {
    if (draft.test !== null) return draft;
    const context = planningContext(snapshot, draft.sport);
    const steps = draft.steps.map((step) => {
      const checked = checkTarget(step, draft.sport, context, draft.intensity);
      targetsChanged ||= checked.changed;
      return checked.step;
    });
    return { ...draft, steps };
  });
  if (targetsChanged) notes.push(`${FORMAL_PREFIX} Zielwerte an die Grenzen für dich und die Intensität angepasst`);

  // 7. Koppeltraining nur direkt nach der passenden ersten Einheit (nach allen Streichungen).
  drafts = drafts.map((draft, index) => {
    if (!draft.brick) return draft;
    const previous = index === 1 ? drafts[0] : undefined;
    if (previous !== undefined && draft.sport.planning.brickAfter.includes(previous.sport.id)) return draft;
    notes.push(`${draft.sport.displayName} als eigene Einheit (Koppeltraining nur direkt nach ${draft.sport.planning.brickAfter.map(sportName).join(" oder ") || "keiner Sportart"})`);
    return { ...draft, brick: false };
  });

  // 8. Kraft und Mobilitaet in der restlichen Tageszeit (Mobilitaet zuerst).
  let room = maxMinutes - drafts.reduce((sum, draft) => sum + minutesOf(draft), 0);
  extras = [...extras]
    .sort((a, b) => (a.kind === b.kind ? 0 : a.kind === "mobility" ? -1 : 1))
    .filter((extra) => {
      if (extra.minutes <= room) {
        room -= extra.minutes;
        return true;
      }
      notes.push(`${EXTRA_RULES[extra.kind].displayName} gestrichen (Tageszeit ausgeschöpft)`);
      return false;
    });

  const rest = drafts.length === 0;
  const rationale = rest && input.sessions.length > 0 ? "Heute ist Ruhe angesagt: Die geplanten Einheiten passen heute nicht in die Grenzen." : input.rationale;
  return done(rationale, drafts, extras, coachNotes, notes, false);
}

/** Drinnen nur mit Hilfsmittel; bei Unwetter nach drinnen, wenn das geht (wie im Wochenplan). */
function placeIndoor(draft: Draft, options: DayOptionsV2, notes: string[]): Draft {
  const sport = draft.sport;
  const allowed = indoorAllowed(sport, options.equipment);
  if (draft.indoor && !allowed) {
    notes.push(`${sport.displayName} draußen (${sport.planning.indoor === null ? "drinnen gibt es nicht" : `kein ${sport.planning.indoor.displayName} angegeben`})`);
    return { ...draft, indoor: false };
  }
  const severe = options.weather !== undefined && sport.planning.weatherSensitive ? severeWeather(options.weather) : null;
  if (severe !== null && !draft.indoor && allowed && sport.planning.indoor !== null) {
    notes.push(`${severe}: ${sport.displayName} drinnen (${sport.planning.indoor.displayName})`);
    return { ...draft, indoor: true };
  }
  return draft;
}

/** Freiwasser nur mit Zugang und passendem Wetter (wie im Wochenplan), sonst im Becken. */
function placeOpenWater(draft: Draft, options: DayOptionsV2, notes: string[]): Draft {
  if (!draft.openWater) return draft;
  const sport = draft.sport;
  if (sport.planning.openWater === null || !openWaterAllowed(sport, options.equipment)) {
    notes.push(`${sport.displayName} im Becken (${sport.planning.openWater === null ? "Freiwasser gibt es nicht" : "kein Zugang zu Freiwasser angegeben"})`);
    return { ...draft, openWater: false };
  }
  const blocked = openWaterBlocked(options.weather);
  if (blocked !== null) {
    notes.push(`${blocked}: ${sport.displayName} im Becken`);
    return { ...draft, openWater: false };
  }
  return draft;
}

function findProblem(input: MultiDayPlanRaw): string | null {
  if (input.rationale.trim() === "") return "Begründung fehlt";
  if (input.sessions.length > 6) return `zu viele Einheiten (${input.sessions.length})`;
  for (const session of input.sessions) {
    if (session.steps.length > MULTI_RULES.maxStepsPerSession * 3) return `zu viele Schritte (${session.steps.length})`;
    for (const step of session.steps) {
      const numbers = [step.repetitions, step.rest_seconds, step.distance_meters ?? 0, step.duration_seconds ?? 0, step.target_value ?? 0];
      if (!numbers.every(Number.isFinite)) return "Zahlenwert in einem Schritt ungültig";
      if (step.repetitions < 1 || (step.distance_meters ?? 0) < 0 || (step.duration_seconds ?? 0) < 0 || step.rest_seconds < 0) return "Schritt mit unmöglichen Werten";
    }
  }
  return null;
}

function toDraft(
  raw: DaySessionRaw,
  snapshot: SnapshotV2,
  available: ReadonlySet<string> | undefined,
  unplanned: Set<string>,
  removedEquipment: Set<string>,
  notes: string[]
): Draft[] {
  const sport = snapshot.training_goal.emphasis.some((entry) => entry.sport === raw.sport && entry.percent > 0) ? SPORTS.get(raw.sport) : undefined;
  if (sport === undefined) {
    unplanned.add(raw.sport);
    return [];
  }
  const isTest = raw.session_type === "test" || raw.test_id !== null;
  if (!isTest && (raw.session_type === "rest" || raw.intensity === "rest")) return [];
  const limits = sportLimits(snapshot, sport);
  const steps: SessionStep[] = [];
  for (const rawStep of raw.steps) {
    const normalized = normalizeStep(rawStep, sport, limits.speed, available);
    normalized.removedEquipment.forEach((item) => removedEquipment.add(sport.planning.equipment[item] ?? item));
    if (normalized.step !== null) steps.push(normalized.step);
  }
  if (steps.length > MULTI_RULES.maxStepsPerSession) {
    notes.push(`${sport.displayName}: auf ${MULTI_RULES.maxStepsPerSession} Schritte gekürzt`);
    steps.length = MULTI_RULES.maxStepsPerSession;
  }
  if (!isTest && steps.length === 0) {
    notes.push(`${sport.displayName}: Einheit ohne Schritte entfernt`);
    return [];
  }
  const test = isTest ? sport.performanceTests.find((entry) => entry.id === raw.test_id) : undefined;
  return [
    {
      sport,
      limits,
      session_type: isTest ? "test" : raw.session_type,
      intensity: raw.intensity === "rest" ? "easy" : raw.intensity,
      focus: raw.focus.trim().slice(0, MULTI_RULES.maxFocusLength) || sport.displayName,
      // Bis zur Pruefung haelt `test` nur den angefragten Test fest.
      test: test !== undefined ? testRef(test) : null,
      steps,
      brick: raw.brick === true,
      indoor: raw.indoor === true,
      openWater: raw.open_water === true && !isTest
    }
  ];
}

function minutesOf(draft: Draft): number {
  return stepsTotals(draft.sport, draft.steps, draft.limits.speed).minutes;
}

/** Leichter machen: Typ ohne Schwelle oder Intervalle, Intensitaet hoechstens `max`; die Ziele passt Schritt 6 an. */
function soften(draft: Draft, max: Intensity): Draft {
  const harsh = draft.session_type === "intervals" || draft.session_type === "threshold" || draft.session_type === "test";
  return { ...draft, session_type: harsh ? "endurance" : draft.session_type, intensity: lower(draft.intensity, max), test: null };
}

function applySportLimits(draft: Draft, today: DayLimitsV2, notes: string[]): Draft[] {
  const limits = today.sports.get(draft.sport.id);
  const sport = draft.sport;
  if (limits === undefined) return [];
  if (limits.blockedReason !== null) {
    notes.push(`${sport.displayName} gestrichen (${limits.blockedReason})`);
    return [];
  }
  if (draft.test !== null) return [draft];
  let result = draft;
  if (RANK[result.intensity] > RANK[limits.maxIntensity]) {
    notes.push(`${sport.displayName}: Intensität von "${result.intensity}" auf "${limits.maxIntensity}" gesenkt (${limits.intensityReasons.join(", ")})`);
    result = soften(result, limits.maxIntensity);
  }
  const before = stepsAmount(result.steps, sport, result.limits.speed);
  if (before > limits.maxAmount) {
    const steps = trimSteps(result.steps, sport, result.limits.speed, limits.maxAmount);
    const after = stepsAmount(steps, sport, result.limits.speed);
    if (after < sport.planning.limits.minSession) {
      notes.push(`${sport.displayName} gestrichen (zu wenig sicherer Restumfang)`);
      return [];
    }
    notes.push(`${sport.displayName}: Umfang von ${formatAmount(sport, before)} auf ${formatAmount(sport, after)} gekürzt (Grenze für heute: ${formatAmount(sport, limits.maxAmount)})`);
    result = { ...result, steps };
  }
  return [result];
}

function done(rationale: string, drafts: Draft[], extras: DayExtra[], coachNotes: string[], notes: string[], forcedRest: boolean): DaySanityResultV2 {
  const sessions = drafts.map((draft): DaySessionV2 => {
    const totals = stepsTotals(draft.sport, draft.steps, draft.limits.speed);
    return {
      sport: draft.sport.id,
      session_type: draft.session_type,
      intensity: draft.intensity,
      focus: draft.focus,
      test: draft.session_type === "test" ? draft.test : null,
      amount: Math.round(totals.amount),
      unit: draft.sport.planning.limitUnit,
      distance_meters: Math.round(totals.meters / 50) * 50,
      duration_minutes: Math.max(Math.round(totals.minutes), 1),
      brick: draft.brick,
      indoor: draft.indoor,
      open_water: draft.openWater && draft.session_type !== "test",
      steps: draft.steps
    };
  });
  const substantive = notes.filter((note) => !note.startsWith(FORMAL_PREFIX));
  const adjustments = notes.map((note) => (note.startsWith(FORMAL_PREFIX) ? note.slice(FORMAL_PREFIX.length).trim() : note));
  return {
    plan: { rationale: forcedRest ? rationale : withNote(rationale, substantive), sessions, extras, coach_notes: coachNotes },
    adjustments,
    blocked: null
  };
}
