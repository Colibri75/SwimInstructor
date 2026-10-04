import { pino } from "pino";
import { z } from "zod";
import { GenerationBudget } from "../budget";
import { EvalCheck } from "../evaluation";
import { PlanGenerationError, PlanUnavailableError } from "../errors";
import { CallOptions, GeneratedPlan, StructuredGenerator } from "../generator";
import { mondayOf } from "../macro";
import { estimateCostUsd, SESSION_TYPE_LABEL } from "../report";
import { SnapshotSchema, SnapshotV2 } from "../snapshot";
import { addDays, weekdayName, windowDates } from "../week";
import { SessionStep } from "../../sports/types";
import { checkDayPlanV2, checkMacroPlanV2, checkRevisionV2, checkWeekPlanV2 } from "./evaluation";
import { MacroPlanV2 } from "./macroSanity";
import { MULTI_DAY_SYSTEM_PROMPT, MULTI_MACRO_SYSTEM_PROMPT, MULTI_REVISE_SYSTEM_PROMPT, MULTI_WEEK_SYSTEM_PROMPT } from "./prompts";
import { DayTargetV2, EquipmentV2Schema, MacroWeekTargetV2, RecentTraining, TestSettingsSchema } from "./schemas";
import { DayResultV2, MacroResultV2, MultiPlanService, ReviseResult, WeekResultV2 } from "./service";
import { plannedSports, sportName, stateOf } from "./sports";
import { MemoryDayPlanStoreV2 } from "./store";
import { WeekPlanV2 } from "./weekSanity";

/**
 * Szenarien fuer die Planung ueber mehrere Sportarten (backend/scenarios/multisport/) und ihr Durchlauf wie in der
 * App: Gesamtplan, die naechsten sieben Tage mit der Vorgabe des Gesamtplans, der Tag mit der Vorgabe der Woche und,
 * wenn das Szenario Feedback hat, die Ueberarbeitung des Gesamtplans. Alles laeuft durch den echten MultiPlanService;
 * nur der Generator wechselt: Claude (scripts/eval-multisport.ts), Claude mit Aufzeichnung oder die Aufzeichnung
 * selbst (Wiedergabe, ohne Netz und ohne Kosten, auch im Jest-Test).
 */
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export const MultiScenarioSchema = z.object({
  description: z.string().min(1),
  today: z.string().regex(DATE),
  snapshot: SnapshotSchema.refine((snapshot) => snapshot.schema_version === 2, { message: "Szenarien brauchen Snapshot v2" }),
  week_wishes: z.string().max(500).optional(),
  day_wishes: z.string().max(500).optional(),
  feedback: z.string().max(1000).optional(),
  test_settings: TestSettingsSchema.optional(),
  equipment: EquipmentV2Schema.optional(),
  unavailable_dates: z.array(z.string().regex(DATE)).max(7).optional()
});

export type MultiScenario = Omit<z.infer<typeof MultiScenarioSchema>, "snapshot"> & { snapshot: SnapshotV2 };

export function parseScenario(json: unknown): MultiScenario {
  return MultiScenarioSchema.parse(json) as MultiScenario;
}

// --- Generatoren ---

export type CallKind = "macro" | "week" | "day" | "revise";
export const CALL_KINDS: readonly CallKind[] = ["macro", "week", "day", "revise"];

export function kindOf(system: string): CallKind {
  if (system === MULTI_MACRO_SYSTEM_PROMPT) return "macro";
  if (system === MULTI_WEEK_SYSTEM_PROMPT) return "week";
  if (system === MULTI_DAY_SYSTEM_PROMPT) return "day";
  if (system === MULTI_REVISE_SYSTEM_PROMPT) return "revise";
  throw new Error("unbekannter System-Prompt");
}

/** Eine aufgezeichnete Antwort: von Claude oder, bis zum ersten echten Lauf, synthetisch (von Hand gebaut). */
export interface RecordedCall {
  source: "claude" | "synthetic";
  model: string;
  recorded_at: string;
  usage: { inputTokens: number; outputTokens: number };
  raw: unknown;
}

