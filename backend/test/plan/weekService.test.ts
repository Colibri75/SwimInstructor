import { GenerationBudget } from "../../src/plan/budget";
import { PlanGenerationError, PlanUnavailableError } from "../../src/plan/errors";
import { GeneratedPlan, WeekGenerator } from "../../src/plan/generator";
import { WeekPlanService, WeekRequest } from "../../src/plan/weekService";
import { createLogger } from "../../src/logger";
import { testConfig } from "../helpers";
import { snapshot } from "./fixtures";
import { goodWeek, TODAY, WEEK_START } from "./weekFixtures";

const logger = createLogger(testConfig);

function generated(raw: unknown = goodWeek()): GeneratedPlan {
  return { raw, model: "claude-opus-5-5", usage: { inputTokens: 3000, outputTokens: 900 } };
}

function request(overrides: Partial<WeekRequest> = {}): WeekRequest {
  return { snapshot: snapshot(), weekStart: WEEK_START, fromDate: TODAY, today: TODAY, unavailableDates: [], swumThisWeek: [], ...overrides };
}

function setup(options: { generate?: jest.Mock | null; budget?: GenerationBudget } = {}) {
  const generateWeek = options.generate === undefined ? jest.fn().mockResolvedValue(generated()) : options.generate;
  const generator: WeekGenerator | null = generateWeek === null ? null : { generateWeek };
  const service = new WeekPlanService({
    generator,
    budget: options.budget ?? new GenerationBudget(100, 100),
    logger,
    now: () => new Date("2026-09-30T10:00:00Z")
  });
  return { service, generateWeek: generateWeek ?? jest.fn() };
}

describe("WeekPlanService", () => {
  it("liefert den gepruefen Wochenplan mit Summe, Zeitpunkt und Woche", async () => {
    const { service } = setup();

    const result = await service.planWeek(request());

    expect(result.weekStart).toBe(WEEK_START);
    expect(result.generatedAt).toBe("2026-09-30T10:00:00.000Z");
    expect(result.plan.days.map((d) => d.date)).toEqual(["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"]);
    expect(result.plan.total_distance_meters).toBe(3600);
    expect(result.adjustments).toEqual([]);
    expect(result).not.toHaveProperty("wishes");
  });

  it("plant nur die Tage ab from_date und gibt Kontext und Wunsch an Claude", async () => {
    const { service, generateWeek } = setup();

    const result = await service.planWeek(
      request({ unavailableDates: ["2026-10-02"], swumThisWeek: [{ date: "2026-09-28", meters: 1000 }, { date: "2026-09-30", meters: 500 }, { date: "2026-09-20", meters: 700 }], wishes: "  mehr Technik  " })
    );

    const input = generateWeek.mock.calls[0][0];
    expect(input.context.dates).toEqual(["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"]);
    expect(input.context.unavailable).toEqual(["2026-10-02"]);
    // Nur Tage vor from_date und in der Woche zaehlen als schon geschwommen.
    expect(input.context.swumBefore).toEqual([{ date: "2026-09-28", meters: 1000 }]);
    expect(input.wishes).toBe("mehr Technik");
    expect(result.wishes).toBe("mehr Technik");
  });

  it("gibt das Equipment an Claude weiter und laesst es ohne Angabe weg", async () => {
    const { service, generateWeek } = setup();

    await service.planWeek(request({ equipment: ["pull_buoy"] }));
    await service.planWeek(request());

    expect(generateWeek.mock.calls[0][0].equipment).toEqual(["pull_buoy"]);
    expect(generateWeek.mock.calls[1][0]).not.toHaveProperty("equipment");
  });

  it("uebergibt ohne Wunsch kein wishes-Feld", async () => {
    const { service, generateWeek } = setup();

    await service.planWeek(request({ wishes: "   " }));

    expect(generateWeek.mock.calls[0][0]).not.toHaveProperty("wishes");
  });

  it("korrigiert den Plan mit der Sicherheitsschicht und nennt die Korrekturen", async () => {
    const { service } = setup();

    const result = await service.planWeek(request({ unavailableDates: ["2026-10-02"] }));

    expect(result.plan.days.find((d) => d.date === "2026-10-02")?.session_type).toBe("rest");
    expect(result.adjustments.join(" ")).toContain("keine Zeit");
    expect(result.plan.rationale).toContain("Hinweis: Zur Sicherheit angepasst");
  });

  it("meldet 'nicht eingerichtet', wenn kein Generator da ist", async () => {
    await expect(setup({ generate: null }).service.planWeek(request())).rejects.toMatchObject({ reason: "not_configured" });
  });

  it("meldet 'Budget erschoepft' und fragt Claude dann nicht", async () => {
    const budget = new GenerationBudget(1, 100);
    const { service, generateWeek } = setup({ budget });
    await service.planWeek(request());

    await expect(service.planWeek(request())).rejects.toMatchObject({ reason: "budget_exceeded" });
    expect(generateWeek).toHaveBeenCalledTimes(1);
  });

  it.each(["timeout", "unreachable", "rate_limited", "upstream_error", "refusal", "invalid_json"] as const)("meldet den Ausfallgrund %s", async (reason) => {
    const { service } = setup({ generate: jest.fn().mockRejectedValue(new PlanGenerationError(reason, "kaputt")) });

    await expect(service.planWeek(request())).rejects.toEqual(new PlanUnavailableError(reason));
  });

  it("meldet unbekannte Fehler als 'unknown'", async () => {
    const { service } = setup({ generate: jest.fn().mockRejectedValue(new Error("irgendwas")) });

    await expect(service.planWeek(request())).rejects.toMatchObject({ reason: "unknown" });
  });

  it("lehnt eine Antwort ab, die nicht zum Schema passt", async () => {
    const { service } = setup({ generate: jest.fn().mockResolvedValue(generated({ rationale: "x", days: [{ date: "2026-09-30" }] })) });

    await expect(service.planWeek(request())).rejects.toMatchObject({ reason: "schema_invalid" });
  });

  it("lehnt einen Plan ab, den die Sicherheitsschicht blockt", async () => {
    const { service } = setup({ generate: jest.fn().mockResolvedValue(generated(goodWeek({ days: [] }))) });

    await expect(service.planWeek(request())).rejects.toMatchObject({ reason: "sanity_blocked" });
  });
});
