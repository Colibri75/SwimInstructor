import request from "supertest";
import { GenerationBudget } from "../../../src/plan/budget";
import { dayLimits, hardOn, painRestriction } from "../../../src/plan/multi/limits";
import { buildDayUserMessageV2, buildWeekUserMessageV2, MULTI_WEEK_SYSTEM_PROMPT } from "../../../src/plan/multi/prompts";
import { multiRoutes } from "../../../src/plan/multi/routes";
import { RecentTraining } from "../../../src/plan/multi/schemas";
import { MultiPlanService } from "../../../src/plan/multi/service";
import { MemoryDayPlanStoreV2 } from "../../../src/plan/multi/store";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { createLogger } from "../../../src/logger";
import { buildApp, TEST_TOKEN, testConfig } from "../../helpers";
import { multiSnapshot, RUNNER, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

/** Mittwoch 30.09.: Laufen am Dienstag mit Beschwerden. */
const run = (pain: number, extra: Partial<RecentTraining> = {}): RecentTraining => ({ date: "2026-09-29", sport: "run", minutes: 40, meters: 6000, pain, pain_area: "knee", ...extra });
const runner = () => multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER } });

describe("Beschwerden nach einer Einheit", () => {
  it("bremsen je nach Staerke unterschiedlich lange", () => {
    expect(painRestriction([run(1)], "run", "2026-09-29")).toMatchObject({ blocked: false, maxIntensity: "moderate", amountFactor: 1, until: "2026-09-29" });
    expect(painRestriction([run(1)], "run", "2026-09-30")).toBeNull();
    expect(painRestriction([run(2)], "run", "2026-09-30")).toMatchObject({ blocked: false, maxIntensity: "easy", amountFactor: 0.5, until: "2026-09-30" });
    expect(painRestriction([run(2)], "run", "2026-10-01")).toBeNull();
    expect(painRestriction([run(3)], "run", "2026-10-01")).toMatchObject({ blocked: true, until: "2026-10-01" });
    expect(painRestriction([run(3)], "run", "2026-10-02")).toBeNull();
  });

  it("gelten nur fuer die Sportart, nicht vor dem Tag der Meldung, und die staerkste zaehlt", () => {
    expect(painRestriction([run(3)], "bike", "2026-09-30")).toBeNull();
    expect(painRestriction([run(3)], "run", "2026-09-28")).toBeNull();
    expect(painRestriction([run(0)], "run", "2026-09-29")).toBeNull();
    const both = painRestriction([run(1, { date: "2026-09-30" }), run(2)], "run", "2026-09-30");
    expect(both?.maxIntensity).toBe("easy");
    expect(both?.reason).toBe("deutliche Beschwerden (Knie) nach Laufen am 29.09.");
  });

  it("sperren die Sportart heute oder senken Intensitaet und Umfang", () => {
    const strong = dayLimits(runner(), TODAY, [run(3)]).sports.get("run");
    const moderate = dayLimits(runner(), TODAY, [run(2)]).sports.get("run");
    const none = dayLimits(runner(), TODAY, []).sports.get("run");

    expect(strong?.blockedReason).toBe("starke Beschwerden (Knie) nach Laufen am 29.09.: Pause bis 01.10.");
    expect(moderate?.blockedReason).toBeNull();
    expect(moderate?.maxIntensity).toBe("easy");
    expect(moderate?.maxAmount).toBeLessThanOrEqual(Math.floor((none?.maxAmount ?? 0) / 2 / 5) * 5 + 5);
    expect(moderate?.intensityReasons).toContain("deutliche Beschwerden (Knie) nach Laufen am 29.09.");
  });

  it("wirken in der Woche auf die Tage danach, nicht auf andere Sportarten", () => {
    const raw = weekPlan([[weekSession("run", 30, { intensity: "hard", session_type: "intervals" })], [weekSession("run", 40)], [weekSession("run", 30)], [weekSession("bike", 60)]]);
    const context: WeekContextV2 = { today: TODAY, dates: weekDates(), unavailable: [], recent: [], reports: [run(3)] };

    const result = sanitizeWeekV2(raw, multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER, bike: { minutes_last_seven_days: 60, average_weekly_minutes: 120, longest_session_minutes: 60, days_since_last_session: 2 } } }), context);

    expect(result.plan.days.slice(0, 4).map((day) => day.sessions.map((session) => session.sport))).toEqual([[], [], ["run"], ["bike"]]);
    expect(result.adjustments).toEqual(
      expect.arrayContaining(["Mittwoch, 30.09.: Laufen gestrichen (starke Beschwerden (Knie) nach Laufen am 29.09.)", "Donnerstag, 01.10.: Laufen gestrichen (starke Beschwerden (Knie) nach Laufen am 29.09.)"])
    );
  });

  it("senken bei deutlichen Beschwerden auf locker und die Haelfte", () => {
    const raw = weekPlan([[weekSession("run", 40, { intensity: "hard", session_type: "intervals" })]]);
    const result = sanitizeWeekV2(raw, runner(), { today: TODAY, dates: weekDates(), unavailable: [], recent: [], reports: [run(2)] });

    const session = result.plan.days[0].sessions[0];
    expect(session.intensity).toBe("easy");
    expect(session.amount).toBeLessThan(40);
    expect(result.adjustments.some((line) => line.includes("deutliche Beschwerden"))).toBe(true);
  });
});

