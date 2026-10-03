import { readFileSync } from "node:fs";
import path from "node:path";
import request from "supertest";
import { createLogger } from "../src/logger";
import { GenerationBudget } from "../src/plan/budget";
import { PlanGenerationError } from "../src/plan/errors";
import { macroRoutes } from "../src/plan/macroRoutes";
import { MacroPlanService } from "../src/plan/macroService";
import { planRoutes } from "../src/plan/routes";
import { PlanService } from "../src/plan/service";
import { SnapshotSchema } from "../src/plan/snapshot";
import { MemoryPlanStore } from "../src/plan/store";
import { weekRoutes } from "../src/plan/weekRoutes";
import { WeekPlanService } from "../src/plan/weekService";
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

describe("contracts/wire", () => {
  const snapshot = contract("wire/snapshot-v1.json");

  it("nimmt den Snapshot der App vollstaendig an (kein Feld wird verworfen)", () => {
    const parsed = SnapshotSchema.safeParse(snapshot);
    expect(parsed.success).toBe(true);
    expect(sorted(keyPaths(parsed.data))).toEqual(sorted(keyPaths(snapshot)));
  });

  it.each(["wire/snapshot-v2.json", "wire/snapshot-v2-profile.json"])("nimmt %s der App vollstaendig an (kein Feld wird verworfen)", (file) => {
    const v2 = contract(file);
    const parsed = SnapshotSchema.safeParse(v2);
    expect(parsed.success).toBe(true);
    expect(sorted(keyPaths(parsed.data))).toEqual(sorted(keyPaths(v2)));
  });

  it.each([
    ["/v1/plan/today", (snapshot: unknown) => ({ snapshot })],
    ["/v1/plan/week", (snapshot: unknown) => ({ snapshot, from_date: "2026-09-30", today: "2026-09-30" })],
    ["/v1/plan/macro", (snapshot: unknown) => ({ snapshot, today: "2026-09-30" })]
  ])("%s nimmt Snapshot v2 an", async (path, body) => {
    const today = contract("wire/plan-today-response.json");
    const week = contract("wire/plan-week-response.json");
    const macro = contract("wire/plan-macro-response.json");
    const deps = { budget: new GenerationBudget(100, 100), logger, now };
    const app = buildApp({
      registerV1Routes: (router) => {
        planRoutes(new PlanService({ ...deps, generator: { generate: generated(today.plan) }, store: new MemoryPlanStore(), timezone: "Europe/Berlin" }))(router);
        weekRoutes(new WeekPlanService({ ...deps, generator: { generateWeek: generated({ rationale: week.plan.rationale, days: week.plan.days }) } }))(router);
        macroRoutes(
          new MacroPlanService({
            ...deps,
            generator: { generateMacro: generated({ rationale: macro.plan.rationale, weeks: macro.plan.weeks.map(({ phase: _phase, ...w }: { phase: string }) => w) }) }
          })
        )(router);
      }
    });

    const response = await request(app).post(path).set(auth).send(body(contract("wire/snapshot-v2.json")));

    expect(response.status).toBe(200);
  });

  it("antwortet auf /v1/plan/today mit genau den Feldern des Vertrags", async () => {
    const fixture = contract("wire/plan-today-response.json");
    const service = new PlanService({
      generator: { generate: generated(fixture.plan) },
      store: new MemoryPlanStore(),
      budget: new GenerationBudget(100, 100),
      logger,
      timezone: "Europe/Berlin",
      now
    });

    const response = await request(buildApp({ registerV1Routes: planRoutes(service) }))
      .post("/v1/plan/today")
      .set(auth)
      .send({ snapshot, wishes: fixture.wishes });

    expect(response.status).toBe(200);
    expect(sorted(keyPaths(response.body))).toEqual(sorted(keyPaths(fixture)));
  });

  it("antwortet bei Claude-Ausfall mit genau den Feldern des Fallback-Vertrags", async () => {
    const fixture = contract("wire/plan-today-fallback-response.json");
    const service = new PlanService({
      generator: { generate: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")) },
      store: new MemoryPlanStore({
        date: fixture.date,
        snapshotHash: "alt",
        generatedAt: fixture.generated_at,
        model: "claude-opus-5-5",
        plan: fixture.plan,
        adjustments: []
      }),
      budget: new GenerationBudget(100, 100),
      logger,
      timezone: "Europe/Berlin",
      now
    });

    const response = await request(buildApp({ registerV1Routes: planRoutes(service) }))
      .post("/v1/plan/today")
      .set(auth)
      .send({ snapshot });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ source: "fallback", stale: true, fallback_reason: "timeout" });
    expect(sorted(keyPaths(response.body))).toEqual(sorted(keyPaths(fixture)));
  });

  it("antwortet auf /v1/plan/week mit genau den Feldern des Vertrags", async () => {
    const fixture = contract("wire/plan-week-response.json");
    const service = new WeekPlanService({
      generator: { generateWeek: generated({ rationale: fixture.plan.rationale, days: fixture.plan.days }) },
      budget: new GenerationBudget(100, 100),
      logger,
      now
    });

    const response = await request(buildApp({ registerV1Routes: weekRoutes(service) }))
      .post("/v1/plan/week")
      .set(auth)
      .send({ snapshot, week_start: fixture.week_start, from_date: "2026-09-30", today: "2026-09-30", wishes: fixture.wishes });

    expect(response.status).toBe(200);
    expect(sorted(keyPaths(response.body))).toEqual(sorted(keyPaths(fixture)));
  });

  it("antwortet auf /v1/plan/macro mit genau den Feldern des Vertrags", async () => {
    const fixture = contract("wire/plan-macro-response.json");
    const weeks = fixture.plan.weeks.map(({ phase: _phase, ...week }: { phase: string }) => week);
    const service = new MacroPlanService({
      generator: { generateMacro: generated({ rationale: fixture.plan.rationale, weeks }) },
      budget: new GenerationBudget(100, 100),
      logger,
      now
    });

    const response = await request(buildApp({ registerV1Routes: macroRoutes(service) }))
      .post("/v1/plan/macro")
      .set(auth)
      .send({ snapshot, today: "2026-09-30" });

    expect(response.status).toBe(200);
    expect(sorted(keyPaths(response.body))).toEqual(sorted(keyPaths(fixture)));
  });
});
