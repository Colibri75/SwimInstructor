import request from "supertest";
import { GenerationBudget } from "../../../src/plan/budget";
import { PlanGenerationError } from "../../../src/plan/errors";
import { macroWeekStarts } from "../../../src/plan/macro";
import { macroRoutes } from "../../../src/plan/macroRoutes";
import { MacroPlanService } from "../../../src/plan/macroService";
import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { multiRoutes } from "../../../src/plan/multi/routes";
import { MacroWeekTargetV2 } from "../../../src/plan/multi/schemas";
import { MultiPlanService } from "../../../src/plan/multi/service";
import { MemoryDayPlanStoreV2 } from "../../../src/plan/multi/store";
import { planRoutes } from "../../../src/plan/routes";
import { PlanService } from "../../../src/plan/service";
import { MemoryPlanStore } from "../../../src/plan/store";
import { weekRoutes } from "../../../src/plan/weekRoutes";
import { WeekPlanService } from "../../../src/plan/weekService";
import { createLogger } from "../../../src/logger";
import { buildApp, TEST_TOKEN, testConfig } from "../../helpers";
import { goodPlan, snapshot as snapshotV1 } from "../fixtures";
import { goodMacro as goodMacroV1, MACRO_TODAY } from "../macroFixtures";
import { goodWeek as goodWeekV1, WEEK_START } from "../weekFixtures";
import { dayPlan, macroPlan, multiSnapshot, session, swimStep, TODAY, weekPlan, weekSession } from "./fixtures";

const auth = { Authorization: `Bearer ${TEST_TOKEN}` };
const NOW_ISO = "2026-09-30T10:00:00.000Z";
const GOAL_DAY = "2027-07-04";
const WEEKS = macroWeekStarts(TODAY, GOAL_DAY);

const claude = (raw: unknown) => jest.fn().mockResolvedValue({ raw, model: "claude-opus-5-5", usage: { inputTokens: 1, outputTokens: 1 } });
const timeout = () => jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "zu langsam"));

const goodDay = () => dayPlan([session("swim", { steps: [swimStep(300, { name: "Einschwimmen" }), swimStep(400), swimStep(150, { name: "Ausschwimmen" })] })]);
const goodWeek = () => weekPlan([[weekSession("swim", 800)], [weekSession("bike", 45)], [], [weekSession("run", 20)], [weekSession("swim", 1500)], [], [weekSession("bike", 60)]]);
const goodMacro = () => macroPlan(WEEKS, () => ({ swim: 3000, bike: 90, run: 30 }), (index) => index % 4 === 3);
const revision = (changes: string[]) => ({ ...goodMacro(), changes });

const currentWeeks: MacroWeekTargetV2[] = WEEKS.slice(0, 2).map((week_start) => ({
  week_start,
  phase: "base",
  deload: false,
  focus: "Grundlage",
  sports: [
    { sport: "swim", amount: 3000, sessions: 3 },
    { sport: "bike", amount: 90, sessions: 2 }
  ],
  tests: [{ sport: "bike", test_id: "threshold_30min" }]
}));

type Body = Record<string, unknown>;
const dayBody = (extra: Body = {}) => ({ plan_version: 2, snapshot: multiSnapshot(), ...extra });
const weekBody = (extra: Body = {}) => ({ plan_version: 2, snapshot: multiSnapshot(), from_date: TODAY, today: TODAY, ...extra });
const macroBody = (extra: Body = {}) => ({ plan_version: 2, snapshot: multiSnapshot(), today: TODAY, ...extra });
const reviseBody = (extra: Body = {}) => ({ plan_version: 2, snapshot: multiSnapshot(), today: TODAY, plan: { weeks: currentWeeks }, feedback: "Bitte mehr Schwimmen", ...extra });

