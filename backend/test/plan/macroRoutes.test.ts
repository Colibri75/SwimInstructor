import request from "supertest";
import { GenerationBudget } from "../../src/plan/budget";
import { PlanGenerationError } from "../../src/plan/errors";
import { macroRoutes } from "../../src/plan/macroRoutes";
import { MacroPlanService } from "../../src/plan/macroService";
import { createLogger } from "../../src/logger";
import { buildApp, TEST_TOKEN, testConfig } from "../helpers";
import { snapshot } from "./fixtures";
import { goodMacro, MACRO_TODAY } from "./macroFixtures";

const auth = { Authorization: `Bearer ${TEST_TOKEN}` };

function appWith(generateMacro: jest.Mock | null) {
  const service = new MacroPlanService({
    generator: generateMacro === null ? null : { generateMacro },
    budget: new GenerationBudget(100, 100),
    logger: createLogger(testConfig),
    now: () => new Date("2026-09-30T10:00:00Z")
  });
  return buildApp({ registerV1Routes: macroRoutes(service) });
}

const ok = () => jest.fn().mockResolvedValue({ raw: goodMacro(), model: "claude-opus-5-5", usage: { inputTokens: 1, outputTokens: 1 } });
const nearGoal = () => snapshot({ goal: { target_date: "2026-11-12T11:00:00Z", days_until_goal: 43 } });
const body = (extra: Record<string, unknown> = {}) => ({ snapshot: nearGoal(), today: MACRO_TODAY, ...extra });

describe("POST /v1/plan/macro", () => {
  it("verlangt den Token", async () => {
    expect((await request(appWith(ok())).post("/v1/plan/macro").send(body())).status).toBe(401);
  });

  it("liefert den Gesamtplan im erwarteten Format", async () => {
    const response = await request(appWith(ok())).post("/v1/plan/macro").set(auth).send(body());

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ goal_day: "2026-11-12", generated_at: "2026-09-30T10:00:00.000Z", adjustments: [] });
    expect(response.body.plan.weeks).toHaveLength(7);
    expect(response.body.plan.weeks[0]).toMatchObject({ week_start: "2026-09-28", phase: "specific", target_meters: 3500, sessions: 3, deload: false });
    expect(response.body.plan.rationale).toContain("Sechs Wochen");
  });

  it.each([
    ["Snapshot fehlt", { snapshot: undefined }, "snapshot"],
    ["today fehlt", { today: undefined }, "today"],
    ["today kein Datum", { today: "heute" }, "today"],
    ["unmoegliches Datum", { today: "2026-02-30" }, "today"]
  ])("lehnt ab: %s", async (_name, extra, path) => {
    const response = await request(appWith(ok())).post("/v1/plan/macro").set(auth).send(body(extra));

    expect(response.status).toBe(400);
    expect(response.body.details.some((d: { path: string }) => d.path === path)).toBe(true);
  });

  it("antwortet 503 mit Grund, wenn Claude ausfaellt oder kein Key da ist", async () => {
    const down = await request(appWith(jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "zu langsam")))).post("/v1/plan/macro").set(auth).send(body());
    const none = await request(appWith(null)).post("/v1/plan/macro").set(auth).send(body());

    expect(down.status).toBe(503);
    expect(down.body).toEqual({ error: "plan_unavailable", reason: "timeout" });
    expect(none.body.reason).toBe("not_configured");
  });
});
