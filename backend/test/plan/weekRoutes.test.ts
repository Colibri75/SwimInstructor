import request from "supertest";
import { GenerationBudget } from "../../src/plan/budget";
import { PlanGenerationError } from "../../src/plan/errors";
import { weekRoutes } from "../../src/plan/weekRoutes";
import { WeekPlanService } from "../../src/plan/weekService";
import { createLogger } from "../../src/logger";
import { buildApp, TEST_TOKEN, testConfig } from "../helpers";
import { snapshot } from "./fixtures";
import { goodWeek, TODAY, WEEK_START } from "./weekFixtures";

const auth = { Authorization: `Bearer ${TEST_TOKEN}` };

function appWith(generateWeek: jest.Mock | null) {
  const service = new WeekPlanService({
    generator: generateWeek === null ? null : { generateWeek },
    budget: new GenerationBudget(100, 100),
    logger: createLogger(testConfig),
    now: () => new Date("2026-09-30T10:00:00Z")
  });
  return buildApp({ registerV1Routes: weekRoutes(service) });
}

const ok = () => jest.fn().mockResolvedValue({ raw: goodWeek(), model: "claude-opus-5-5", usage: { inputTokens: 1, outputTokens: 1 } });
const body = (extra: Record<string, unknown> = {}) => ({ snapshot: snapshot(), week_start: WEEK_START, from_date: TODAY, today: TODAY, ...extra });

describe("POST /v1/plan/week", () => {
  it("verlangt den Token", async () => {
    expect((await request(appWith(ok())).post("/v1/plan/week").send(body())).status).toBe(401);
  });

  it("liefert den Wochenplan im erwarteten Format", async () => {
    const response = await request(appWith(ok())).post("/v1/plan/week").set(auth).send(body());

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ week_start: WEEK_START, generated_at: "2026-09-30T10:00:00.000Z", adjustments: [] });
    expect(response.body.plan.total_distance_meters).toBe(3600);
    expect(response.body.plan.days).toHaveLength(5);
    expect(response.body.plan.days[0]).toMatchObject({ date: "2026-09-30", session_type: "endurance", target_distance_meters: 1200 });
    expect(response.body.wishes).toBeUndefined();
  });

  it("plant ohne week_start die sieben Tage ab from_date und reicht Vorwoche und Gesamtplan weiter", async () => {
    const generateWeek = ok();
    const macroWeeks = [{ week_start: "2026-09-28", phase: "specific", target_meters: 3500, sessions: 3, deload: false, focus: "Ausdauer" }];

    const response = await request(appWith(generateWeek))
      .post("/v1/plan/week")
      .set(auth)
      .send({ snapshot: snapshot(), from_date: TODAY, today: TODAY, recent_swim: [{ date: "2026-09-27", meters: 1200 }], macro_weeks: macroWeeks });

    expect(response.status).toBe(200);
    expect(response.body.week_start).toBe(TODAY);
    expect(response.body.plan.days).toHaveLength(7);
    const input = generateWeek.mock.calls[0][0];
    expect(input.context.dates).toHaveLength(7);
    expect(input.context.recentSwim).toEqual([{ date: "2026-09-27", meters: 1200 }]);
    expect(input.macroWeeks).toEqual(macroWeeks);
  });

  it("reicht Wunsch, Tage ohne Zeit und Geschwommenes weiter und meldet den Wunsch zurueck", async () => {
    const generateWeek = ok();

    const response = await request(appWith(generateWeek))
      .post("/v1/plan/week")
      .set(auth)
      .send(body({ wishes: "mehr Technik", unavailable_dates: ["2026-10-02"], swum_this_week: [{ date: "2026-09-28", meters: 900 }] }));

    expect(response.status).toBe(200);
    expect(response.body.wishes).toBe("mehr Technik");
    expect(generateWeek.mock.calls[0][0].context.swumBefore).toEqual([{ date: "2026-09-28", meters: 900 }]);
  });

  it.each([
    ["Snapshot fehlt", { snapshot: undefined }, "snapshot"],
    ["week_start ist kein Datum", { week_start: "Montag" }, "week_start"],
    ["unmoegliches Datum", { week_start: "2026-02-30" }, "week_start"],
    ["week_start ist kein Montag", { week_start: "2026-09-29" }, "week_start"],
    ["from_date vor der Woche", { from_date: "2026-09-27" }, "from_date"],
    ["from_date nach der Woche", { from_date: "2026-10-05" }, "from_date"],
    ["Tag ohne Zeit ist kein Datum", { unavailable_dates: ["morgen"] }, "unavailable_dates.0"],
    ["unmoeglicher Tag ohne Zeit", { unavailable_dates: ["2026-02-30"] }, "unavailable_dates.0"],
    ["unmoegliches Geschwommen-Datum", { swum_this_week: [{ date: "2026-02-30", meters: 100 }] }, "swum_this_week.0.date"],
    ["negative Meter", { swum_this_week: [{ date: "2026-09-28", meters: -1 }] }, "swum_this_week.0.meters"],
    ["zu langer Wunsch", { wishes: "x".repeat(501) }, "wishes"],
    ["unbekanntes Equipment", { equipment: ["jetpack"] }, "equipment.0"],
    ["Gesamtplan-Woche kein Montag", { macro_weeks: [{ week_start: "2026-09-29", phase: "base", target_meters: 3000, sessions: 3, deload: false, focus: "x" }] }, "macro_weeks.0.week_start"],
    ["Gesamtplan mit unbekannter Phase", { macro_weeks: [{ week_start: "2026-09-28", phase: "sprint", target_meters: 3000, sessions: 3, deload: false, focus: "x" }] }, "macro_weeks.0.phase"],
    ["Vorwoche mit unmoeglichem Datum", { recent_swim: [{ date: "2026-02-30", meters: 100 }] }, "recent_swim.0.date"],
    ["zu viele Tage ohne Zeit", { unavailable_dates: Array(8).fill("2026-10-01") }, "unavailable_dates"]
  ])("lehnt ab: %s", async (_name, extra, path) => {
    const response = await request(appWith(ok())).post("/v1/plan/week").set(auth).send(body(extra));

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("invalid_request");
    expect(response.body.details.some((d: { path: string }) => d.path === path)).toBe(true);
  });

  it("antwortet 503 mit Grund, wenn Claude ausfaellt", async () => {
    const response = await request(appWith(jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "zu langsam"))))
      .post("/v1/plan/week")
      .set(auth)
      .send(body());

    expect(response.status).toBe(503);
    expect(response.body).toEqual({ error: "plan_unavailable", reason: "timeout" });
  });

  it("antwortet 503 not_configured ohne API-Key", async () => {
    const response = await request(appWith(null)).post("/v1/plan/week").set(auth).send(body());

    expect(response.status).toBe(503);
    expect(response.body.reason).toBe("not_configured");
  });

  it("gibt unerwartete Fehler an die Fehlerbehandlung weiter (500 ohne Details)", async () => {
    const broken = { planWeek: jest.fn().mockRejectedValue(new Error("interne Details")) } as unknown as WeekPlanService;
    const app = buildApp({ registerV1Routes: weekRoutes(broken) });

    const response = await request(app).post("/v1/plan/week").set(auth).send(body());

    expect(response.status).toBe(500);
    expect(JSON.stringify(response.body)).not.toContain("interne Details");
  });
});
