import { GenerationBudget } from "../../../src/plan/budget";
import { FallbackReason, PlanGenerationError, PlanUnavailableError } from "../../../src/plan/errors";
import { GeneratedPlan } from "../../../src/plan/generator";
import { macroWeekStarts } from "../../../src/plan/macro";
import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { MULTI_DAY_SYSTEM_PROMPT, MULTI_MACRO_SYSTEM_PROMPT, MULTI_REVISE_SYSTEM_PROMPT, MULTI_WEEK_SYSTEM_PROMPT } from "../../../src/plan/multi/prompts";
import {
  MacroRevisionRaw,
  MacroRevisionSchema,
  MacroWeekTargetV2,
  MultiDayPlanSchema,
  MultiMacroPlanRaw,
  MultiMacroPlanSchema,
  MultiWeekPlanRaw,
  MultiWeekPlanSchema,
  RecentTraining
} from "../../../src/plan/multi/schemas";
import { dayHash, MultiPlanService, ReviseInput, WeekInputV2 } from "../../../src/plan/multi/service";
import { DayPlanStoreV2, MemoryDayPlanStoreV2, StoredDayV2 } from "../../../src/plan/multi/store";
import { createLogger } from "../../../src/logger";
import { testConfig } from "../../helpers";
import { asBlocks, dayPlan, macroPlan, multiSnapshot, session, step, swimStep, TODAY, weekPlan, weekSession } from "./fixtures";

const logger = createLogger(testConfig);
const GOAL_DAY = "2027-07-04";
const NOW_ISO = "2026-09-30T10:00:00.000Z";

function generated(raw: unknown): GeneratedPlan {
  return { raw, model: "claude-opus-5-5", usage: { inputTokens: 1, outputTokens: 1 } };
}

/** 300 + 400 + 150 m: genau die Grenze fuer heute (850 m), keine Anpassung. */
const swimSession = () => session("swim", { steps: [swimStep(300, { name: "Einschwimmen" }), swimStep(400), swimStep(150, { name: "Ausschwimmen" })] });
const goodDay = () => dayPlan([swimSession()]);

interface Setup {
  service: MultiPlanService;
  complete: jest.Mock;
  store: DayPlanStoreV2;
  advance: (ms: number) => void;
}

function setup(options: { complete?: jest.Mock | null; store?: DayPlanStoreV2; budget?: GenerationBudget; start?: string } = {}): Setup {
  let now = new Date(options.start ?? "2026-09-30T10:00:00Z").getTime();
  const complete = options.complete === undefined ? jest.fn().mockResolvedValue(generated(goodDay())) : options.complete;
  const store = options.store ?? new MemoryDayPlanStoreV2();
  const service = new MultiPlanService({
    generator: complete === null ? null : { complete },
    store,
    budget: options.budget ?? new GenerationBudget(100, 100),
    logger,
    timezone: "Europe/Berlin",
    now: () => new Date(now)
  });
  return { service, complete: complete ?? jest.fn(), store, advance: (ms) => (now += ms) };
}

/** Der Plan von gestern: eine lockere Radeinheit (30 min), die auch heute noch in die Grenzen passt. */
const bikeDay = () =>
  dayPlan(
    [session("bike", { steps: [step({ name: "Einrollen", duration_seconds: 600 }), step({ duration_seconds: 900 }), step({ name: "Ausrollen", duration_seconds: 300 })] })],
    "Rad locker, 90 min in 7 Tagen."
  );

function storedDay(overrides: Partial<StoredDayV2> = {}): StoredDayV2 {
  return {
    date: "2026-09-29",
    hash: "alt",
    generatedAt: "2026-09-29T10:00:00.000Z",
    model: "claude-opus-5-5",
    plan: sanitizeDayV2(bikeDay(), multiSnapshot(), { date: "2026-09-29" }).plan,
    adjustments: [],
    ...overrides
  };
}

const failingStore = (overrides: Partial<DayPlanStoreV2>): DayPlanStoreV2 => ({
  latest: async () => null,
  save: async () => undefined,
  ...overrides
});