export type Recording = Partial<Record<CallKind, RecordedCall>>;

/** Spielt die Aufzeichnung eines Szenarios ab; fehlt eine Antwort, scheitert der Aufruf wie bei Claude. */
export class ReplayGenerator implements StructuredGenerator {
  constructor(private readonly recording: Recording) {}

  async complete(system: string): Promise<GeneratedPlan> {
    const kind = kindOf(system);
    const call = this.recording[kind];
    if (call === undefined) throw new PlanGenerationError("unknown", `keine Aufzeichnung für ${kind}`);
    return { raw: call.raw, model: call.model, usage: call.usage };
  }
}

/** Reicht an einen anderen Generator durch und haelt jede Antwort fest (EVAL_RECORD=1). */
export class RecordingGenerator implements StructuredGenerator {
  readonly recording: Recording = {};

  constructor(
    private readonly inner: StructuredGenerator,
    private readonly now: () => Date = () => new Date()
  ) {}

  async complete(system: string, user: string, schema: z.ZodType, options?: CallOptions): Promise<GeneratedPlan> {
    const result = await this.inner.complete(system, user, schema, options);
    this.recording[kindOf(system)] = { source: "claude", model: result.model, recorded_at: this.now().toISOString(), usage: result.usage, raw: result.raw };
    return result;
  }
}

export interface CallInfo {
  kind: CallKind;
  model: string;
  usage: { inputTokens: number; outputTokens: number };
  seconds: number;
  costUsd: number | null;
  /** Nur bei einem fehlgeschlagenen Aufruf: die Meldung (etwa "Request timed out."). */
  error?: string;
}

/** Misst jeden Aufruf: Modell, Token, Dauer, Kosten; bei einem Fehler Dauer und Meldung. */
class MeteredGenerator implements StructuredGenerator {
  readonly calls: CallInfo[] = [];

  constructor(private readonly inner: StructuredGenerator) {}

  async complete(system: string, user: string, schema: z.ZodType, options?: CallOptions): Promise<GeneratedPlan> {
    const started = Date.now();
    let result: GeneratedPlan;
    try {
      result = await this.inner.complete(system, user, schema, options);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.calls.push({ kind: kindOf(system), model: "-", usage: { inputTokens: 0, outputTokens: 0 }, seconds: (Date.now() - started) / 1000, costUsd: null, error: message });
      throw error;
    }
    this.calls.push({
      kind: kindOf(system),
      model: result.model,
      usage: result.usage,
      seconds: (Date.now() - started) / 1000,
      costUsd: estimateCostUsd(result.model, result.usage)
    });
    return result;
  }
}

// --- Eingaben wie in der App ---

/**
 * Das Training der letzten sieben Tage aus dem Snapshot nachgebaut: je Sportart die Einheiten im Abstand von zwei Tagen
 * ab der letzten, gleich lang. Die harte Einheit liegt auf dem Tag der letzten harten Einheit, wenn dort eine liegt.
 */
export function recentFromSnapshot(snapshot: SnapshotV2, today: string): RecentTraining[] {
  const hardDaysAgo = snapshot.load.days_since_last_hard_session;
  let hardMarked = false;
  const result: RecentTraining[] = [];
  for (const sport of plannedSports(snapshot)) {
    const state = stateOf(snapshot, sport.id);
    const last = state.days_since_last_session;
    const sessions = state.sessions_last_seven_days;
    if (last === undefined || sessions <= 0) continue;
    for (let index = 0; index < sessions; index += 1) {
      const daysAgo = last + index * 2;
      if (daysAgo < 1 || daysAgo > 7) continue;
      const hard: boolean = !hardMarked && daysAgo === hardDaysAgo;
      hardMarked ||= hard;
      result.push({
        date: addDays(today, -daysAgo),
        sport: sport.id,
        minutes: Math.round(state.minutes_last_seven_days / sessions),
        meters: Math.round(state.meters_last_seven_days / sessions),
        ...(hard ? { hard: true } : {})
      });
    }
  }
  return result.sort((a, b) => a.date.localeCompare(b.date) || a.sport.localeCompare(b.sport));
}