/** Wie in server.ts: Plan v2 vor den Routen von v1 auf denselben Pfaden. */
function appWith(complete: jest.Mock | null, store = new MemoryDayPlanStoreV2()) {
  const logger = createLogger(testConfig);
  const budget = new GenerationBudget(100, 100);
  const now = () => new Date("2026-09-30T10:00:00Z");
  const v1 = { generate: claude(goodPlan), generateWeek: claude(goodWeekV1()), generateMacro: claude(goodMacroV1()) };

  const registerMultiRoutes = multiRoutes(new MultiPlanService({ generator: complete === null ? null : { complete }, store, budget, logger, timezone: "Europe/Berlin", now }));
  const registerPlanRoutes = planRoutes(new PlanService({ generator: { generate: v1.generate }, store: new MemoryPlanStore(), budget, logger, timezone: "Europe/Berlin", now }));
  const registerWeekRoutes = weekRoutes(new WeekPlanService({ generator: { generateWeek: v1.generateWeek }, budget, logger, now }));
  const registerMacroRoutes = macroRoutes(new MacroPlanService({ generator: { generateMacro: v1.generateMacro }, budget, logger, now }));
  const app = buildApp({
    registerV1Routes: (router) => {
      registerMultiRoutes(router);
      registerPlanRoutes(router);
      registerWeekRoutes(router);
      registerMacroRoutes(router);
    }
  });
  return { app, v1 };
}

function detailPaths(body: { details?: Array<{ path: string }> }): string[] {
  return (body.details ?? []).map((detail) => detail.path);
}

describe("Plan v2: Token", () => {
  it.each([
    ["/v1/plan/today", dayBody()],
    ["/v1/plan/week", weekBody()],
    ["/v1/plan/macro", macroBody()],
    ["/v1/plan/macro/revise", reviseBody()]
  ])("%s verlangt den Token", async (path, body) => {
    const complete = claude(goodDay());

    const response = await request(appWith(complete).app).post(path).send(body);

    expect(response.status).toBe(401);
    expect(complete).not.toHaveBeenCalled();
  });
});