describe("MultiPlanService.planDay: frischer Plan", () => {
  it("erzeugt den Tagesplan, speichert ihn und liefert ihn aus", async () => {
    const { service, store } = setup();

    const result = await service.planDay({ snapshot: multiSnapshot() });

    expect(result).toMatchObject({ source: "claude", date: TODAY, generatedAt: NOW_ISO, stale: false, adjustments: [] });
    expect(result.plan.sessions).toHaveLength(1);
    expect(result.plan.sessions[0]).toMatchObject({ sport: "swim", session_type: "endurance", intensity: "easy", amount: 850, unit: "meters", test: null });
    expect(result).not.toHaveProperty("fallbackReason");
    expect(result).not.toHaveProperty("wishes");
    expect(await store.latest()).toEqual({
      date: TODAY,
      hash: dayHash({ snapshot: multiSnapshot() }),
      generatedAt: NOW_ISO,
      model: "claude-opus-5-5",
      plan: result.plan,
      adjustments: []
    });
  });

  it("schickt Tages-Prompt, Nutzernachricht mit dem Wunsch als JSON-String und das Schema an Claude", async () => {
    const { service, complete } = setup();

    const result = await service.planDay({ snapshot: multiSnapshot(), wishes: '  Schulter schonen, "bitte"  ' });

    expect(complete).toHaveBeenCalledTimes(1);
    const [system, user, schema, options] = complete.mock.calls[0];
    expect(system).toBe(MULTI_DAY_SYSTEM_PROMPT);
    expect(schema).toBe(MultiDayPlanSchema);
    expect(options).toEqual({});
    expect(user).toContain("Erstelle die Einheiten für heute, Mittwoch, 2026-09-30.");
    expect(user).toContain(JSON.stringify('Schulter schonen, "bitte"'));
    expect(result.wishes).toBe('Schulter schonen, "bitte"');
  });

  it("laesst einen leeren Wunsch weg", async () => {
    const { service, complete } = setup();

    const result = await service.planDay({ snapshot: multiSnapshot(), wishes: "   " });

    expect(result).not.toHaveProperty("wishes");
    expect(complete.mock.calls[0][1]).not.toContain("Wunsch des Athleten");
  });

  it("korrigiert Claudes Plan mit der Sicherheitsschicht und speichert die Anpassungen mit", async () => {
    const tooMuch = dayPlan([session("swim", { steps: [swimStep(400, { name: "Einschwimmen" }), swimStep(1000), swimStep(200, { name: "Ausschwimmen" })] })]);
    const { service, store } = setup({ complete: jest.fn().mockResolvedValue(generated(tooMuch)) });

    const result = await service.planDay({ snapshot: multiSnapshot() });

    expect(result.source).toBe("claude");
    expect(result.plan.sessions[0].amount).toBe(850);
    expect(result.adjustments).toEqual(["Schwimmen: Umfang von 1600 m auf 850 m gekürzt (Grenze für heute: 850 m)"]);
    expect(result.plan.rationale).toContain("Zur Sicherheit angepasst");
    expect((await store.latest())?.adjustments).toEqual(result.adjustments);
  });

  it("nimmt fuer den Tag die Zeitzone des Servers, nicht UTC", async () => {
    // 23:30 UTC ist in Berlin (MESZ) schon der naechste Tag
    const { service } = setup({ start: "2026-09-30T23:30:00Z" });

    expect((await service.planDay({ snapshot: multiSnapshot() })).date).toBe("2026-10-01");
  });
});

