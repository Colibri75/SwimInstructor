import { GenerationBudget } from "../../src/plan/budget";
import { PlanGenerationError, PlanUnavailableError } from "../../src/plan/errors";
import { GeneratedPlan, PlanGenerator } from "../../src/plan/generator";
import { localDate, PlanService, snapshotHash } from "../../src/plan/service";
import { MemoryPlanStore, PlanStore, StoredPlan } from "../../src/plan/store";
import { createLogger } from "../../src/logger";
import { testConfig } from "../helpers";
import { goodPlan, plan, planOfMeters, snapshot } from "./fixtures";

const logger = createLogger(testConfig);
const usage = { inputTokens: 1800, outputTokens: 2500 };

function generated(raw: unknown = goodPlan): GeneratedPlan {
  return { raw, model: "claude-opus-5-5", usage };
}

interface Setup {
  service: PlanService;
  generate: jest.Mock;
  store: PlanStore;
  advance: (ms: number) => void;
}

function setup(options: { generate?: jest.Mock | null; store?: PlanStore; budget?: GenerationBudget; start?: string } = {}): Setup {
  let now = new Date(options.start ?? "2026-09-30T10:00:00Z").getTime();
  const generate = options.generate === undefined ? jest.fn().mockResolvedValue(generated()) : options.generate;
  const generator: PlanGenerator | null = generate === null ? null : { generate };
  const store = options.store ?? new MemoryPlanStore();
  const service = new PlanService({
    generator,
    store,
    budget: options.budget ?? new GenerationBudget(100, 100),
    logger,
    timezone: "Europe/Berlin",
    now: () => new Date(now)
  });
  return { service, generate: generate ?? jest.fn(), store, advance: (ms) => (now += ms) };
}

const storedPlan = (overrides: Partial<StoredPlan> = {}): StoredPlan => ({
  date: "2026-09-29",
  snapshotHash: "alt",
  generatedAt: "2026-09-29T10:00:00.000Z",
  model: "claude-opus-5-5",
  plan: goodPlan,
  adjustments: [],
  ...overrides
});

describe("PlanService: frischer Plan", () => {
  it("erzeugt einen Plan, speichert ihn und liefert ihn aus", async () => {
    const { service, store } = setup();

    const result = await service.planForToday(snapshot());

    expect(result).toMatchObject({ source: "claude", date: "2026-09-30", stale: false, plan: goodPlan, adjustments: [] });
    expect((await store.latest())?.plan).toEqual(goodPlan);
    expect((await store.latest())?.snapshotHash).toBe(snapshotHash(snapshot()));
  });

  it("schickt Datum und Snapshot an den Generator", async () => {
    const { service, generate } = setup();

    await service.planForToday(snapshot());

    expect(generate).toHaveBeenCalledWith({ snapshot: snapshot(), date: "2026-09-30" });
  });

  it("korrigiert einen gefaehrlichen Claude-Plan mit der Sicherheitsschicht, bevor er gespeichert wird", async () => {
    const dangerous = planOfMeters(4800, { intensity: "hard", session_type: "intervals" });
    const { service, store } = setup({ generate: jest.fn().mockResolvedValue(generated(dangerous)) });

    const result = await service.planForToday(snapshot({ load: { days_since_last_hard_session: 1 } }));

    expect(result.source).toBe("claude");
    expect(result.plan.total_distance_meters).toBeLessThanOrEqual(2400);
    expect(result.plan.intensity).toBe("moderate");
    expect(result.adjustments.length).toBeGreaterThanOrEqual(2);
    expect((await store.latest())?.plan).toEqual(result.plan);
  });

  it("nimmt fuer den Tag die Zeitzone des Servers, nicht UTC", async () => {
    // 23:30 UTC ist in Berlin (MESZ) schon der naechste Tag
    const { service } = setup({ start: "2026-09-30T23:30:00Z" });

    expect((await service.planForToday(snapshot())).date).toBe("2026-10-01");
  });
});

