import { SPORTS } from "../../sports/registry";
import { LimitUnit, SessionStep, SportDefinition } from "../../sports/types";
import { Intensity, SessionType } from "../vocabulary";
import { SnapshotV2 } from "../snapshot";
import { dayLimits, DayLimitsV2, lower, MULTI_RULES, RANK, sportLimits, SportLimitsNow } from "./limits";
import { DaySessionRaw, MultiDayPlanRaw, RecentTraining, TestSettings } from "./schemas";
import { formatAmount, planningContext, sportName } from "./sports";
import { checkTarget, normalizeStep, stepsAmount, trimSteps } from "./steps";
import { chooseTest, stepsTotals, TestRef, testRef } from "./tests";
import { withNote } from "./weekSanity";

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
  steps: SessionStep[];
}

export interface DayPlanV2 {
  rationale: string;
  sessions: DaySessionV2[];
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
}

const FORMAL_PREFIX = "Formal:";

export function sanitizeDayV2(input: MultiDayPlanRaw, snapshot: SnapshotV2, options: DayOptionsV2): DaySanityResultV2 {
  const problem = findProblem(input);
  if (problem !== null) return { plan: { rationale: input.rationale, sessions: [], coach_notes: [] }, adjustments: [], blocked: problem };

  const notes: string[] = [];
  const today = dayLimits(snapshot, options.date, options.recent ?? []);
  const available = options.equipment === undefined ? undefined : new Set(options.equipment);
  const coachNotes = input.coach_notes
    .map((note) => note.trim().slice(0, MULTI_RULES.maxNoteLength))
    .filter((note) => note !== "")
    .slice(0, MULTI_RULES.maxNotes);

  if (today.restReason !== null) {
    if (input.sessions.length > 0) notes.push(`Ruhetag erzwungen: ${today.restReason}`);
    return done(`Heute ist Ruhe angesagt: ${today.restReason}.`, [], coachNotes, notes, true);
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

  // 5. Der Tag hat hoechstens die Haelfte der Wochenstunden: die groessten Einheiten (ohne Test) werden gekuerzt.
  const total = drafts.reduce((sum, draft) => sum + minutesOf(draft), 0);
  if (total > today.maxMinutes) {
    const fixed = drafts.filter((draft) => draft.test !== null).reduce((sum, draft) => sum + minutesOf(draft), 0);
    const flexible = total - fixed;
    const factor = flexible > 0 ? Math.max(today.maxMinutes - fixed, 0) / flexible : 0;
    notes.push(`Tagesumfang von ${Math.round(total)} min auf höchstens ${today.maxMinutes} min gekürzt`);
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

  const rest = drafts.length === 0;
  const rationale = rest && input.sessions.length > 0 ? "Heute ist Ruhe angesagt: Die geplanten Einheiten passen heute nicht in die Grenzen." : input.rationale;
  return done(rationale, drafts, coachNotes, notes, false);
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
      steps
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

function done(rationale: string, drafts: Draft[], coachNotes: string[], notes: string[], forcedRest: boolean): DaySanityResultV2 {
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
      steps: draft.steps
    };
  });
  const substantive = notes.filter((note) => !note.startsWith(FORMAL_PREFIX));
  const adjustments = notes.map((note) => (note.startsWith(FORMAL_PREFIX) ? note.slice(FORMAL_PREFIX.length).trim() : note));
  return {
    plan: { rationale: forcedRest ? rationale : withNote(rationale, substantive), sessions, coach_notes: coachNotes },
    adjustments,
    blocked: null
  };
}