describe("MultiPlanService.planDay: Cache", () => {
  it("ruft Claude bei demselben Zustand am selben Tag nur einmal auf", async () => {
    const { service, complete } = setup();

    const first = await service.planDay({ snapshot: multiSnapshot(), wishes: " mehr Technik " });
    const second = await service.planDay({ snapshot: multiSnapshot(), wishes: "mehr Technik" });

    expect(complete).toHaveBeenCalledTimes(1);
    expect(second).toMatchObject({ source: "cache", date: TODAY, stale: false, generatedAt: first.generatedAt, wishes: "mehr Technik" });
    expect(second.plan).toEqual(first.plan);
    expect(second.adjustments).toEqual(first.adjustments);
  });

  it("fragt Claude bei regenerate neu, auch wenn fuer denselben Zustand ein Plan vorliegt", async () => {
    const { service, complete } = setup();

    await service.planDay({ snapshot: multiSnapshot() });
    const again = await service.planDay({ snapshot: multiSnapshot(), regenerate: true });

    expect(complete).toHaveBeenCalledTimes(2);
    expect(again.source).toBe("claude");
  });

  it("plant bei anderem Wunsch neu (neuer Fingerabdruck)", async () => {
    const { service, complete, store } = setup();

    await service.planDay({ snapshot: multiSnapshot(), wishes: "mehr Technik" });
    const other = await service.planDay({ snapshot: multiSnapshot(), wishes: "lieber Rad" });
    const none = await service.planDay({ snapshot: multiSnapshot() });

    expect(other.source).toBe("claude");
    expect(none.source).toBe("claude");
    expect(complete).toHaveBeenCalledTimes(3);
    expect((await store.latest())?.hash).toBe(dayHash({ snapshot: multiSnapshot() }));
  });

  it("ignoriert den Erzeugungszeitpunkt des Snapshots und die Reihenfolge des Equipments", async () => {
    const { service, complete } = setup();

    await service.planDay({ snapshot: multiSnapshot(), equipment: ["pull_buoy", "fins"] });
    const later = await service.planDay({ snapshot: { ...multiSnapshot(), generated_at: "2026-09-30T15:45:00Z" }, equipment: ["fins", "pull_buoy", "fins"] });

    expect(complete).toHaveBeenCalledTimes(1);
    expect(later.source).toBe("cache");
  });

  it("erzeugt neu, wenn sich der Zustand geaendert hat", async () => {
    const { service, complete } = setup();

    await service.planDay({ snapshot: multiSnapshot() });
    await service.planDay({ snapshot: multiSnapshot({ recovery: { status: "moderate" } }) });

    expect(complete).toHaveBeenCalledTimes(2);
  });

  it("erzeugt am naechsten Tag neu, auch bei gleichem Zustand", async () => {
    const { service, complete, advance } = setup();

    await service.planDay({ snapshot: multiSnapshot() });
    advance(24 * 60 * 60 * 1000);
    const next = await service.planDay({ snapshot: multiSnapshot() });

    expect(complete).toHaveBeenCalledTimes(2);
    expect(next).toMatchObject({ source: "claude", date: "2026-10-01" });
  });

  it("liefert den Cache auch ohne Claude-Konfiguration und ohne Budget", async () => {
    const store = new MemoryDayPlanStoreV2(storedDay({ date: TODAY, hash: dayHash({ snapshot: multiSnapshot() }) }));
    const { service } = setup({ complete: null, store, budget: new GenerationBudget(0, 0) });

    expect((await service.planDay({ snapshot: multiSnapshot() })).source).toBe("cache");
  });
});

