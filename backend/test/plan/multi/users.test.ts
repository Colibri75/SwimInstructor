import { GenerationBudget, UserBudgets } from "../../../src/plan/budget";
import { PlanGenerationError, PlanUnavailableError } from "../../../src/plan/errors";
import { MultiPlanService } from "../../../src/plan/multi/service";
import { DayPlanStoreV2, MemoryDayPlanStoreV2 } from "../../../src/plan/multi/store";
import { createLogger } from "../../../src/logger";
import { UsageInput } from "../../../src/usage";
import { testConfig } from "../../helpers";
import { dayPlan, multiSnapshot, session, swimStep, TODAY, weekPlan, weekSession } from "./fixtures";

const logger = createLogger(testConfig);
const goodDay = () => dayPlan([session("swim", { steps: [swimStep(300, { name: "Einschwimmen" }), swimStep(400), swimStep(150, { name: "Ausschwimmen" })] })]);
const goodWeek = () => weekPlan([[weekSession("swim", 800)], [weekSession("bike", 45)], [], [weekSession("run", 20)], [weekSession("swim", 1500)], [], [weekSession("bike", 60)]]);

function setup(
  options: { complete?: jest.Mock; budget?: GenerationBudget; userBudgets?: UserBudgets; adminBudgets?: UserBudgets; isAdmin?: (user: string) => boolean } = {}
) {
  const stores = new Map<string, MemoryDayPlanStoreV2>();
  const storeFor = (user: string): DayPlanStoreV2 => {
    if (!stores.has(user)) stores.set(user, new MemoryDayPlanStoreV2());
    return stores.get(user)!;
  };
  const recorded: UsageInput[] = [];
  const complete = options.complete ?? jest.fn().mockResolvedValue({ raw: goodDay(), model: "claude-opus-5-5", usage: { inputTokens: 9_000, outputTokens: 2_000 } });
  const service = new MultiPlanService({
    generator: { complete },
    store: storeFor,
    budget: options.budget ?? new GenerationBudget(100, 100),
    userBudgets: options.userBudgets,
    adminBudgets: options.adminBudgets,
    isAdmin: options.isAdmin,
    usage: { record: (event) => recorded.push(event) },
    logger,
    timezone: "Europe/Berlin",
    now: () => new Date("2026-09-30T10:00:00Z")
  });
  return { service, stores, recorded, complete };
}

describe("Plan v2: Nutzer getrennt", () => {
  it("speichert den Tagesplan je Nutzer und liefert den Cache nur dem eigenen Nutzer", async () => {
    const { service, stores, complete } = setup();

    const anna = await service.planDay({ user: "anna", snapshot: multiSnapshot() });
    const annaAgain = await service.planDay({ user: "anna", snapshot: multiSnapshot() });
    const ben = await service.planDay({ user: "ben", snapshot: multiSnapshot() });

    expect([anna.source, annaAgain.source, ben.source]).toEqual(["claude", "cache", "claude"]);
    expect(complete).toHaveBeenCalledTimes(2);
    expect([...stores.keys()].sort()).toEqual(["anna", "ben"]);
  });

  it("faellt nur auf den eigenen letzten Plan zurueck", async () => {
    const complete = jest.fn().mockResolvedValueOnce({ raw: goodDay(), model: "m", usage: { inputTokens: 1, outputTokens: 1 } }).mockRejectedValue(new PlanGenerationError("timeout", "langsam"));
    const { service } = setup({ complete });
    await service.planDay({ user: "anna", snapshot: multiSnapshot() });

    const anna = await service.planDay({ user: "anna", snapshot: multiSnapshot(), regenerate: true });
    const ben = service.planDay({ user: "ben", snapshot: multiSnapshot() });

    expect(anna.source).toBe("fallback");
    await expect(ben).rejects.toEqual(new PlanUnavailableError("timeout"));
  });

  it("hat ein Budget je Nutzer, ohne dass einer das der anderen aufbraucht", async () => {
    const { service } = setup({ userBudgets: new UserBudgets(1, 10) });

    await service.planDay({ user: "anna", snapshot: multiSnapshot() });
    const annaAgain = service.planDay({ user: "anna", snapshot: multiSnapshot(), regenerate: true });
    const ben = await service.planDay({ user: "ben", snapshot: multiSnapshot() });

    // Anna faellt auf ihren eigenen Plan zurueck, Ben bekommt einen frischen.
    expect((await annaAgain).fallbackReason).toBe("budget_exceeded");
    expect(ben.source).toBe("claude");
  });

  it("verbraucht das Nutzerbudget nicht, wenn das Gesamtbudget erschoepft ist", async () => {
    const userBudgets = new UserBudgets(5, 5);
    const { service } = setup({ budget: new GenerationBudget(1, 1), userBudgets });

    await service.planDay({ user: "anna", snapshot: multiSnapshot() });
    await expect(service.planDay({ user: "ben", snapshot: multiSnapshot() })).rejects.toEqual(new PlanUnavailableError("budget_exceeded"));

    expect(userBudgets.for("ben").available()).toBe(true);
    expect([1, 2, 3, 4, 5].every(() => userBudgets.for("ben").tryConsume())).toBe(true);
  });
});