/** Der Gesamtplan, wie die App ihn als Vorgabe fuer die Woche und fuers Feedback mitschickt. */
export function macroTargets(plan: MacroPlanV2): MacroWeekTargetV2[] {
  return plan.weeks.map((week) => ({
    week_start: week.week_start,
    phase: week.phase,
    deload: week.deload,
    focus: week.focus,
    sports: week.sports.map((entry) => ({ sport: entry.sport, amount: entry.amount, sessions: entry.sessions })),
    tests: week.tests.map((test) => ({ sport: test.sport, test_id: test.test_id }))
  }));
}

/** Die Wochen des Gesamtplans, in die die sieben Tage ab `from` fallen. */
export function coveringWeeks(targets: readonly MacroWeekTargetV2[], from: string): MacroWeekTargetV2[] {
  const mondays = new Set(windowDates(from, 7).map(mondayOf));
  return targets.filter((week) => mondays.has(week.week_start));
}

/** Die Vorgabe fuer heute aus dem Wochenplan. */
export function dayTargetFrom(plan: WeekPlanV2, today: string): DayTargetV2 | undefined {
  const day = plan.days.find((entry) => entry.date === today);
  if (day === undefined) return undefined;
  return {
    focus: day.focus.slice(0, 120),
    sessions: day.sessions.map((session) => ({
      sport: session.sport,
      session_type: session.session_type,
      intensity: session.intensity,
      amount: session.amount,
      focus: session.focus.slice(0, 120),
      test_id: session.test?.id ?? null
    }))
  };
}

// --- Durchlauf ---

export interface StepReport<T> {
  result?: T;
  error?: string;
  /** Was genau scheiterte, etwa warum die Sicherheitsschicht blockierte. */
  detail?: string;
  checks: EvalCheck[];
}

export interface ScenarioReport {
  name: string;
  scenario: MultiScenario;
  macro: StepReport<MacroResultV2>;
  week: StepReport<WeekResultV2> & { macroWeeks: MacroWeekTargetV2[] };
  day: StepReport<DayResultV2> & { target?: DayTargetV2 };
  revise?: StepReport<ReviseResult>;
  calls: CallInfo[];
}

async function step<T>(work: () => Promise<T>, checks: (result: T) => EvalCheck[]): Promise<StepReport<T>> {
  try {
    const result = await work();
    return { result, checks: checks(result) };
  } catch (error) {
    if (error instanceof PlanUnavailableError) return { error: error.reason, ...(error.detail === undefined ? {} : { detail: error.detail }), checks: [] };
    throw error;
  }
}

export async function runScenario(name: string, scenario: MultiScenario, generator: StructuredGenerator): Promise<ScenarioReport> {
  const { snapshot, today } = scenario;
  const metered = new MeteredGenerator(generator);
  const service = new MultiPlanService({
    generator: metered,
    store: new MemoryDayPlanStoreV2(),
    budget: new GenerationBudget(1000, 1000),
    logger: pino({ level: "silent" }),
    timezone: "Europe/Berlin",
    now: () => new Date(`${today}T10:00:00Z`)
  });
  const recent = recentFromSnapshot(snapshot, today);
  const settings = scenario.test_settings;

  const macro = await step(
    () => service.planMacro({ snapshot, today, ...(settings !== undefined ? { testSettings: settings } : {}) }),
    (result) => checkMacroPlanV2(snapshot, result.plan, today)
  );
  const targets = macro.result !== undefined ? macroTargets(macro.result.plan) : [];
  const macroWeeks = coveringWeeks(targets, today);

  const week = await step(
    () =>
      service.planWeek({
        snapshot,
        fromDate: today,
        today,
        unavailable: scenario.unavailable_dates ?? [],
        recent,
        macroWeeks,
        wishes: scenario.week_wishes,
        equipment: scenario.equipment,
        testSettings: settings
      }),
    (result) => checkWeekPlanV2(snapshot, result.plan, macroWeeks)
  );
  const target = week.result !== undefined ? dayTargetFrom(week.result.plan, today) : undefined;

  const day = await step(
    () => service.planDay({ snapshot, wishes: scenario.day_wishes, dayTarget: target, equipment: scenario.equipment, recent, testSettings: settings }),
    (result) => checkDayPlanV2(result.plan, target)
  );

  let revise: StepReport<ReviseResult> | undefined;
  if (scenario.feedback !== undefined && macro.result !== undefined) {
    const feedback = scenario.feedback;
    const plan = { rationale: macro.result.plan.rationale, weeks: targets };
    revise = await step(
      () => service.reviseMacro({ snapshot, today, plan, feedback, history: [], testSettings: settings }),
      (result) => checkRevisionV2(targets, result.plan, result.changes)
    );
  }

  return { name, scenario, macro: { ...macro }, week: { ...week, macroWeeks }, day: { ...day, ...(target !== undefined ? { target } : {}) }, ...(revise !== undefined ? { revise } : {}), calls: metered.calls };
}