describe("dayHash", () => {
  const snapshot = multiSnapshot();
  const base = dayHash({ snapshot });

  it("ignoriert den Erzeugungszeitpunkt des Snapshots", () => {
    expect(dayHash({ snapshot: { ...snapshot, generated_at: "2026-09-30T23:59:00Z" } })).toBe(base);
  });

  it("sortiert das Equipment und zaehlt doppelte nur einmal", () => {
    expect(dayHash({ snapshot, equipment: ["pull_buoy", "fins"] })).toBe(dayHash({ snapshot, equipment: ["fins", "pull_buoy", "fins"] }));
    expect(dayHash({ snapshot, equipment: ["fins"] })).not.toBe(dayHash({ snapshot, equipment: ["pull_buoy", "fins"] }));
  });

  it("unterscheidet 'kein Equipment' von 'Equipment nicht angegeben'", () => {
    expect(dayHash({ snapshot, equipment: [] })).not.toBe(base);
  });

  it("aendert sich mit Wunsch, Vorgabe, Verlauf und Testeinstellungen", () => {
    const recent: RecentTraining[] = [{ date: "2026-09-29", sport: "swim", minutes: 40, meters: 2000 }];
    const variants = [
      dayHash({ snapshot }, "mehr Technik"),
      dayHash({ snapshot, dayTarget: { sessions: [] } }),
      dayHash({ snapshot, recent }),
      dayHash({ snapshot, testSettings: { offer: false } }),
      dayHash({ snapshot: multiSnapshot({ recovery: { status: "poor" } }) })
    ];

    expect(new Set([base, ...variants]).size).toBe(variants.length + 1);
  });

  it("bleibt gleich bei leerem Verlauf", () => {
    expect(dayHash({ snapshot, recent: [] })).toBe(base);
  });
});

describe("MultiPlanService.planDay: Fallback auf den letzten gueltigen Plan", () => {
  const cases: Array<[string, () => { complete?: jest.Mock | null; budget?: GenerationBudget }, FallbackReason]> = [
    ["Zeitueberschreitung", () => ({ complete: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "zu langsam")) }), "timeout"],
    ["Antwort, die nicht zum Schema passt", () => ({ complete: jest.fn().mockResolvedValue(generated({ foo: "bar" })) }), "schema_invalid"],
    ["erschoepftem Budget", () => ({ budget: new GenerationBudget(0, 0) }), "budget_exceeded"],
    ["Block durch die Sicherheitsschicht (leere Begruendung)", () => ({ complete: jest.fn().mockResolvedValue(generated(dayPlan([swimSession()], "   "))) }), "sanity_blocked"],
    ["fehlendem API-Key", () => ({ complete: null }), "not_configured"],
    ["unbekanntem Fehler", () => ({ complete: jest.fn().mockRejectedValue(new Error("kaputt")) }), "unknown"]
  ];

  it.each(cases)("liefert bei %s den letzten gueltigen Plan und speichert nichts Neues", async (_name, options, reason) => {
    const stored = storedDay();
    const store = new MemoryDayPlanStoreV2(stored);
    const { service } = setup({ ...options(), store });

    const result = await service.planDay({ snapshot: multiSnapshot() });

    expect(result).toMatchObject({ source: "fallback", fallbackReason: reason, date: "2026-09-29", generatedAt: stored.generatedAt, stale: true });
    expect(result.plan).toEqual(stored.plan);
    expect(result.plan.sessions[0].sport).toBe("bike");
    expect(await store.latest()).toBe(stored);
  });

  it.each(cases)("wirft bei %s ohne frueheren Plan PlanUnavailableError mit dem Grund", async (_name, options, reason) => {
    const { service } = setup(options());

    const failure = await service.planDay({ snapshot: multiSnapshot() }).catch((error: unknown) => error);

    expect(failure).toBeInstanceOf(PlanUnavailableError);
    expect((failure as PlanUnavailableError).reason).toBe(reason);
  });

  it("ruft Claude bei erschoepftem Budget gar nicht auf", async () => {
    const { service, complete } = setup({ budget: new GenerationBudget(1, 100, () => 0) });

    await service.planDay({ snapshot: multiSnapshot() });
    const result = await service.planDay({ snapshot: multiSnapshot(), regenerate: true });

    expect(complete).toHaveBeenCalledTimes(1);
    expect(result).toMatchObject({ source: "fallback", fallbackReason: "budget_exceeded", date: TODAY, stale: false });
  });

  it("markiert einen Plan von heute (anderer Zustand) nicht als veraltet", async () => {
    const store = new MemoryDayPlanStoreV2(storedDay({ date: TODAY, hash: "anderer-zustand" }));
    const { service } = setup({ complete: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store });

    expect(await service.planDay({ snapshot: multiSnapshot() })).toMatchObject({ source: "fallback", date: TODAY, stale: false });
  });

  it("prueft den alten Plan vor dem Ausliefern gegen den heutigen Zustand", async () => {
    const store = new MemoryDayPlanStoreV2(storedDay());
    const { service } = setup({ complete: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store });

    const result = await service.planDay({ snapshot: multiSnapshot({ flags: ["recovery_poor", "overreaching_risk"], recovery: { status: "poor" } }) });

    expect(result.source).toBe("fallback");
    expect(result.plan.sessions).toEqual([]);
    expect(result.adjustments.join(" ")).toContain("Ruhetag erzwungen");
  });

  it("liefert lieber PlanUnavailableError als einen gespeicherten Plan, der die Pruefung nicht mehr besteht", async () => {
    const stored = storedDay();
    const store = new MemoryDayPlanStoreV2({ ...stored, plan: { ...stored.plan, rationale: "" } });
    const { service } = setup({ complete: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")), store });

    await expect(service.planDay({ snapshot: multiSnapshot() })).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "timeout" });
  });
});