describe("POST /v1/plan/today mit plan_version 2", () => {
  it("liefert den Tagesplan v2 im erwarteten Format", async () => {
    const complete = claude(goodDay());
    const { app, v1 } = appWith(complete);

    const response = await request(app).post("/v1/plan/today").set(auth).send(dayBody());

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ plan_version: 2, source: "claude", date: TODAY, generated_at: NOW_ISO, stale: false, adjustments: [] });
    expect(response.body.plan.sessions).toHaveLength(1);
    expect(response.body.plan.sessions[0]).toMatchObject({ sport: "swim", session_type: "endurance", intensity: "easy", amount: 850, unit: "meters", test: null });
    expect(response.body.plan.sessions[0].steps).toHaveLength(3);
    expect(response.body.plan.rationale).toContain("3500 m");
    expect(response.body).not.toHaveProperty("fallback_reason");
    expect(response.body).not.toHaveProperty("wishes");
    expect(complete).toHaveBeenCalledTimes(1);
    expect(v1.generate).not.toHaveBeenCalled();
  });

  it("meldet den Wunsch zurueck und liefert beim zweiten Aufruf aus dem Cache", async () => {
    const complete = claude(goodDay());
    const { app } = appWith(complete);

    const first = await request(app).post("/v1/plan/today").set(auth).send(dayBody({ wishes: "  Schulter schonen " }));
    const second = await request(app).post("/v1/plan/today").set(auth).send(dayBody({ wishes: "Schulter schonen" }));

    expect(first.body).toMatchObject({ source: "claude", wishes: "Schulter schonen" });
    expect(second.body).toMatchObject({ plan_version: 2, source: "cache", wishes: "Schulter schonen" });
    expect(complete).toHaveBeenCalledTimes(1);
  });

  it("liefert bei einem Ausfall den letzten gueltigen Plan mit Grund", async () => {
    const plan = sanitizeDayV2(goodDay(), multiSnapshot(), { date: "2026-09-29" }).plan;
    const store = new MemoryDayPlanStoreV2({ date: "2026-09-29", hash: "alt", generatedAt: "2026-09-29T10:00:00.000Z", model: "claude-opus-5-5", plan, adjustments: [] });

    const response = await request(appWith(timeout(), store).app).post("/v1/plan/today").set(auth).send(dayBody());

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ plan_version: 2, source: "fallback", fallback_reason: "timeout", date: "2026-09-29", stale: true });
    expect(response.body.plan.sessions[0].sport).toBe("swim");
  });

  it("lehnt einen Snapshot v1 ab, statt an v1 weiterzureichen", async () => {
    const complete = claude(goodDay());
    const { app, v1 } = appWith(complete);

    const response = await request(app).post("/v1/plan/today").set(auth).send(dayBody({ snapshot: snapshotV1() }));

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("invalid_request");
    expect(response.body.details).toContainEqual({ path: "snapshot.schema_version", message: "Plan v2 braucht Snapshot v2" });
    expect(complete).not.toHaveBeenCalled();
    expect(v1.generate).not.toHaveBeenCalled();
  });

  it("lehnt ein Datum im Verlauf ab, das es nicht gibt", async () => {
    const response = await request(appWith(claude(goodDay())).app)
      .post("/v1/plan/today")
      .set(auth)
      .send(dayBody({ recent_training: [{ date: "2026-02-30", sport: "swim", minutes: 40, meters: 2000 }] }));

    expect(response.status).toBe(400);
    expect(response.body).toEqual({ error: "invalid_request", details: [{ path: "recent_training.0.date", message: "kein gültiger Kalendertag" }] });
  });

  it.each([
    ["zu langer Wunsch", { wishes: "x".repeat(501) }, "wishes"],
    ["Equipment mit ungueltiger Kennung", { equipment: ["Flossen!"] }, "equipment.0"],
    ["unbekannte Sportart im Verlauf", { recent_training: [{ date: "2026-09-29", sport: "curling", minutes: 40, meters: 0 }] }, "recent_training.0.sport"],
    ["Vorgabe mit mehr als zwei Einheiten", { day_plan: { sessions: Array.from({ length: 3 }, () => ({ sport: "swim", session_type: "endurance", intensity: "easy", amount: 500, focus: "x" })) } }, "day_plan.sessions"],
    ["Snapshot fehlt", { snapshot: undefined }, "snapshot"]
  ])("lehnt ab: %s", async (_name, extra, path) => {
    const response = await request(appWith(claude(goodDay())).app).post("/v1/plan/today").set(auth).send(dayBody(extra));

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("invalid_request");
    expect(detailPaths(response.body)).toContain(path);
  });

  it.each([
    ["ohne Key", null, "not_configured"],
    ["bei Zeitueberschreitung", timeout(), "timeout"]
  ])("antwortet 503 mit Grund, wenn es keinen Plan gibt (%s)", async (_name, complete, reason) => {
    const response = await request(appWith(complete).app).post("/v1/plan/today").set(auth).send(dayBody());

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: "plan_unavailable", reason });
  });
});

describe("POST /v1/plan/today ohne plan_version 2 (alte App)", () => {
  it.each([
    ["ohne plan_version", {}],
    ["mit plan_version 1", { plan_version: 1 }],
    ['mit plan_version "2" als Text', { plan_version: "2" }]
  ])("geht %s unveraendert an v1", async (_name, extra) => {
    const complete = claude(goodDay());
    const { app, v1 } = appWith(complete);

    const response = await request(app).post("/v1/plan/today").set(auth).send({ snapshot: snapshotV1(), ...extra });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ source: "claude", date: TODAY, stale: false, plan: { session_type: "endurance", total_distance_meters: 1600 } });
    expect(response.body.plan.sets).toHaveLength(3);
    expect(response.body).not.toHaveProperty("plan_version");
    expect(v1.generate).toHaveBeenCalledTimes(1);
    expect(complete).not.toHaveBeenCalled();
  });

  it("liefert die Fehler von v1, nicht die von v2", async () => {
    const response = await request(appWith(claude(goodDay())).app).post("/v1/plan/today").set(auth).send({ wishes: "x" });

    expect(response.status).toBe(400);
    expect(detailPaths(response.body)).toEqual(["snapshot"]);
  });
});