// --- Bericht ---

const INTENSITY_LABEL = { rest: "Ruhe", easy: "locker", moderate: "moderat", hard: "hart" } as const;
const UNIT_LABEL = { meters: "m", minutes: "min" } as const;
const PHASE_LABEL = { base: "Aufbau", specific: "zielspezifisch", taper: "Zuspitzen", goal_week: "Zielwoche", maintain: "Erhalten" } as const;

function formatChecks(checks: readonly EvalCheck[]): string {
  if (checks.length === 0) return "Keine automatischen Prüfungen.";
  return checks.map((check) => `- [${check.ok ? "x" : " "}] ${check.name}: ${check.detail}`).join("\n");
}

function adjustmentsBlock(adjustments: readonly string[]): string[] {
  return adjustments.length === 0 ? ["Die Sicherheitsschicht hat nichts geändert.", ""] : ["Korrekturen der Sicherheitsschicht:", "", ...adjustments.map((note) => `- ${note}`), ""];
}

function cell(text: string): string {
  return text.replace(/\|/g, "/").replace(/\n/g, " ");
}

export function formatMacroPlanV2(plan: MacroPlanV2): string[] {
  const sports = plan.weeks[0]?.sports.map((entry) => entry.sport) ?? [];
  const lines = [
    `| Woche ab | Phase | Entlastung | ${sports.map(sportName).join(" | ")} | Minuten | Tests | Schwerpunkt |`,
    `|---|---|---|${sports.map(() => "---|").join("")}---|---|---|`
  ];
  for (const week of plan.weeks) {
    const amounts = week.sports.map((entry) => (entry.amount > 0 ? `${entry.amount} ${UNIT_LABEL[entry.unit]} / ${entry.sessions}×` : "–"));
    const tests = week.tests.map((test) => `${sportName(test.sport)}: ${test.display_name}`).join(", ") || "–";
    lines.push(`| ${week.week_start} | ${PHASE_LABEL[week.phase]} | ${week.deload ? "ja" : "–"} | ${amounts.join(" | ")} | ${week.total_minutes} | ${cell(tests)} | ${cell(week.focus)} |`);
  }
  return lines;
}

export function formatWeekPlanV2(plan: WeekPlanV2): string[] {
  const lines = ["| Tag | Einheiten | Minuten | Schwerpunkt |", "|---|---|---|---|"];
  for (const day of plan.days) {
    const sessions =
      day.sessions
        .map((session) => `${sportName(session.sport)} ${session.amount} ${UNIT_LABEL[session.unit]} ${INTENSITY_LABEL[session.intensity]} (${session.test !== null ? session.test.display_name : SESSION_TYPE_LABEL[session.session_type]})`)
        .join(" + ") || "Ruhetag";
    const minutes = day.sessions.reduce((sum, session) => sum + session.minutes, 0);
    lines.push(`| ${weekdayName(day.date)} ${day.date} | ${cell(sessions)} | ${minutes} | ${cell(day.focus)} |`);
  }
  return lines;
}