describe("MultiPlanService.planDay: Speicherfehler", () => {
  it("behandelt einen Lesefehler wie 'kein Plan' und erzeugt neu", async () => {
    const { service, complete } = setup({ store: failingStore({ latest: async () => Promise.reject(new Error("EACCES")) }) });

    expect((await service.planDay({ snapshot: multiSnapshot() })).source).toBe("claude");
    expect(complete).toHaveBeenCalledTimes(1);
  });

  it("meldet bei Lesefehler und Ausfall von Claude den Grund des Ausfalls", async () => {
    const store = failingStore({ latest: async () => Promise.reject(new Error("EACCES")) });
    const { service } = setup({ complete: jest.fn().mockRejectedValue(new PlanGenerationError("unreachable", "x")), store });

    await expect(service.planDay({ snapshot: multiSnapshot() })).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "unreachable" });
  });

  it("liefert den frischen Plan, auch wenn das Speichern scheitert", async () => {
    const { service } = setup({ store: failingStore({ save: async () => Promise.reject(new Error("Platte voll")) }) });

    const result = await service.planDay({ snapshot: multiSnapshot() });

    expect(result.source).toBe("claude");
    expect(result.plan.sessions[0].sport).toBe("swim");
  });
});

// --- Wochenplan ---

const goodWeek = (): MultiWeekPlanRaw =>
  weekPlan([[weekSession("swim", 800)], [weekSession("bike", 45)], [], [weekSession("run", 20)], [weekSession("swim", 1500)], [], [weekSession("bike", 60)]]);

const weekInput = (extra: Partial<WeekInputV2> = {}): WeekInputV2 => ({ snapshot: multiSnapshot(), fromDate: TODAY, today: TODAY, unavailable: [], recent: [], ...extra });

