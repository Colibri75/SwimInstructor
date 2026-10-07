import { buildWeekUserMessageV2 } from "../../../src/plan/multi/prompts";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { multiSnapshot, RUNNER, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

/** Feste Tage: vom Athleten geaendert oder heute schon geplant. Sie bleiben, die anderen Tage richten sich danach. */
const BIKER = { sessions_last_seven_days: 3, sessions_last_four_weeks: 12, minutes_last_seven_days: 180, average_weekly_minutes: 200, meters_last_seven_days: 60_000, average_weekly_meters: 70_000, longest_session_meters: 40_000, longest_session_minutes: 90, days_since_last_session: 1 };
const athlete = () => multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER, bike: BIKER, swim: { meters_last_seven_days: 1000 } } });
const context = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent: [], ...patch });

const fixedRun = { date: TODAY, focus: "Locker laufen", sessions: [{ sport: "run", session_type: "endurance" as const, intensity: "easy" as const, amount: 40, focus: "Locker" }] };

describe("Feste Tage im Wochenplan", () => {
  it("uebernimmt den festen Tag genau so, auch wenn Claude dort etwas anderes plant", () => {
    const raw = weekPlan([[weekSession("swim", 1500)], [weekSession("bike", 60)]]);

    const result = sanitizeWeekV2(raw, athlete(), context({ fixed: [fixedRun] }));

    expect(result.plan.days[0].sessions.map((item) => [item.sport, item.amount, item.intensity])).toEqual([["run", 40, "easy"]]);
    expect(result.plan.days[0].focus).toBe("Locker laufen");
    expect(result.plan.days[1].sessions.map((item) => item.sport)).toEqual(["bike"]);
  });

  it("zaehlt feste harte Tage: kein harter Tag direkt daneben", () => {
    const hardFixed = { date: TODAY, sessions: [{ sport: "run", session_type: "intervals" as const, intensity: "hard" as const, amount: 40, focus: "Tempo" }] };
    const raw = weekPlan([[], [weekSession("bike", 60, { session_type: "intervals", intensity: "hard" })]]);

    const result = sanitizeWeekV2(raw, athlete(), context({ fixed: [hardFixed] }));

    expect(result.plan.days[0].sessions[0].intensity).toBe("hard");
    expect(result.plan.days[1].sessions[0].intensity).toBe("moderate");
  });

  it("zieht den Umfang fester Tage von der Wochengrenze ab", () => {
    const longFixed = { date: TODAY, sessions: [{ sport: "run", session_type: "endurance" as const, intensity: "easy" as const, amount: 60, focus: "Lang" }] };
    const raw = weekPlan([[], [weekSession("run", 60)], [], [weekSession("run", 60)], [], [weekSession("run", 60)]]);

    const free = sanitizeWeekV2(raw, athlete(), context());
    const withFixed = sanitizeWeekV2(raw, athlete(), context({ fixed: [longFixed] }));

    const runMinutes = (result: ReturnType<typeof sanitizeWeekV2>) =>
      result.plan.days.flatMap((day) => day.sessions.filter((item) => item.sport === "run")).reduce((sum, item) => sum + item.amount, 0);
    // Ohne festen Tag passen 3 × 60 min; mit 60 min fest werden die anderen kuerzer, zusammen bleibt es in der Grenze.
    expect(runMinutes(free)).toBe(180);
    expect(withFixed.plan.days[0].sessions[0].amount).toBe(60);
    expect(runMinutes(withFixed) - 60).toBeLessThan(180);
    expect(runMinutes(withFixed)).toBeLessThanOrEqual(runMinutes(free) + 60);
  });

  it("nennt feste Tage im Prompt und laesst Tage ohne Zeit Vorrang", () => {
    const message = buildWeekUserMessageV2({ snapshot: athlete(), context: context({ fixed: [fixedRun] }) });
    const unavailable = sanitizeWeekV2(weekPlan([[weekSession("swim", 1500)]]), athlete(), context({ fixed: [fixedRun], unavailable: [TODAY] }));

    expect(message).toContain(`${TODAY} (fest: Laufen, endurance, easy, 40 min)`);
    expect(message).toContain("Übernimm sie genau so");
    expect(unavailable.plan.days[0].sessions).toEqual([]);
  });
});
