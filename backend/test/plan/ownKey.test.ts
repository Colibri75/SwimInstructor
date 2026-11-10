import request from "supertest";
import { GenerationBudget } from "../../src/plan/budget";
import { PlanGenerationError, PlanUnavailableError } from "../../src/plan/errors";
import { GeneratedPlan } from "../../src/plan/generator";
import { MultiPlanService } from "../../src/plan/multi/service";
import { MemoryDayPlanStoreV2 } from "../../src/plan/multi/store";
import { currentOwnKey, isPlausibleOwnKey, OWN_KEY_HEADER, withOwnKey } from "../../src/plan/ownKey";
import { createLogger } from "../../src/logger";
import { UsageInput } from "../../src/usage";
import { withCost } from "../../src/usage";
import { buildApp, buildAppWithCapturedLogs, TEST_TOKEN, testConfig } from "../helpers";
import { dayPlan, multiSnapshot, session, swimStep } from "./multi/fixtures";

const OWN_KEY = "sk-ant-api03-" + "a".repeat(40);
const logger = createLogger(testConfig);

const generated = (raw: unknown): GeneratedPlan => ({ raw, model: "claude-opus-5-5", usage: { inputTokens: 1000, outputTokens: 1000 } });
const goodDay = () => dayPlan([session("swim", { steps: [swimStep(300, { name: "Einschwimmen" }), swimStep(400), swimStep(150, { name: "Ausschwimmen" })] })]);

function setup(budget = new GenerationBudget(100, 100)) {
  const serverComplete = jest.fn().mockResolvedValue(generated(goodDay()));
  const ownComplete = jest.fn().mockResolvedValue(generated(goodDay()));
  const keys: string[] = [];
  const usage: UsageInput[] = [];
  const service = new MultiPlanService({
    generator: { complete: serverComplete },
    generatorFor: (key) => {
      keys.push(key);
      return { complete: ownComplete };
    },
    store: new MemoryDayPlanStoreV2(),
    budget,
    usage: { record: (event) => usage.push(event) },
    logger,
    timezone: "Europe/Berlin",
    now: () => new Date("2026-09-30T10:00:00Z")
  });
  return { service, serverComplete, ownComplete, keys, usage };
}

describe("Eigener Claude-Schluessel", () => {
  it("plant ohne eigenen Schluessel mit dem Schluessel des Servers", async () => {
    const { service, serverComplete, ownComplete, keys } = setup();

    await service.planDay({ snapshot: multiSnapshot() });

    expect(serverComplete).toHaveBeenCalledTimes(1);
    expect(ownComplete).not.toHaveBeenCalled();
    expect(keys).toEqual([]);
  });

  it("plant mit eigenem Schluessel ueber dessen Konto, ohne Kostenbremse und ohne Kosten fuer den Server", async () => {
    const { service, serverComplete, ownComplete, keys, usage } = setup(new GenerationBudget(0, 0));

    const result = await withOwnKey(OWN_KEY, () => service.planDay({ snapshot: multiSnapshot() }));

    expect(result.source).toBe("claude");
    expect(ownComplete).toHaveBeenCalledTimes(1);
    expect(serverComplete).not.toHaveBeenCalled();
    expect(keys).toEqual([OWN_KEY]);
    expect(usage[0]).toMatchObject({ outcome: "claude", ownKey: true });
    expect(withCost(usage[0], new Date()).costUsd).toBeUndefined();
  });

  it("meldet einen abgelehnten eigenen Schluessel als eigenen Grund, nicht als Serverfehler", async () => {
    const { service, ownComplete } = setup();
    ownComplete.mockRejectedValue(new PlanGenerationError("auth", "invalid x-api-key"));

    const failure = await withOwnKey(OWN_KEY, () => service.planDay({ snapshot: multiSnapshot() })).catch((error: unknown) => error);

    expect(failure).toBeInstanceOf(PlanUnavailableError);
    expect((failure as PlanUnavailableError).reason).toBe("own_key_rejected");
  });

  it("erkennt nur Schluessel, die wie Anthropic-Schluessel aussehen", () => {
    expect(isPlausibleOwnKey(OWN_KEY)).toBe(true);
    expect(isPlausibleOwnKey("sk-ant-kurz")).toBe(false);
    expect(isPlausibleOwnKey("sk-proj-" + "a".repeat(40))).toBe(false);
    expect(isPlausibleOwnKey(OWN_KEY + " ")).toBe(false);
  });
});

describe("Header fuer den eigenen Schluessel", () => {
  const app = buildApp({
    registerV1Routes: (router) => {
      router.get("/own-key", (_req, res) => {
        res.json({ ownKey: currentOwnKey() === undefined ? "none" : "set" });
      });
    }
  });

  it("ohne Header: Schluessel des Servers", async () => {
    const response = await request(app).get("/v1/own-key").set("Authorization", `Bearer ${TEST_TOKEN}`);

    expect(response.body).toEqual({ ownKey: "none" });
  });

  it("mit gueltigem Header: eigener Schluessel fuer diese Anfrage", async () => {
    const response = await request(app).get("/v1/own-key").set("Authorization", `Bearer ${TEST_TOKEN}`).set(OWN_KEY_HEADER, OWN_KEY);

    expect(response.body).toEqual({ ownKey: "set" });
  });

  it("lehnt einen Wert ab, der kein Anthropic-Schluessel sein kann", async () => {
    const response = await request(app).get("/v1/own-key").set("Authorization", `Bearer ${TEST_TOKEN}`).set(OWN_KEY_HEADER, "falsch");

    expect(response.status).toBe(400);
    expect(response.body).toEqual({ error: "invalid_own_key" });
  });

  it("schreibt den Schluessel nie ins Log", async () => {
    const { app: logged, raw } = buildAppWithCapturedLogs({ registerV1Routes: (router) => router.get("/own-key", (_req, res) => res.json({})) });

    await request(logged).get("/v1/own-key").set("Authorization", `Bearer ${TEST_TOKEN}`).set(OWN_KEY_HEADER, OWN_KEY);

    expect(raw()).not.toContain(OWN_KEY);
  });
});