describe("MultiPlanService.planWeek", () => {
  it("erzeugt die sieben Tage ab from_date", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated(goodWeek())) });

    const result = await service.planWeek(weekInput());

    expect(result).toMatchObject({ fromDate: TODAY, generatedAt: NOW_ISO, adjustments: [] });
    expect(result.plan.days.map((day) => day.date)).toEqual(["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"]);
    expect(result.plan.days[0].sessions[0]).toMatchObject({ sport: "swim", amount: 800, unit: "meters", test: null });
    expect(result.plan.total_minutes).toBe(171);
    expect(result).not.toHaveProperty("wishes");
  });

  it("schickt Wochen-Prompt, den Wunsch als JSON-String und das Wochen-Schema an Claude", async () => {
    const complete = jest.fn().mockResolvedValue(generated(goodWeek()));
    const { service } = setup({ complete });

    const result = await service.planWeek(weekInput({ wishes: "  Am Wochenende lieber Rad  " }));

    const [system, user, schema, options] = complete.mock.calls[0];
    expect(system).toBe(MULTI_WEEK_SYSTEM_PROMPT);
    expect(schema).toBe(MultiWeekPlanSchema);
    expect(options).toEqual({});
    expect(user).toContain("Plane die nächsten sieben Tage. Heute ist Mittwoch, 2026-09-30.");
    expect(user).toContain(JSON.stringify("Am Wochenende lieber Rad"));
    expect(result.wishes).toBe("Am Wochenende lieber Rad");
  });

  it("nimmt nur Training vor from_date in den Verlauf", async () => {
    const complete = jest.fn().mockResolvedValue(generated(goodWeek()));
    const { service } = setup({ complete });
    const recent: RecentTraining[] = [
      { date: "2026-09-28", sport: "swim", minutes: 40, meters: 2000 },
      { date: "2026-09-30", sport: "bike", minutes: 55, meters: 25_000, hard: true },
      { date: "2026-10-01", sport: "run", minutes: 33, meters: 5000 }
    ];

    await service.planWeek(weekInput({ recent }));

    const user = complete.mock.calls[0][1] as string;
    expect(user).toContain("Training der Tage davor: 2026-09-28 Schwimmen 40 min (2000 m).");
    expect(user).not.toContain("Radfahren 55 min");
    expect(user).not.toContain("Laufen 33 min");
  });

  it("gibt die Vorgabe des Gesamtplans nur weiter, wenn es eine gibt", async () => {
    const complete = jest.fn().mockResolvedValue(generated(goodWeek()));
    const { service } = setup({ complete });
    const macroWeeks: MacroWeekTargetV2[] = [{ week_start: "2026-09-28", phase: "base", deload: false, focus: "Grundlage", sports: [{ sport: "swim", amount: 3000, sessions: 3 }] }];

    await service.planWeek(weekInput({ macroWeeks: [] }));
    await service.planWeek(weekInput({ macroWeeks }));

    expect(complete.mock.calls[0][1]).not.toContain("Vorgabe aus dem Gesamtplan");
    expect(complete.mock.calls[1][1]).toContain("Vorgabe aus dem Gesamtplan");
    expect(complete.mock.calls[1][1]).toContain("Woche ab 2026-09-28: Phase base; Schwimmen 3000 m in 3 Einheiten");
  });

  it("wirft schema_invalid, wenn Claudes Antwort nicht zum Schema passt", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated({ rationale: "x", days: "keine" })) });

    await expect(service.planWeek(weekInput())).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "schema_invalid" });
  });

  it("wirft sanity_blocked, wenn die Sicherheitsschicht den Plan blockt", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated({ ...goodWeek(), rationale: " " })) });

    await expect(service.planWeek(weekInput())).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "sanity_blocked" });
  });

  it.each<[string, () => { complete?: jest.Mock | null; budget?: GenerationBudget }, FallbackReason]>([
    ["fehlendem API-Key", () => ({ complete: null }), "not_configured"],
    ["erschoepftem Budget", () => ({ budget: new GenerationBudget(0, 0) }), "budget_exceeded"],
    ["Rate-Limit", () => ({ complete: jest.fn().mockRejectedValue(new PlanGenerationError("rate_limited", "429")) }), "rate_limited"],
    ["unbekanntem Fehler", () => ({ complete: jest.fn().mockRejectedValue(new Error("kaputt")) }), "unknown"]
  ])("wirft bei %s PlanUnavailableError mit dem Grund", async (_name, options, reason) => {
    const { service } = setup(options());

    await expect(service.planWeek(weekInput())).rejects.toMatchObject({ name: "PlanUnavailableError", reason });
  });
});

// --- Gesamtplan ---

const WEEKS = macroWeekStarts(TODAY, GOAL_DAY);
const goodMacro = (): MultiMacroPlanRaw => asBlocks(macroPlan(WEEKS, () => ({ swim: 3000, bike: 90, run: 30 }), (index) => index % 4 === 3));

