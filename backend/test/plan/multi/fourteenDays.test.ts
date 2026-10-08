import { buildWeekUserMessageV2 } from "../../../src/plan/multi/prompts";
import { RecentTraining } from "../../../src/plan/multi/schemas";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { multiSnapshot, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

// Schwimmen: in 7 Tagen hoechstens 4350 m (aus dem Snapshot der Fixtures); Plan ab Mittwoch, 30.09., bis Dienstag, 13.10.
const rested = multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { swim: { meters_last_seven_days: 3400 }, bike: { minutes_last_seven_days: 30 } } });
const context = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(TODAY, 14), unavailable: [], recent: [], ...patch });
const hard = (sport: string, amount: number) => weekSession(sport, amount, { intensity: "hard", session_type: "intervals" });
const swimDays = (amount: number) => Array.from({ length: 14 }, (_, index) => (index % 7 === 1 || index % 7 === 3 || index % 7 === 5 ? [weekSession("swim", amount)] : []));

describe("Plan fuer 14 Tage", () => {
  it("liefert alle 14 Tage und gibt jedem Block von 7 Tagen die Wochengrenze", () => {
    const result = sanitizeWeekV2(weekPlan(swimDays(1400)), rested, context());

    expect(result.blocked).toBeNull();
    expect(result.plan.days.map((day) => day.date)).toEqual(weekDates(TODAY, 14));
    const swum = (from: number) => result.plan.days.slice(from, from + 7).reduce((sum, day) => sum + day.sessions.reduce((s, item) => s + item.amount, 0), 0);
    // Je Block 4200 m: passt in 4350 m, also bleibt der zweite Block so voll wie der erste.
    expect([swum(0), swum(7)]).toEqual([4200, 4200]);
    expect(result.adjustments).toEqual([]);
  });

  it("zaehlt den ersten Block fuer die 7 Tage ueber die Blockgrenze", () => {
    const days = Array.from({ length: 14 }, () => [] as ReturnType<typeof weekSession>[]);
    days[5] = [weekSession("swim", 2000)];
    days[6] = [weekSession("swim", 2000)];
    days[7] = [weekSession("swim", 2000)];

    const result = sanitizeWeekV2(weekPlan(days), rested, context());

    // Am 8. Tag zaehlen schon 4000 m aus dem ersten Block: es bleiben 350 m, weniger als eine Einheit.
    expect(result.plan.days[7].sessions).toEqual([]);
    expect(result.adjustments).toContain("Mittwoch, 07.10.: Schwimmen gestrichen (in 7 Tagen höchstens 4350 m, davon schon 4000 m)");
  });

  it("erlaubt keine harten Tage hintereinander ueber die Blockgrenze", () => {
    const days = Array.from({ length: 14 }, () => [] as ReturnType<typeof weekSession>[]);
    days[6] = [hard("bike", 60)];
    days[7] = [hard("bike", 60)];

    const result = sanitizeWeekV2(weekPlan(days), rested, context());

    expect(result.plan.days[6].sessions[0].intensity).toBe("hard");
    expect(result.plan.days[7].sessions[0].intensity).not.toBe("hard");
  });

  it("plant keinen zweiten Test derselben Sportart im zweiten Block", () => {
    const days = Array.from({ length: 14 }, () => [] as ReturnType<typeof weekSession>[]);
    days[1] = [weekSession("swim", 1000, { session_type: "test", intensity: "hard", test_id: "css_400_200" })];
    days[9] = [weekSession("swim", 1000, { session_type: "test", intensity: "hard", test_id: "css_400_200" })];

    const result = sanitizeWeekV2(weekPlan(days), rested, context());

    expect(result.plan.days[1].sessions[0].test?.id).toBe("css_400_200");
    expect(result.plan.days[9].sessions[0].test).toBeNull();
  });

  it("haelt sieben Tage wie bisher in einem Block", () => {
    const result = sanitizeWeekV2(weekPlan(swimDays(1400).slice(0, 7)), rested, context({ dates: weekDates() }));

    expect(result.plan.days).toHaveLength(7);
  });

  it("nennt Claude beide Bloecke und dass die Grenzen je Block gelten", () => {
    const recent: RecentTraining[] = [];
    const message = buildWeekUserMessageV2({ snapshot: rested, context: context({ recent }) });

    expect(message).toContain("Plane die nächsten 14 Tage.");
    expect(message).toContain("Block 1:\n- Mittwoch 2026-09-30");
    expect(message).toContain("Block 2:\n- Mittwoch 2026-10-07");
    expect(message).toContain("für jeden Block von 7 Tagen");
    expect(message).toContain("höchstens 5 Trainingstage");
  });
});