describe("POST /v1/plan/week mit plan_version 2", () => {
  it("liefert die sieben Tage ab from_date", async () => {
    const complete = claude(goodWeek());
    const { app, v1 } = appWith(complete);

    const response = await request(app).post("/v1/plan/week").set(auth).send(weekBody({ wishes: " Mehr Rad " }));

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ plan_version: 2, from_date: TODAY, generated_at: NOW_ISO, adjustments: [], wishes: "Mehr Rad" });
    expect(response.body.plan.days).toHaveLength(7);
    expect(response.body.plan.days[0]).toMatchObject({ date: TODAY, sessions: [{ sport: "swim", amount: 800, unit: "meters" }] });
    expect(response.body.plan.total_minutes).toBe(171);
    expect(v1.generateWeek).not.toHaveBeenCalled();
  });

  it("nimmt die Vorgabe des Gesamtplans an, wenn die Woche an einem Montag beginnt", async () => {
    const complete = claude(goodWeek());

    const response = await request(appWith(complete).app).post("/v1/plan/week").set(auth).send(weekBody({ macro_weeks: [currentWeeks[0]] }));

    expect(response.status).toBe(200);
    expect(complete.mock.calls[0][1]).toContain("Vorgabe aus dem Gesamtplan");
  });

  it("lehnt eine Vorgabe des Gesamtplans ab, deren Woche nicht an einem Montag beginnt", async () => {
    const complete = claude(goodWeek());

    const response = await request(appWith(complete).app)
      .post("/v1/plan/week")
      .set(auth)
      .send(weekBody({ macro_weeks: [{ ...currentWeeks[0], week_start: "2026-09-29" }] }));

    expect(response.status).toBe(400);
    expect(response.body).toEqual({ error: "invalid_request", details: [{ path: "macro_weeks.0.week_start", message: "muss ein Montag sein" }] });
    expect(complete).not.toHaveBeenCalled();
  });

  it.each([
    ["from_date", { from_date: "2026-02-30" }, "from_date"],
    ["today", { today: "2026-13-01" }, "today"],
    ["Tag ohne Zeit", { unavailable_dates: ["2026-10-01", "2026-09-31"] }, "unavailable_dates.1"],
    ["Verlauf", { recent_training: [{ date: "2026-02-29", sport: "bike", minutes: 60, meters: 30_000 }] }, "recent_training.0.date"],
    ["Woche des Gesamtplans", { macro_weeks: [{ ...currentWeeks[0], week_start: "2026-02-30" }] }, "macro_weeks.0.week_start"]
  ])("lehnt ein unmoegliches Datum ab: %s", async (_name, extra, path) => {
    const response = await request(appWith(claude(goodWeek())).app).post("/v1/plan/week").set(auth).send(weekBody(extra));

    expect(response.status).toBe(400);
    expect(response.body.details).toContainEqual({ path, message: "kein gültiger Kalendertag" });
  });

  it("lehnt einen Snapshot v1 ab", async () => {
    const response = await request(appWith(claude(goodWeek())).app).post("/v1/plan/week").set(auth).send(weekBody({ snapshot: snapshotV1() }));

    expect(response.status).toBe(400);
    expect(detailPaths(response.body)).toContain("snapshot.schema_version");
  });

  it("geht ohne plan_version unveraendert an v1", async () => {
    const complete = claude(goodWeek());
    const { app, v1 } = appWith(complete);

    const response = await request(app).post("/v1/plan/week").set(auth).send({ snapshot: snapshotV1(), week_start: WEEK_START, from_date: TODAY, today: TODAY });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ week_start: WEEK_START, adjustments: [] });
    expect(response.body.plan.total_distance_meters).toBe(3600);
    expect(response.body).not.toHaveProperty("plan_version");
    expect(v1.generateWeek).toHaveBeenCalledTimes(1);
    expect(complete).not.toHaveBeenCalled();
  });
});

