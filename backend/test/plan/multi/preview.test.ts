import request from "supertest";
import { GenerationBudget } from "../../../src/plan/budget";
import { multiRoutes } from "../../../src/plan/multi/routes";
import { MultiPlanService, PREVIEW_DAYS } from "../../../src/plan/multi/service";
import { MemoryDayPlanStoreV2 } from "../../../src/plan/multi/store";
import { createLogger } from "../../../src/logger";
import { buildApp, TEST_TOKEN, testConfig } from "../../helpers";
import { dayPlan, multiSnapshot, session, swimStep, TODAY } from "./fixtures";

/** Vorschau eines kommenden Tags im Plan-Tab: `date` beim Tagesplan. */
describe("Tagesplan als Vorschau fuer einen kommenden Tag", () => {
  const auth = { Authorization: `Bearer ${TEST_TOKEN}` };
  const raw = dayPlan([session("swim", { steps: [swimStep(300, { name: "Einschwimmen" }), swimStep(800), swimStep(200, { name: "Ausschwimmen" })] })]);

  function setup() {
    const complete = jest.fn().mockResolvedValue({ raw, model: "m", usage: { inputTokens: 1, outputTokens: 1 } });
    const store = new MemoryDayPlanStoreV2();
    const forecast = jest.fn().mockResolvedValue([]);
    const service = new MultiPlanService({
      generator: { complete },
      store,
      budget: new GenerationBudget(100, 100),
      weather: { forecast },
      logger: createLogger(testConfig),
      timezone: "Europe/Berlin",
      now: () => new Date("2026-09-30T10:00:00Z")
    });
    return { app: buildApp({ registerV1Routes: multiRoutes(service) }), complete, store, forecast };
  }

  const body = (patch: Record<string, unknown> = {}) => ({
    plan_version: 2,
    snapshot: multiSnapshot(),
    day_plan: { sessions: [{ sport: "swim", session_type: "endurance", intensity: "easy", amount: 1300, focus: "Grundlage" }] },
    ...patch
  });

  it("plant den Tag mit seinem Datum, ohne den Plan von heute zu ersetzen", async () => {
    const { app, complete, store, forecast } = setup();

    const response = await request(app)
      .post("/v1/plan/today")
      .set(auth)
      .send(body({ date: "2026-10-02", location: { latitude: 52.5, longitude: 13.4 } }));

    expect(response.status).toBe(200);
    expect(response.body.date).toBe("2026-10-02");
    expect(response.body.source).toBe("claude");
    expect(response.body.plan.sessions[0].steps.length).toBe(3);
    expect(complete.mock.calls[0][1]).toContain("Erstelle die Einheiten für Freitag, 2026-10-02. Das ist eine Vorschau");
    expect(forecast).toHaveBeenCalledWith({ latitude: 52.5, longitude: 13.4 }, ["2026-10-02"]);
    expect(await store.latest()).toBeNull();
  });

  it("heute als Datum ist der normale Tagesplan", async () => {
    const { app, store } = setup();

    const response = await request(app).post("/v1/plan/today").set(auth).send(body({ date: TODAY }));

    expect(response.status).toBe(200);
    expect(response.body.date).toBe(TODAY);
    expect((await store.latest())?.date).toBe(TODAY);
  });

  it("lehnt Tage in der Vergangenheit, zu weit voraus und ungueltige Tage ab", async () => {
    const { app, complete } = setup();

    const past = await request(app).post("/v1/plan/today").set(auth).send(body({ date: "2026-09-29" }));
    const far = await request(app).post("/v1/plan/today").set(auth).send(body({ date: "2026-10-31" }));
    const invalid = await request(app).post("/v1/plan/today").set(auth).send(body({ date: "2026-02-30" }));

    expect([past.status, far.status, invalid.status]).toEqual([400, 400, 400]);
    expect(far.body.details[0]).toEqual({ path: "date", message: `Vorschau nur für die nächsten ${PREVIEW_DAYS} Tage` });
    expect(invalid.body.details[0].path).toBe("date");
    expect(complete).not.toHaveBeenCalled();
  });

  it("antwortet ohne Fallback mit 503, wenn Claude ausfaellt", async () => {
    const { app, complete } = setup();
    complete.mockRejectedValue(Object.assign(new Error("weg"), { name: "PlanGenerationError", reason: "timeout" }));

    const response = await request(app).post("/v1/plan/today").set(auth).send(body({ date: "2026-10-01" }));

    expect(response.status).toBe(503);
  });
});
