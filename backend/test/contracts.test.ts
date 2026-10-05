import { readFileSync } from "node:fs";
import path from "node:path";
import request from "supertest";
import { createLogger } from "../src/logger";
import { GenerationBudget } from "../src/plan/budget";
import { PlanGenerationError } from "../src/plan/errors";
import { multiRoutes } from "../src/plan/multi/routes";
import { MultiPlanService } from "../src/plan/multi/service";
import { asRawDayPlan, MemoryDayPlanStoreV2 } from "../src/plan/multi/store";
import { SnapshotSchema } from "../src/plan/snapshot";
import { ATHLETE_METRICS } from "../src/sports/performance";
import { SPORTS } from "../src/sports/registry";
import { STEP_MEASURES, STEP_TARGETS } from "../src/sports/vocabulary";
import { buildApp, TEST_TOKEN, testConfig } from "./helpers";

/**
 * Prueft den Server gegen contracts/. Die App prueft dieselben Dateien (ContractTests.swift): So faellt ein
 * Formatbruch zwischen App und Server in der CI auf, ohne Geraet und ohne laufende App.
 *
 * Die Antworten entstehen hier ueber die echten Routen (nur Claude ist ersetzt) und muessen genau die Felder
 * der Vertragsdateien haben, die die App dekodiert.
 */
const CONTRACTS = path.join(__dirname, "../../contracts");
const contract = (file: string): any => JSON.parse(readFileSync(path.join(CONTRACTS, file), "utf8"));

const auth = { Authorization: `Bearer ${TEST_TOKEN}` };
const now = () => new Date("2026-09-30T10:00:00Z");
const logger = createLogger(testConfig);
const generated = (raw: unknown) => jest.fn().mockResolvedValue({ raw, model: "claude-opus-5-5", usage: { inputTokens: 1, outputTokens: 1 } });

/** Alle Schluesselpfade eines JSON-Werts, z. B. "plan.sets[].cue". Gegenstueck: JSONKeyPaths in Swift. */
function keyPaths(value: unknown, prefix = ""): Set<string> {
  const paths = new Set<string>();
  if (Array.isArray(value)) {
    for (const item of value) for (const p of keyPaths(item, `${prefix}[]`)) paths.add(p);
  } else if (typeof value === "object" && value !== null) {
    for (const [key, child] of Object.entries(value)) {
      const p = prefix === "" ? key : `${prefix}.${key}`;
      paths.add(p);
      for (const nested of keyPaths(child, p)) paths.add(nested);
    }
  }
  return paths;
}

const sorted = (paths: Set<string>) => [...paths].sort();

describe("contracts/sports.json", () => {
  const sports = contract("sports.json");

  it("nennt denselben Wortschatz wie der Server", () => {
    expect(sports.schema_version).toBe(1);
    expect(sports.measures).toEqual([...STEP_MEASURES]);
    expect(sports.targets).toEqual([...STEP_TARGETS]);
  });

  it("nennt dieselben Sportarten wie der Server", () => {
    expect(sports.sports.map((sport: { id: string }) => sport.id)).toEqual(SPORTS.ids);
    for (const sport of sports.sports) {
      const definition = SPORTS.get(sport.id);
      expect(definition?.displayName).toBe(sport.display_name);
      expect([...(definition?.measures ?? [])].sort()).toEqual([...sport.measures].sort());
      expect([...(definition?.targets ?? [])].sort()).toEqual([...sport.targets].sort());
      expect(definition?.goalSpeed).toEqual({
        minMetersPerSecond: sport.goal_speed.min_meters_per_second,
        maxMetersPerSecond: sport.goal_speed.max_meters_per_second
      });
      expect(definition?.loadFactor).toBe(sport.load_factor);
      expect(definition?.planning.limitUnit).toBe(sport.plan_unit);
      expect(definition?.planning.typicalSpeedMetersPerSecond).toBe(sport.typical_speed_meters_per_second);
      expect(definition?.planning.brickAfter).toEqual(sport.brick_after);
      expect(definition?.planning.weatherSensitive).toBe(sport.weather_sensitive);
      expect(definition?.planning.indoor).toEqual(sport.indoor === null ? null : { equipment: sport.indoor.equipment, displayName: sport.indoor.display_name });
      expect(definition?.performanceMetrics).toEqual(sport.performance_metrics.map(metricOf));
      expect(definition?.performanceTests).toEqual(
        sport.performance_tests.map((test: any) => ({
          id: test.id,
          displayName: test.display_name,
          produces: test.produces,
          maximalEffort: test.maximal_effort,
          durationMinutes: test.duration_minutes
        }))
      );
    }
  });

  it("nennt dieselben Leistungswerte fuer alle Sportarten wie der Server", () => {
    expect([...ATHLETE_METRICS]).toEqual(sports.athlete_metrics.map(metricOf));
  });
});