describe("POST /v1/plan/macro mit plan_version 2", () => {
  it("liefert den Gesamtplan mit Phase, Sportarten und Leistungstests je Woche", async () => {
    const complete = claude(goodMacro());
    const { app, v1 } = appWith(complete);

    const response = await request(app).post("/v1/plan/macro").set(auth).send(macroBody());

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ plan_version: 2, goal_day: GOAL_DAY, generated_at: NOW_ISO });
    expect(Array.isArray(response.body.adjustments)).toBe(true);
    const weeks = response.body.plan.weeks as Array<{ week_start: string; phase: string; sports: Array<{ sport: string }>; tests: unknown[] }>;
    expect(weeks).toHaveLength(40);
    expect(weeks[0]).toMatchObject({ week_start: "2026-09-28", phase: "base" });
    expect(weeks[39]).toMatchObject({ week_start: "2027-06-28", phase: "goal_week" });
    for (const week of weeks) {
      expect(typeof week.phase).toBe("string");
      expect(Array.isArray(week.sports)).toBe(true);
      expect(Array.isArray(week.tests)).toBe(true);
    }
    expect(weeks[0].sports.map((entry) => entry.sport)).toEqual(["swim", "bike", "run"]);
    expect(weeks.some((week) => week.tests.length > 0)).toBe(true);
    expect(v1.generateMacro).not.toHaveBeenCalled();
  });

  it("lehnt ein unmoegliches Datum und einen Snapshot v1 ab", async () => {
    const app = appWith(claude(goodMacro())).app;

    const badDate = await request(app).post("/v1/plan/macro").set(auth).send(macroBody({ today: "2026-02-30" }));
    const oldSnapshot = await request(app).post("/v1/plan/macro").set(auth).send(macroBody({ snapshot: snapshotV1() }));

    expect(badDate.status).toBe(400);
    expect(badDate.body.details).toEqual([{ path: "today", message: "kein gültiger Kalendertag" }]);
    expect(oldSnapshot.status).toBe(400);
    expect(detailPaths(oldSnapshot.body)).toContain("snapshot.schema_version");
  });

  it("geht ohne plan_version unveraendert an v1", async () => {
    const complete = claude(goodMacro());
    const { app, v1 } = appWith(complete);
    const nearGoal = snapshotV1({ goal: { target_date: "2026-11-12T11:00:00Z", days_until_goal: 43 } });

    const response = await request(app).post("/v1/plan/macro").set(auth).send({ snapshot: nearGoal, today: MACRO_TODAY });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ goal_day: "2026-11-12", adjustments: [] });
    expect(response.body.plan.weeks).toHaveLength(7);
    expect(response.body.plan.weeks[0]).toMatchObject({ week_start: "2026-09-28", target_meters: 3500 });
    expect(response.body).not.toHaveProperty("plan_version");
    expect(v1.generateMacro).toHaveBeenCalledTimes(1);
    expect(complete).not.toHaveBeenCalled();
  });
});