function stepVolume(item: SessionStep): string {
  const per = item.measure === "distance" ? `${item.distance_meters} m` : `${Math.round(((item.duration_seconds ?? 0) / 60) * 10) / 10} min`;
  return item.repetitions > 1 ? `${item.repetitions} × ${per}` : per;
}

export function formatDayPlanV2(plan: DayResultV2["plan"]): string[] {
  if (plan.sessions.length === 0) return ["Ruhetag.", ""];
  const lines: string[] = [];
  for (const session of plan.sessions) {
    const title = session.test !== null ? `Leistungstest: ${session.test.display_name}` : SESSION_TYPE_LABEL[session.session_type];
    lines.push(`**${sportName(session.sport)}: ${title}**, ${INTENSITY_LABEL[session.intensity]}, ${session.amount} ${UNIT_LABEL[session.unit]}, ca. ${session.duration_minutes} min`, "");
    lines.push("| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |", "|---|---|---|---|---|---|");
    for (const item of session.steps) {
      const target = item.target_type === null ? "–" : `${item.target_type} ${item.target_value}`;
      lines.push(`| ${cell(item.name)} | ${stepVolume(item)} | ${target} | ${item.rest_seconds} s | ${cell(item.cue) || "–"} | ${cell(item.instructions)} |`);
    }
    lines.push("");
  }
  return lines;
}

function callLine(calls: readonly CallInfo[], kind: CallKind): string[] {
  const call = calls.find((entry) => entry.kind === kind);
  if (call === undefined) return [];
  if (call.error !== undefined) return [`Aufruf fehlgeschlagen nach ${call.seconds.toFixed(1)} s: ${call.error}`, ""];
  return [`Modell \`${call.model}\`, ${call.usage.inputTokens} Token ein, ${call.usage.outputTokens} Token aus, ${call.seconds.toFixed(1)} s, ca. ${call.costUsd === null ? "?" : `$${call.costUsd.toFixed(3)}`}`, ""];
}

/** Eine Zeile je Stufe fuer die Konsole: "ok" oder der Grund, bei einem Fehler von Claude mit Meldung und Dauer. */
/** Der Ausfallgrund einer Stufe, mit Einzelheit, wenn es eine gibt (etwa warum die Sicherheitsschicht blockierte). */
function failure(step: StepReport<unknown>): string {
  return step.detail === undefined ? (step.error ?? "") : `${step.error} (${step.detail})`;
}

export function stepSummary(report: ScenarioReport): string {
  const steps: [CallKind, StepReport<unknown> | undefined][] = [
    ["macro", report.macro],
    ["week", report.week],
    ["day", report.day],
    ["revise", report.revise]
  ];
  return steps
    .filter((entry): entry is [CallKind, StepReport<unknown>] => entry[1] !== undefined)
    .map(([kind, step]) => {
      if (step.error === undefined) return "ok";
      const call = report.calls.find((entry) => entry.kind === kind && entry.error !== undefined);
      return call === undefined ? failure(step) : `${step.error} (${call.error}, nach ${call.seconds.toFixed(0)} s)`;
    })
    .join(", ");
}