function metricOf(metric: any) {
  return { id: metric.id, displayName: metric.display_name, unit: metric.unit, min: metric.min, max: metric.max };
}

describe("contracts/wire, Snapshot", () => {
  it.each(["wire/snapshot-v2.json", "wire/snapshot-v2-profile.json", "wire/snapshot-v2-starting-levels.json"])("nimmt %s der App vollstaendig an (kein Feld wird verworfen)", (file) => {
    const snapshot = contract(file);
    const parsed = SnapshotSchema.safeParse(snapshot);
    expect(parsed.success).toBe(true);
    expect(sorted(keyPaths(parsed.data))).toEqual(sorted(keyPaths(snapshot)));
  });
});

describe("contracts/wire, Plan", () => {
  // Wie die App ihren Snapshot schickt, mit Rad-Umfang und Abstand zur harten Einheit, die heute einen Test erlauben.
  const profile = contract("wire/snapshot-v2-profile.json");
  const snapshot = {
    ...profile,
    load: { ...profile.load, days_since_last_hard_session: 3 },
    sports: profile.sports.map((state: { sport: string }) =>
      state.sport === "bike" ? { ...state, minutes_last_seven_days: 30, meters_last_seven_days: 14_000, load_last_seven_days: 24 } : state
    )
  };
  // Gesamtplan mit Ziel in sechs Wochen, damit alle Phasen vorkommen und die Datei kurz bleibt.
  const goalDate = "2026-11-08T08:00:00Z";
  const near = { ...snapshot, goal: { ...snapshot.goal, target_date: goalDate, days_until_goal: 39 }, training_goal: { ...snapshot.training_goal, target_date: goalDate, days_until_goal: 39 } };

  function appWith(complete: jest.Mock, store = new MemoryDayPlanStoreV2()) {
    const service = new MultiPlanService({ generator: { complete }, store, budget: new GenerationBudget(100, 100), logger, timezone: "Europe/Berlin", now });
    return buildApp({ registerV1Routes: multiRoutes(service) });
  }

  /** Was Claude fuer Woche und Gesamtplan liefert, aus der Antwort im Vertrag zurueckgebaut. */
  const rawWeek = (plan: any) => ({
    rationale: plan.rationale,
    days: plan.days.map((day: any) => ({
      date: day.date,
      focus: day.focus,
      sessions: day.sessions.map((item: any) => ({
        sport: item.sport,
        session_type: item.session_type,
        intensity: item.intensity,
        amount: item.amount,
        focus: item.focus,
        test_id: item.test?.id ?? null,
        brick: item.brick,
        indoor: item.indoor
      })),
      extras: day.extras
    }))
  });
  const supplements = { strength_per_week: 1, mobility_per_week: 2 };
  const rawWeeks = (weeks: any[]) =>
    weeks.map((week) => ({ week_start: week.week_start, deload: week.deload, focus: week.focus, sports: week.sports.map((entry: any) => ({ sport: entry.sport, amount: entry.amount, sessions: entry.sessions })) }));
  // So liefert Claude den Gesamtplan: in Abschnitten, hier jede Woche ein eigener.
  const rawBlocks = (weeks: any[]) =>
    rawWeeks(weeks).map((week) => ({
      weeks: 1,
      deload_last: week.deload,
      focus: week.focus,
      sports: week.sports.map((entry: any) => ({ sport: entry.sport, start_amount: entry.amount, end_amount: entry.amount, deload_amount: week.deload ? entry.amount : null, sessions: entry.sessions }))
    }));
  const targets = (weeks: any[]) =>
    weeks.map((week) => ({ ...rawWeeks([week])[0], phase: week.phase, tests: week.tests.map((test: any) => ({ sport: test.sport, test_id: test.test_id })) }));

  async function expectContract(file: string, app: ReturnType<typeof appWith>, path: string, body: object) {
    const fixture = contract(file);
    const response = await request(app).post(path).set(auth).send(body);

    expect(response.status).toBe(200);
    expect(response.body.plan_version).toBe(2);
    expect(sorted(keyPaths(response.body))).toEqual(sorted(keyPaths(fixture)));
    return { fixture, response };
  }

  it("antwortet auf /v1/plan/today mit Plan v2 mit genau den Feldern des Vertrags, Leistungstest eingeschlossen", async () => {
    const fixture = contract("wire/plan-v2-today-response.json");
    const { response } = await expectContract("wire/plan-v2-today-response.json", appWith(generated(asRawDayPlan(fixture.plan))), "/v1/plan/today", {
      plan_version: 2,
      snapshot,
      wishes: fixture.wishes,
      supplements
    });

    expect(response.body.plan.sessions.map((item: { test: { id: string } | null }) => item.test?.id ?? null)).toEqual([null, "threshold_30min"]);
    expect(response.body.plan.sessions.map((item: { unit: string }) => item.unit)).toEqual(["meters", "minutes"]);
  });

  it("antwortet bei Claude-Ausfall mit Plan v2 mit genau den Feldern des Fallback-Vertrags", async () => {
    const fixture = contract("wire/plan-v2-today-fallback-response.json");
    const store = new MemoryDayPlanStoreV2({ date: fixture.date, hash: "alt", generatedAt: fixture.generated_at, model: "claude-opus-5-5", plan: fixture.plan, adjustments: [] });
    const { response } = await expectContract(
      "wire/plan-v2-today-fallback-response.json",
      appWith(jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store),
      "/v1/plan/today",
      { plan_version: 2, snapshot }
    );

    expect(response.body).toMatchObject({ source: "fallback", stale: true, fallback_reason: "timeout" });
  });

  it("antwortet auf /v1/plan/week mit Plan v2 mit genau den Feldern des Vertrags", async () => {
    const fixture = contract("wire/plan-v2-week-response.json");
    const macroWeek = { week_start: "2026-09-28", phase: "base", deload: false, focus: "Grundlage", sports: [{ sport: "swim", amount: 3500, sessions: 2 }, { sport: "bike", amount: 110, sessions: 2 }, { sport: "run", amount: 40, sessions: 2 }], tests: [{ sport: "bike", test_id: "threshold_30min" }] };
    const { response } = await expectContract("wire/plan-v2-week-response.json", appWith(generated(rawWeek(fixture.plan))), "/v1/plan/week", {
      plan_version: 2,
      snapshot,
      from_date: fixture.from_date,
      today: fixture.from_date,
      wishes: fixture.wishes,
      macro_weeks: [macroWeek],
      supplements
    });

    expect(response.body.plan.days.flatMap((day: any) => day.sessions.filter((item: any) => item.test !== null).map((item: any) => `${day.date} ${item.test.id}`))).toEqual(["2026-10-02 threshold_30min"]);
    expect(response.body.plan.days[4].sessions.map((item: any) => [item.sport, item.brick, item.indoor])).toEqual([["bike", false, true]]);
    expect(response.body.plan.days.map((day: any) => day.extras.map((extra: any) => extra.kind))).toEqual([[], ["mobility"], [], ["strength"], [], [], []]);
    expect(response.body.adjustments).toEqual([]);
  });

  it("antwortet auf /v1/plan/macro mit Plan v2 mit genau den Feldern des Vertrags", async () => {
    const fixture = contract("wire/plan-v2-macro-response.json");
    const { response } = await expectContract("wire/plan-v2-macro-response.json", appWith(generated({ rationale: fixture.plan.rationale, blocks: rawBlocks(fixture.plan.weeks) })), "/v1/plan/macro", {
      plan_version: 2,
      snapshot: near,
      today: "2026-09-30"
    });

    expect(response.body.plan.weeks.map((week: { phase: string }) => week.phase)).toEqual(["specific", "specific", "specific", "specific", "taper", "goal_week"]);
  });

  it("antwortet auf /v1/plan/macro/review mit genau den Feldern des Vertrags", async () => {
    const before = contract("wire/plan-v2-macro-response.json");
    const fixture = contract("wire/plan-v2-review-response.json");
    const raw = { rationale: fixture.plan.rationale, summary: fixture.summary, changes: fixture.changes, blocks: rawBlocks(fixture.plan.weeks) };
    await expectContract("wire/plan-v2-review-response.json", appWith(generated(raw)), "/v1/plan/macro/review", {
      plan_version: 2,
      snapshot: near,
      today: "2026-09-30",
      plan: { rationale: before.plan.rationale, weeks: targets(before.plan.weeks) },
      actual: [{ week_start: "2026-09-21", sports: [{ sport: "swim", amount: 3400, sessions: 2 }] }],
      reason: fixture.reason,
      feedback: fixture.feedback
    });
  });

  it("antwortet auf /v1/plan/macro/revise mit genau den Feldern des Vertrags", async () => {
    const before = contract("wire/plan-v2-macro-response.json");
    const fixture = contract("wire/plan-v2-revise-response.json");
    const raw = { rationale: fixture.plan.rationale, changes: fixture.changes, blocks: rawBlocks(fixture.plan.weeks) };
    await expectContract("wire/plan-v2-revise-response.json", appWith(generated(raw)), "/v1/plan/macro/revise", {
      plan_version: 2,
      snapshot: near,
      today: "2026-09-30",
      plan: { rationale: before.plan.rationale, weeks: targets(before.plan.weeks) },
      feedback: fixture.feedback,
      history: []
    });
  });
});