describe("POST /v1/plan/macro/revise", () => {
  it.each([
    ["mit plan_version 2", {}],
    ["ohne plan_version (nur v2)", { plan_version: undefined }]
  ])("liefert den geaenderten Gesamtplan mit Aenderungen und Feedback (%s)", async (_name, extra) => {
    const complete = claude(revision(["  Mehr Schwimmen im Winter  ", "", "Laufen später steigern"]));

    const response = await request(appWith(complete).app)
      .post("/v1/plan/macro/revise")
      .set(auth)
      .send(reviseBody({ feedback: "  Bitte mehr Schwimmen im Winter ", history: [{ feedback: "Weniger Laufen", changes: ["Laufen reduziert"] }], ...extra }));

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      plan_version: 2,
      goal_day: GOAL_DAY,
      generated_at: NOW_ISO,
      changes: ["Mehr Schwimmen im Winter", "Laufen später steigern"],
      feedback: "Bitte mehr Schwimmen im Winter"
    });
    expect(response.body.plan.weeks).toHaveLength(40);
    expect(response.body.plan.weeks[0]).toHaveProperty("phase");
    expect(complete.mock.calls[0][1]).toContain(JSON.stringify("Bitte mehr Schwimmen im Winter"));
  });

  it.each([
    ["zu langes Feedback", { feedback: "x".repeat(1001) }, "feedback"],
    ["leeres Feedback", { feedback: "   " }, "feedback"],
    ["Feedback fehlt", { feedback: undefined }, "feedback"],
    ["Plan ohne Wochen", { plan: { weeks: [] } }, "plan.weeks"],
    ["mehr als fuenf fruehere Runden", { history: Array.from({ length: 6 }, () => ({ feedback: "x", changes: [] })) }, "history"],
    ["Snapshot v1", { snapshot: snapshotV1() }, "snapshot.schema_version"],
    ["today kein Kalendertag", { today: "2026-02-30" }, "today"]
  ])("lehnt ab: %s", async (_name, extra, path) => {
    const complete = claude(revision([]));

    const response = await request(appWith(complete).app).post("/v1/plan/macro/revise").set(auth).send(reviseBody(extra));

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("invalid_request");
    expect(detailPaths(response.body)).toContain(path);
    expect(complete).not.toHaveBeenCalled();
  });

  it("nimmt Feedback mit genau 1000 Zeichen an", async () => {
    const response = await request(appWith(claude(revision([]))).app).post("/v1/plan/macro/revise").set(auth).send(reviseBody({ feedback: "x".repeat(1000) }));

    expect(response.status).toBe(200);
  });

  it("lehnt eine Woche des Plans ab, die nicht an einem Montag beginnt", async () => {
    const response = await request(appWith(claude(revision([]))).app)
      .post("/v1/plan/macro/revise")
      .set(auth)
      .send(reviseBody({ plan: { weeks: [currentWeeks[0], { ...currentWeeks[1], week_start: "2026-10-06" }] } }));

    expect(response.status).toBe(400);
    expect(response.body.details).toEqual([{ path: "plan.weeks.1.week_start", message: "muss ein Montag sein" }]);
  });
});

describe("Plan v2: Ausfall von Claude", () => {
  const cases: Array<[string, () => Body]> = [
    ["/v1/plan/week", weekBody],
    ["/v1/plan/macro", macroBody],
    ["/v1/plan/macro/revise", reviseBody]
  ];

  it.each(cases)("%s antwortet ohne Key 503 mit Grund not_configured", async (path, body) => {
    const { app, v1 } = appWith(null);

    const response = await request(app).post(path).set(auth).send(body());

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: "plan_unavailable", reason: "not_configured" });
    expect(v1.generateWeek).not.toHaveBeenCalled();
    expect(v1.generateMacro).not.toHaveBeenCalled();
  });

  it.each(cases)("%s antwortet bei Zeitueberschreitung 503 mit Grund timeout", async (path, body) => {
    const response = await request(appWith(timeout()).app).post(path).set(auth).send(body());

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: "plan_unavailable", reason: "timeout" });
  });

  it("antwortet 503 mit sanity_blocked, wenn die Sicherheitsschicht den Wochenplan blockt", async () => {
    const response = await request(appWith(claude({ ...goodWeek(), rationale: "" })).app).post("/v1/plan/week").set(auth).send(weekBody());

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: "plan_unavailable", reason: "sanity_blocked" });
  });
});