describe("Plan v2: Admins und Server-Budget", () => {
  it("laesst Admins planen, auch wenn andere das Server-Budget aufgebraucht haben", async () => {
    const budget = new GenerationBudget(1, 1);
    const { service } = setup({ budget, userBudgets: new UserBudgets(5, 5), adminBudgets: new UserBudgets(5, 5), isAdmin: (user) => user === "owner" });

    await service.planDay({ user: "anna", snapshot: multiSnapshot() });
    await expect(service.planDay({ user: "ben", snapshot: multiSnapshot() })).rejects.toEqual(new PlanUnavailableError("budget_exceeded"));
    const owner = await service.planDay({ user: "owner", snapshot: multiSnapshot() });

    expect(owner.source).toBe("claude");
    // Der Admin hat das Server-Budget nicht verbraucht (es war schon leer) und zaehlt auch spaeter nicht dagegen.
    expect(budget.available()).toBe(false);
  });

  it("begrenzt Admins mit ihrem eigenen Budget", async () => {
    const { service } = setup({ userBudgets: new UserBudgets(5, 5), adminBudgets: new UserBudgets(1, 1), isAdmin: () => true });

    await service.planDay({ user: "owner", snapshot: multiSnapshot() });
    const again = await service.planDay({ user: "owner", snapshot: multiSnapshot(), regenerate: true });

    expect(again.fallbackReason).toBe("budget_exceeded");
  });

  it("zaehlt Admins ohne Budget je Nutzer gegen das Server-Budget", async () => {
    const budget = new GenerationBudget(1, 1);
    const { service } = setup({ budget, isAdmin: () => true });

    await service.planDay({ user: "owner", snapshot: multiSnapshot() });

    expect(budget.available()).toBe(false);
  });
});

describe("Plan v2: Nutzung", () => {
  it("nimmt jede Anfrage mit Ergebnis, Nutzer, Token und Dauer auf", async () => {
    const complete = jest
      .fn()
      .mockResolvedValueOnce({ raw: goodDay(), model: "claude-opus-5-5", usage: { inputTokens: 9_000, outputTokens: 2_000 } })
      .mockResolvedValueOnce({ raw: goodWeek(), model: "claude-opus-5-5", usage: { inputTokens: 12_000, outputTokens: 4_000 } })
      .mockRejectedValue(new PlanGenerationError("timeout", "langsam"));
    const { service, recorded } = setup({ complete });

    await service.planDay({ user: "anna", snapshot: multiSnapshot() });
    await service.planDay({ user: "anna", snapshot: multiSnapshot() });
    await service.planWeek({ user: "anna", snapshot: multiSnapshot(), fromDate: TODAY, today: TODAY, unavailable: [], recent: [] });
    await service.planDay({ user: "anna", snapshot: multiSnapshot(), regenerate: true });
    await expect(service.planMacro({ snapshot: multiSnapshot(), today: TODAY })).rejects.toBeInstanceOf(PlanUnavailableError);

    expect(recorded.map(({ latencyMs: _ignored, ...rest }) => rest)).toEqual([
      { user: "anna", kind: "day", outcome: "claude", model: "claude-opus-5-5", inputTokens: 9_000, outputTokens: 2_000 },
      { user: "anna", kind: "day", outcome: "cache" },
      { user: "anna", kind: "week", outcome: "claude", model: "claude-opus-5-5", inputTokens: 12_000, outputTokens: 4_000 },
      { user: "anna", kind: "day", outcome: "fallback", reason: "timeout" },
      { user: "owner", kind: "macro", outcome: "failed", reason: "timeout" }
    ]);
    expect(recorded.map((event) => event.latencyMs !== undefined)).toEqual([true, false, true, true, true]);
  });

  it("zaehlt die Token auch, wenn die Sicherheitsschicht den Plan verwirft", async () => {
    const broken = weekPlan([[weekSession("swim", 800)]]);
    const complete = jest.fn().mockResolvedValue({ raw: { ...broken, days: [] }, model: "claude-opus-5-5", usage: { inputTokens: 5, outputTokens: 7 } });
    const { service, recorded } = setup({ complete });

    await expect(service.planWeek({ snapshot: multiSnapshot(), fromDate: TODAY, today: TODAY, unavailable: [], recent: [] })).rejects.toBeInstanceOf(PlanUnavailableError);

    expect(recorded).toHaveLength(1);
    expect(recorded[0]).toMatchObject({ kind: "week", outcome: "failed", inputTokens: 5, outputTokens: 7 });
    expect(["schema_invalid", "sanity_blocked"]).toContain(recorded[0].reason);
  });
});