describe("MultiPlanService.planMacro", () => {
  it("erzeugt den Gesamtplan bis zum Zieltag mit Phasen und Leistungstests", async () => {
    const complete = jest.fn().mockResolvedValue(generated(goodMacro()));
    const { service } = setup({ complete });

    const result = await service.planMacro({ snapshot: multiSnapshot(), today: TODAY });

    expect(result).toMatchObject({ goalDay: GOAL_DAY, generatedAt: NOW_ISO });
    expect(result.plan.weeks).toHaveLength(40);
    expect(result.plan.weeks[0]).toMatchObject({ week_start: "2026-09-28", phase: "base" });
    expect(result.plan.weeks[39]).toMatchObject({ week_start: "2027-06-28", phase: "goal_week" });
    expect(result.plan.weeks[0].sports.map((entry) => entry.sport)).toEqual(["swim", "bike", "run"]);
    expect(result.plan.weeks.flatMap((week) => week.tests).length).toBeGreaterThan(0);
    expect(Array.isArray(result.adjustments)).toBe(true);

    const [system, user, schema, options] = complete.mock.calls[0];
    expect(system).toBe(MULTI_MACRO_SYSTEM_PROMPT);
    // Der Gesamtplan bekommt das laengere Zeitlimit.
    expect(options).toEqual({ macro: true });
    expect(schema).toBe(MultiMacroPlanSchema);
    expect(user).toContain(`Erstelle den Gesamtplan bis zum Zieltag ${GOAL_DAY}. Heute ist ${TODAY}.`);
  });

  it("rechnet Claudes Abschnitte in die Wochen bis zum Zieltag um", async () => {
    const block = (weeks: number, swim: [number, number, number | null], deloadLast: boolean) => ({
      weeks,
      deload_last: deloadLast,
      focus: "Grundlage",
      sports: [{ sport: "swim", start_amount: swim[0], end_amount: swim[1], deload_amount: swim[2], sessions: 2 }]
    });
    const blocks = [block(4, [2000, 2400, 1500], true), ...Array.from({ length: 9 }, () => block(4, [2400, 2400, 1600], true))];
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated({ rationale: "In Abschnitten.", blocks })) });

    const result = await service.planMacro({ snapshot: multiSnapshot(), today: TODAY });

    expect(result.plan.weeks).toHaveLength(40);
    expect(result.plan.weeks.slice(0, 4).map((week) => [week.deload, week.sports.find((entry) => entry.sport === "swim")?.amount])).toEqual([
      [false, 2000],
      [false, 2200],
      [false, 2400],
      [true, 1500]
    ]);
  });

  it("wirft schema_invalid, wenn Claudes Antwort nicht zum Schema passt", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated({ rationale: "nur Text" })) });

    await expect(service.planMacro({ snapshot: multiSnapshot(), today: TODAY })).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "schema_invalid" });
  });

  it("wirft sanity_blocked bei einem Gesamtplan ohne Wochen, mit dem Grund fuer Log und Bewertung", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated({ ...goodMacro(), blocks: [] })) });

    await expect(service.planMacro({ snapshot: multiSnapshot(), today: TODAY })).rejects.toMatchObject({
      name: "PlanUnavailableError",
      reason: "sanity_blocked",
      detail: "Gesamtplan ohne Wochen",
      message: "Kein Plan verfügbar (sanity_blocked: Gesamtplan ohne Wochen)"
    });
  });

  it("wirft bei einem Ausfall von Claude PlanUnavailableError mit dem Grund", async () => {
    const { service } = setup({ complete: jest.fn().mockRejectedValue(new PlanGenerationError("timeout", "t")) });

    await expect(service.planMacro({ snapshot: multiSnapshot(), today: TODAY })).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "timeout" });
  });
});

// --- Feedback zum Gesamtplan ---

const currentWeeks: MacroWeekTargetV2[] = WEEKS.slice(0, 2).map((week_start) => ({
  week_start,
  phase: "base",
  deload: false,
  focus: "Grundlage",
  sports: [
    { sport: "swim", amount: 3000, sessions: 3 },
    { sport: "bike", amount: 90, sessions: 2 }
  ]
}));

const revision = (changes: string[] = ["Mehr Schwimmen im Winter"]): MacroRevisionRaw => ({ ...goodMacro(), changes });

