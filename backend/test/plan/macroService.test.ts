import { GenerationBudget } from "../../src/plan/budget";
import { PlanGenerationError, PlanUnavailableError } from "../../src/plan/errors";
import { GeneratedPlan, MacroGenerator } from "../../src/plan/generator";
import { MacroPlanService } from "../../src/plan/macroService";
import { createLogger } from "../../src/logger";
import { testConfig } from "../helpers";
import { snapshot } from "./fixtures";
import { goodMacro, MACRO_GOAL_DAY, MACRO_TODAY, MACRO_WEEKS, macroWeek } from "./macroFixtures";

const logger = createLogger(testConfig);

function generated(raw: unknown = goodMacro()): GeneratedPlan {
  return { raw, model: "claude-opus-5-5", usage: { inputTokens: 3500, outputTokens: 1500 } };
}

// Ziel am 12.11.2026 (Mittag Berlin) statt des Standardziels, damit die Woche zu den Fixtures passt.
const nearGoal = () => snapshot({ goal: { target_date: "2026-11-12T11:00:00Z", days_until_goal: 43 } });

function setup(options: { generate?: jest.Mock | null; budget?: GenerationBudget } = {}) {
  const generateMacro = options.generate === undefined ? jest.fn().mockResolvedValue(generated()) : options.generate;
  const generator: MacroGenerator | null = generateMacro === null ? null : { generateMacro };
  const service = new MacroPlanService({
    generator,
    budget: options.budget ?? new GenerationBudget(100, 100),
    logger,
    now: () => new Date("2026-09-30T10:00:00Z")
  });
  return { service, generateMacro: generateMacro ?? jest.fn() };
}

describe("MacroPlanService", () => {
  it("liefert den gepruefen Gesamtplan mit Zieltag, Zeitpunkt und Phasen", async () => {
    const { service, generateMacro } = setup();

    const result = await service.planMacro({ snapshot: nearGoal(), today: MACRO_TODAY });

    expect(result.goalDay).toBe(MACRO_GOAL_DAY);
    expect(result.generatedAt).toBe("2026-09-30T10:00:00.000Z");
    expect(result.plan.weeks.map((w) => w.week_start)).toEqual(MACRO_WEEKS);
    expect(result.plan.weeks[6].phase).toBe("goal_week");
    expect(result.adjustments).toEqual([]);
    expect(generateMacro.mock.calls[0][0].context).toEqual({ today: MACRO_TODAY, goalDay: MACRO_GOAL_DAY, weeks: MACRO_WEEKS });
  });

  it("korrigiert den Plan mit der Sicherheitsschicht und nennt die Korrekturen", async () => {
    const plan = goodMacro();
    plan.weeks[0] = macroWeek(MACRO_WEEKS[0], { target_meters: 9000 });
    const { service } = setup({ generate: jest.fn().mockResolvedValue(generated(plan)) });

    const result = await service.planMacro({ snapshot: nearGoal(), today: MACRO_TODAY });

    expect(result.plan.weeks[0].target_meters).toBe(3900);
    expect(result.adjustments[0]).toContain("auf 3900 m begrenzt");
  });

  it.each([
    ["kein Key", { generate: null }, "not_configured"],
    ["Budget erschoepft", { budget: new GenerationBudget(0, 0) }, "budget_exceeded"],
    ["Timeout", { generate: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "zu langsam")) }, "timeout"],
    ["unbekannter Fehler", { generate: jest.fn().mockRejectedValue(new Error("kaputt")) }, "unknown"],
    ["Schema ungueltig", { generate: jest.fn().mockResolvedValue(generated({ unsinn: true })) }, "schema_invalid"],
    ["unbrauchbar", { generate: jest.fn().mockResolvedValue(generated(goodMacro({ weeks: [] }))) }, "sanity_blocked"]
  ])("meldet %s als nicht verfuegbar (%s)", async (_name, options, reason) => {
    const { service } = setup(options as Parameters<typeof setup>[0]);

    await expect(service.planMacro({ snapshot: nearGoal(), today: MACRO_TODAY })).rejects.toMatchObject({ reason });
    await expect(service.planMacro({ snapshot: nearGoal(), today: MACRO_TODAY })).rejects.toBeInstanceOf(PlanUnavailableError);
  });

  it("plant nach dem Zieltag nur die laufende Woche", async () => {
    const { service, generateMacro } = setup({ generate: jest.fn().mockResolvedValue(generated({ rationale: "Erhalten.", weeks: [macroWeek("2026-09-28", { target_meters: 2000 })] })) });

    const result = await service.planMacro({ snapshot: snapshot({ goal: { target_date: "2026-08-01T10:00:00Z", days_until_goal: 0 } }), today: MACRO_TODAY });

    expect(result.plan.weeks).toHaveLength(1);
    expect(result.plan.weeks[0].phase).toBe("maintain");
    expect(generateMacro.mock.calls[0][0].context.weeks).toEqual(["2026-09-28"]);
  });
});