describe("PlanService: Cache", () => {
  it("fragt Claude bei regenerate neu, auch wenn fuer denselben Zustand ein Plan vorliegt", async () => {
    const { service, generate } = setup();

    await service.planForToday(snapshot());
    const again = await service.planForToday(snapshot(), { regenerate: true });

    expect(generate).toHaveBeenCalledTimes(2);
    expect(again.source).toBe("claude");
  });

  it("zaehlt regenerate gegen das Budget und faellt bei erschoepftem Budget auf den letzten Plan zurueck", async () => {
    const budget = new GenerationBudget(1, 100);
    const { service, generate } = setup({ budget });

    await service.planForToday(snapshot());
    const again = await service.planForToday(snapshot(), { regenerate: true });

    expect(generate).toHaveBeenCalledTimes(1);
    expect(again).toMatchObject({ source: "fallback", fallbackReason: "budget_exceeded" });
  });

  it("ruft Claude bei demselben Zustand am selben Tag nur einmal auf", async () => {
    const { service, generate } = setup();

    const first = await service.planForToday(snapshot());
    const second = await service.planForToday(snapshot());

    expect(generate).toHaveBeenCalledTimes(1);
    expect(first.source).toBe("claude");
    expect(second).toMatchObject({ source: "cache", plan: goodPlan });
  });

  it("ignoriert bei der Cache-Pruefung den Erzeugungszeitpunkt des Snapshots", async () => {
    const { service, generate } = setup();
    const a = snapshot();
    const b = { ...snapshot(), generated_at: "2026-09-30T15:45:00Z" };

    await service.planForToday(a);
    await service.planForToday(b);

    expect(generate).toHaveBeenCalledTimes(1);
  });

  it("erzeugt neu, wenn sich der Zustand geaendert hat (z. B. neues Workout)", async () => {
    const { service, generate } = setup();

    await service.planForToday(snapshot());
    await service.planForToday(snapshot({ volume: { last_seven_days_meters: 2500 } }));

    expect(generate).toHaveBeenCalledTimes(2);
  });

  it("erzeugt am naechsten Tag neu, auch bei gleichem Zustand", async () => {
    const { service, generate, advance } = setup();

    await service.planForToday(snapshot());
    advance(24 * 60 * 60 * 1000);
    await service.planForToday(snapshot());

    expect(generate).toHaveBeenCalledTimes(2);
  });

  it("liefert den Cache auch ohne Claude-Konfiguration und ohne Budget", async () => {
    const store = new MemoryPlanStore(storedPlan({ date: "2026-09-30", snapshotHash: snapshotHash(snapshot()) }));
    const { service } = setup({ generate: null, store, budget: new GenerationBudget(1, 1, () => 0) });

    expect((await service.planForToday(snapshot())).source).toBe("cache");
  });
});

describe("PlanService: Fallback auf den letzten gueltigen Plan", () => {
  it.each<[string, Error, string]>([
    ["Claude ist nicht erreichbar", new PlanGenerationError("unreachable", "ENOTFOUND"), "unreachable"],
    ["Zeitueberschreitung", new PlanGenerationError("timeout", "timeout"), "timeout"],
    ["Rate-Limit", new PlanGenerationError("rate_limited", "429"), "rate_limited"],
    ["Serverfehler", new PlanGenerationError("upstream_error", "500"), "upstream_error"],
    ["ungueltiges JSON", new PlanGenerationError("invalid_json", "kein JSON"), "invalid_json"],
    ["Ablehnung durch Claude", new PlanGenerationError("refusal", "abgelehnt"), "refusal"],
    ["abgeschnittene Antwort", new PlanGenerationError("truncated", "max_tokens"), "truncated"],
    ["falscher API-Key", new PlanGenerationError("auth", "401"), "auth"],
    ["voellig unerwarteter Fehler", new TypeError("boom"), "unknown"]
  ])("liefert bei %s den letzten Plan statt eines Fehlers", async (_name, error, reason) => {
    const store = new MemoryPlanStore(storedPlan());
    const { service } = setup({ generate: jest.fn().mockRejectedValue(error), store });

    const result = await service.planForToday(snapshot());

    expect(result).toMatchObject({ source: "fallback", fallbackReason: reason, plan: goodPlan });
  });

  it("markiert einen Plan von einem frueheren Tag als veraltet und nennt sein Datum", async () => {
    const store = new MemoryPlanStore(storedPlan({ date: "2026-09-27" }));
    const { service } = setup({ generate: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store });

    const result = await service.planForToday(snapshot());

    expect(result).toMatchObject({ source: "fallback", date: "2026-09-27", stale: true });
  });

  it("markiert einen Plan von heute nicht als veraltet", async () => {
    const store = new MemoryPlanStore(storedPlan({ date: "2026-09-30", snapshotHash: "anderer-zustand" }));
    const { service } = setup({ generate: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store });

    expect((await service.planForToday(snapshot())).stale).toBe(false);
  });

  it("wirft PlanUnavailableError, wenn Claude scheitert und es noch keinen Plan gibt", async () => {
    const { service } = setup({ generate: jest.fn().mockRejectedValue(new PlanGenerationError("unreachable", "x")) });

    await expect(service.planForToday(snapshot())).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "unreachable" });
  });

  it("faellt zurueck, wenn Claude ein falsch aufgebautes JSON liefert", async () => {
    const store = new MemoryPlanStore(storedPlan());
    const { service } = setup({ generate: jest.fn().mockResolvedValue(generated({ foo: "bar" })), store });

    expect(await service.planForToday(snapshot())).toMatchObject({ source: "fallback", fallbackReason: "schema_invalid" });
  });

  it("faellt zurueck, wenn die Sicherheitsschicht den Plan blockt", async () => {
    const unusable = plan({ sets: [], total_distance_meters: 0 }); // Trainingstag ohne Abschnitte
    const store = new MemoryPlanStore(storedPlan());
    const { service, generate } = setup({ generate: jest.fn().mockResolvedValue(generated(unusable)), store });

    const result = await service.planForToday(snapshot());

    expect(generate).toHaveBeenCalled();
    expect(result).toMatchObject({ source: "fallback", fallbackReason: "sanity_blocked" });
    expect((await store.latest())?.date).toBe("2026-09-29"); // der kaputte Plan wurde nicht gespeichert
  });

  it("liefert ohne konfigurierten API-Key den letzten Plan und ruft nie Claude", async () => {
    const store = new MemoryPlanStore(storedPlan());
    const { service } = setup({ generate: null, store });

    expect(await service.planForToday(snapshot())).toMatchObject({ source: "fallback", fallbackReason: "not_configured" });
  });

  it("wirft ohne API-Key und ohne gespeicherten Plan PlanUnavailableError", async () => {
    const { service } = setup({ generate: null });

    await expect(service.planForToday(snapshot())).rejects.toBeInstanceOf(PlanUnavailableError);
  });

  it("ruft Claude nicht mehr auf, wenn das Aufrufbudget erschoepft ist, und liefert den letzten Plan", async () => {
    const budget = new GenerationBudget(1, 100, () => 0);
    const store = new MemoryPlanStore();
    const { service, generate } = setup({ budget, store });

    await service.planForToday(snapshot()); // verbraucht das einzige Stundenbudget
    const result = await service.planForToday(snapshot({ volume: { last_seven_days_meters: 2500 } }));

    expect(generate).toHaveBeenCalledTimes(1);
    expect(result).toMatchObject({ source: "fallback", fallbackReason: "budget_exceeded" });
  });

  it("prueft den alten Plan vor dem Ausliefern gegen den heutigen Zustand", async () => {
    // Gestern war die harte Einheit in Ordnung, heute meldet der Snapshot Uebertrainingsrisiko.
    const hardYesterday = planOfMeters(1600, { session_type: "intervals", intensity: "hard", rationale: "Harte Intervalle." });
    const store = new MemoryPlanStore(storedPlan({ plan: hardYesterday }));
    const strained = snapshot({
      recovery: { status: "poor", warning_signals: ["short_sleep", "low_heart_rate_variability"] },
      flags: ["recovery_poor", "overreaching_risk"]
    });
    const { service } = setup({ generate: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store });

    const result = await service.planForToday(strained);

    expect(result.source).toBe("fallback");
    expect(result.plan.session_type).toBe("rest");
    expect(result.plan.sets).toEqual([]);
    expect(result.adjustments.join(" ")).toContain("Ruhetag");
  });
});