const reviseInput = (extra: Partial<ReviseInput> = {}): ReviseInput => ({
  snapshot: multiSnapshot(),
  today: TODAY,
  plan: { rationale: "Bisheriger Plan.", weeks: currentWeeks },
  feedback: "  Bitte mehr Schwimmen im Winter  ",
  history: [],
  ...extra
});

describe("MultiPlanService.reviseMacro", () => {
  it("aendert den Gesamtplan nach dem Feedback und meldet Aenderungen und Feedback zurueck", async () => {
    const complete = jest.fn().mockResolvedValue(generated(revision()));
    const { service } = setup({ complete });

    const result = await service.reviseMacro(reviseInput({ history: [{ feedback: " Weniger Laufen ", changes: ["Laufen reduziert"] }] }));

    expect(result).toMatchObject({ goalDay: GOAL_DAY, generatedAt: NOW_ISO, changes: ["Mehr Schwimmen im Winter"], feedback: "Bitte mehr Schwimmen im Winter" });
    expect(result.plan.weeks).toHaveLength(40);
    expect(result.plan.weeks[0].phase).toBe("base");

    const [system, user, schema, options] = complete.mock.calls[0];
    expect(system).toBe(MULTI_REVISE_SYSTEM_PROMPT);
    expect(options).toEqual({ macro: true });
    expect(schema).toBe(MacroRevisionSchema);
    expect(user).toContain(JSON.stringify("Bitte mehr Schwimmen im Winter"));
    expect(user).toContain(`Feedback ${JSON.stringify("Weniger Laufen")}; Änderungen: ${JSON.stringify("Laufen reduziert")}`);
    expect(user).toContain("Woche ab 2026-09-28: Phase base; Schwimmen 3000 m in 3 Einheiten, Radfahren 90 min in 2 Einheiten");
  });

  it("kuerzt die Aenderungen: getrimmt, leere entfernt, je hoechstens 200 Zeichen, hoechstens acht", async () => {
    const changes = ["  Mehr Schwimmen  ", "   ", `  ${"x".repeat(250)}  `, "", "c4", "c5", "c6", "c7", "c8", "c9", "c10"];
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated(revision(changes))) });

    const result = await service.reviseMacro(reviseInput());

    expect(result.changes).toEqual(["Mehr Schwimmen", "x".repeat(200), "c4", "c5", "c6", "c7", "c8", "c9"]);
  });

  it("liefert eine leere Liste, wenn Claude keine Aenderung nennt", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated(revision([" "]))) });

    expect((await service.reviseMacro(reviseInput())).changes).toEqual([]);
  });

  it("wirft schema_invalid, wenn die Antwort keine Aenderungen enthaelt", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated(goodMacro())) });

    await expect(service.reviseMacro(reviseInput())).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "schema_invalid" });
  });

  it("wirft sanity_blocked, wenn die Sicherheitsschicht den geaenderten Plan blockt", async () => {
    const { service } = setup({ complete: jest.fn().mockResolvedValue(generated({ ...revision(), rationale: "" })) });

    await expect(service.reviseMacro(reviseInput())).rejects.toMatchObject({ name: "PlanUnavailableError", reason: "sanity_blocked" });
  });

  it.each<[string, () => { complete?: jest.Mock | null; budget?: GenerationBudget }, FallbackReason]>([
    ["fehlendem API-Key", () => ({ complete: null }), "not_configured"],
    ["erschoepftem Budget", () => ({ budget: new GenerationBudget(0, 0) }), "budget_exceeded"],
    ["unbekanntem Fehler", () => ({ complete: jest.fn().mockRejectedValue(new Error("kaputt")) }), "unknown"]
  ])("wirft bei %s PlanUnavailableError mit dem Grund", async (_name, options, reason) => {
    const { service } = setup(options());

    await expect(service.reviseMacro(reviseInput())).rejects.toMatchObject({ name: "PlanUnavailableError", reason });
  });
});