describe("Gefuehlte Anstrengung", () => {
  it("macht eine Einheit ab 8 von 10 zur harten, auch wenn sie nicht hart geplant war", () => {
    expect(hardOn([{ date: "2026-09-29", sport: "bike", minutes: 60, meters: 0, effort: 8 }], "2026-09-29")).toBe(true);
    expect(hardOn([{ date: "2026-09-29", sport: "bike", minutes: 60, meters: 0, effort: 7 }], "2026-09-29")).toBe(false);
    const limits = dayLimits(runner(), TODAY, [{ date: "2026-09-29", sport: "run", minutes: 60, meters: 0, effort: 9 }]);
    expect(limits.maxIntensity).toBe("moderate");
  });
});

describe("Prompt: echtes Training", () => {
  it("nennt Anstrengung, Beschwerden, Ausfaelle und den Anlass", () => {
    const message = buildWeekUserMessageV2({
      snapshot: runner(),
      context: {
        today: TODAY,
        dates: weekDates(),
        unavailable: [],
        recent: [run(2, { effort: 9 })],
        reports: [run(2, { effort: 9 })],
        missed: [{ date: "2026-09-28", sport: "run", session_type: "intervals", intensity: "hard", amount: 45 }],
        reason: "pain"
      }
    });

    expect(message).toContain("Anlass der Neuplanung: der Athlet hat nach einer Einheit Beschwerden gemeldet.");
    expect(message).toContain("2026-09-29 Laufen 40 min (6,0 km), Anstrengung 9 von 10, deutliche Beschwerden (Knie)");
    expect(message).toContain("- Laufen: deutliche Beschwerden (Knie) nach Laufen am 29.09.: bis einschließlich 30.09. nur locker und höchstens 50 % der Einheitengrenze.");
    expect(message).toContain("- Montag 2026-09-28: Laufen 45 min, Typ intervals, Intensität hard");
    expect(MULTI_WEEK_SYSTEM_PROMPT).toContain("12. Der Plan richtet sich nach dem echten Training");
  });

  it("laesst den Anlass bei der taeglichen Abstimmung weg", () => {
    const message = buildWeekUserMessageV2({ snapshot: runner(), context: { today: TODAY, dates: weekDates(), unavailable: [], recent: [], reason: "daily" } });
    expect(message).not.toContain("Anlass der Neuplanung");
    expect(message).not.toContain("Ausgefallene Einheiten");
    expect(message).not.toContain("Beschwerden (vom Athleten");
  });

  it("nennt die Bremse auch im Tagesplan", () => {
    const message = buildDayUserMessageV2({ snapshot: runner(), date: TODAY, recent: [run(3)] });
    expect(message).toContain("- Laufen: starke Beschwerden (Knie) nach Laufen am 29.09.: keine Einheiten Laufen bis einschließlich 01.10.");
    expect(message).toContain("- Laufen: heute nicht (starke Beschwerden (Knie) nach Laufen am 29.09.: Pause bis 01.10.");
  });
});

describe("Route /v1/plan/week: echtes Training", () => {
  it("nimmt Ausfaelle, Anlass, Anstrengung und Beschwerden an und prueft sie", async () => {
    const complete = jest.fn().mockResolvedValue({ raw: weekPlan([[weekSession("swim", 800)]]), model: "m", usage: { inputTokens: 1, outputTokens: 1 } });
    const service = new MultiPlanService({ generator: { complete }, store: new MemoryDayPlanStoreV2(), budget: new GenerationBudget(100, 100), logger: createLogger(testConfig), timezone: "Europe/Berlin", now: () => new Date("2026-09-30T10:00:00Z") });
    const app = buildApp({ registerV1Routes: multiRoutes(service) });
    const body = {
      plan_version: 2,
      snapshot: multiSnapshot(),
      from_date: TODAY,
      today: TODAY,
      reason: "missed",
      recent_training: [{ date: "2026-09-30", sport: "run", minutes: 30, meters: 5000, effort: 6, pain: 1, pain_area: "shin" }],
      missed_sessions: [{ date: "2026-09-28", sport: "bike", session_type: "endurance", intensity: "easy", amount: 60 }]
    };

    const ok = await request(app).post("/v1/plan/week").set("Authorization", `Bearer ${TEST_TOKEN}`).send(body);
    const badPain = await request(app).post("/v1/plan/week").set("Authorization", `Bearer ${TEST_TOKEN}`).send({ ...body, recent_training: [{ ...body.recent_training[0], pain: 4 }] });
    const badDate = await request(app).post("/v1/plan/week").set("Authorization", `Bearer ${TEST_TOKEN}`).send({ ...body, missed_sessions: [{ ...body.missed_sessions[0], date: "2026-02-30" }] });
    const badReason = await request(app).post("/v1/plan/week").set("Authorization", `Bearer ${TEST_TOKEN}`).send({ ...body, reason: "langeweile" });

    expect(ok.status).toBe(200);
    expect(complete.mock.calls[0][1]).toContain("Anlass der Neuplanung: geplante Einheiten sind ausgefallen.");
    expect(complete.mock.calls[0][1]).toContain("leichte Beschwerden (Schienbein)");
    expect([badPain.status, badDate.status, badReason.status]).toEqual([400, 400, 400]);
    expect(badDate.body.details[0].path).toBe("missed_sessions.0.date");
  });
});