describe("PlanService: unbrauchbarer gespeicherter Plan", () => {
  it("liefert lieber 503 als einen gespeicherten Plan, der die Pruefung nicht mehr besteht", async () => {
    const corrupt = plan({ sets: [], total_distance_meters: 0 }); // Trainingstag ohne Abschnitte
    const store = new MemoryPlanStore(storedPlan({ plan: corrupt }));
    const { service } = setup({ generate: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store });

    await expect(service.planForToday(snapshot())).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "timeout" });
  });
});

describe("PlanService: Speicherfehler", () => {
  const failingStore = (overrides: Partial<PlanStore>): PlanStore => ({
    latest: async () => null,
    save: async () => undefined,
    ...overrides
  });

  it("liefert den frischen Plan, auch wenn das Speichern scheitert", async () => {
    const { service } = setup({ store: failingStore({ save: async () => Promise.reject(new Error("Platte voll")) }) });

    expect(await service.planForToday(snapshot())).toMatchObject({ source: "claude", plan: goodPlan });
  });

  it("behandelt einen Lesefehler wie 'kein Plan' und erzeugt neu", async () => {
    const { service, generate } = setup({ store: failingStore({ latest: async () => Promise.reject(new Error("EACCES")) }) });

    expect((await service.planForToday(snapshot())).source).toBe("claude");
    expect(generate).toHaveBeenCalledTimes(1);
  });
});

describe("Hilfsfunktionen", () => {
  it("localDate liefert den Kalendertag in der Zeitzone", () => {
    const instant = new Date("2026-09-30T23:30:00Z");

    expect(localDate(instant, "UTC")).toBe("2026-09-30");
    expect(localDate(instant, "Europe/Berlin")).toBe("2026-10-01");
    expect(localDate(instant, "America/Los_Angeles")).toBe("2026-09-30");
  });

  it("snapshotHash ist stabil und reagiert auf Zustandsaenderungen", () => {
    expect(snapshotHash(snapshot())).toBe(snapshotHash(snapshot()));
    expect(snapshotHash(snapshot())).not.toBe(snapshotHash(snapshot({ flags: ["training_pause"] })));
  });
});