export function formatScenarioReport(report: ScenarioReport): string {
  const { scenario, calls } = report;
  const lines = [`## ${report.name}`, "", scenario.description, ""];
  const goal = scenario.snapshot.training_goal;
  lines.push(
    `Heute ${scenario.today}, Ziel am ${goal.target_date.slice(0, 10)}: ${goal.disciplines.map((discipline) => `${sportName(discipline.sport)} ${discipline.distance_meters} m`).join(", ")}; ` +
      `Schwerpunkte ${goal.emphasis.filter((entry) => entry.percent > 0).map((entry) => `${sportName(entry.sport)} ${entry.percent} %`).join(", ")}; ${goal.training_days_per_week} Tage, ${goal.weekly_hours} h pro Woche.`,
    ""
  );
  if (scenario.week_wishes !== undefined) lines.push(`Wunsch für die Woche: ${JSON.stringify(scenario.week_wishes)}`, "");
  if (scenario.day_wishes !== undefined) lines.push(`Wunsch für heute: ${JSON.stringify(scenario.day_wishes)}`, "");

  lines.push("### Gesamtplan", "");
  if (report.macro.result !== undefined) {
    lines.push(report.macro.result.plan.rationale, "", ...formatMacroPlanV2(report.macro.result.plan), "", ...adjustmentsBlock(report.macro.result.adjustments));
  } else {
    lines.push(`**Kein Gesamtplan:** ${failure(report.macro)}`, "");
  }
  lines.push("Prüfungen:", "", formatChecks(report.macro.checks), "", ...callLine(calls, "macro"));

  lines.push("### Die nächsten sieben Tage", "");
  if (report.week.result !== undefined) {
    lines.push(report.week.result.plan.rationale, "", ...formatWeekPlanV2(report.week.result.plan), "", ...adjustmentsBlock(report.week.result.adjustments));
  } else {
    lines.push(`**Kein Wochenplan:** ${failure(report.week)}`, "");
  }
  lines.push("Prüfungen:", "", formatChecks(report.week.checks), "", ...callLine(calls, "week"));

  lines.push("### Heute", "");
  if (report.day.result !== undefined) {
    lines.push(report.day.result.plan.rationale, "", ...formatDayPlanV2(report.day.result.plan), ...adjustmentsBlock(report.day.result.adjustments));
    if (report.day.result.plan.coach_notes.length > 0) lines.push(...report.day.result.plan.coach_notes.map((note) => `> ${note}`), "");
  } else {
    lines.push(`**Kein Tagesplan:** ${failure(report.day)}`, "");
  }
  lines.push("Prüfungen:", "", formatChecks(report.day.checks), "", ...callLine(calls, "day"));

  if (report.revise !== undefined) {
    lines.push("### Feedback zum Gesamtplan", "", `Feedback: ${JSON.stringify(scenario.feedback)}`, "");
    if (report.revise.result !== undefined) {
      lines.push("Änderungen laut Claude:", "", ...report.revise.result.changes.map((change) => `- ${change}`), "", ...formatMacroPlanV2(report.revise.result.plan), "", ...adjustmentsBlock(report.revise.result.adjustments));
    } else {
      lines.push(`**Keine Überarbeitung:** ${failure(report.revise)}`, "");
    }
    lines.push("Prüfungen:", "", formatChecks(report.revise.checks), "", ...callLine(calls, "revise"));
  }
  return lines.join("\n");
}

/** Die Uebersicht ueber alle Szenarien: Status, Korrekturen und erfuellte Pruefungen je Stufe, dazu die Kosten. */
export function formatSummary(reports: readonly ScenarioReport[]): string {
  const lines = ["| Szenario | Stufe | Status | Korrekturen | Prüfungen erfüllt |", "|---|---|---|---|---|"];
  for (const report of reports) {
    const steps: Array<[string, StepReport<{ adjustments: string[] }> | undefined]> = [
      ["Gesamt", report.macro],
      ["7 Tage", report.week],
      ["Tag", report.day],
      ["Feedback", report.revise]
    ];
    for (const [label, item] of steps) {
      if (item === undefined) continue;
      const passed = item.checks.filter((check) => check.ok).length;
      lines.push(`| ${report.name} | ${label} | ${item.error ?? "ok"} | ${item.result?.adjustments.length ?? 0} | ${passed}/${item.checks.length} |`);
    }
  }
  const cost = reports.flatMap((report) => report.calls).reduce((sum, call) => sum + (call.costUsd ?? 0), 0);
  lines.push("", `Geschätzte Kosten: $${cost.toFixed(2)} (${reports.reduce((sum, report) => sum + report.calls.length, 0)} Aufrufe).`);
  return lines.join("\n");
}
