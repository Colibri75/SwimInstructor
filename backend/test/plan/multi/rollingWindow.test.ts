import { dayLimits } from "../../../src/plan/multi/limits";
import { buildWeekUserMessageV2 } from "../../../src/plan/multi/prompts";
import { RecentTraining } from "../../../src/plan/multi/schemas";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { multiSnapshot, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

// Schwimmen: in 7 Tagen hoechstens 4350 m (aus dem Snapshot der Fixtures).
const athlete = multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { swim: { meters_last_seven_days: 3400 } } });
const context = (recent: RecentTraining[], patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent, ...patch });
const swim = (date: string, meters: number): RecentTraining => ({ date, sport: "swim", minutes: Math.round(meters / 50), meters });
const css = () => weekSession("swim", 1000, { session_type: "test", intensity: "hard", test_id: "css_400_200" });
// 3400 m am Montag und Dienstag vor dem Plan (Plan ab Mittwoch, 30.09.).
const busy = [swim("2026-09-28", 1700), swim("2026-09-29", 1700)];

describe("Gleitende 7 Tage im Wochenplan", () => {
  it("verlegt einen Test, der an seinem Tag nicht mehr in die 7 Tage passt, auf einen spaeteren Schwimmtag", () => {
    const raw = weekPlan([[], [css()], [], [], [], [weekSession("swim", 800)]]);

    const result = sanitizeWeekV2(raw, athlete, context(busy));

    expect(result.plan.days[1].sessions).toMatchObject([{ sport: "swim", session_type: "endurance", intensity: "easy", amount: 800, test: null }]);
    expect(result.plan.days[5].sessions).toMatchObject([{ sport: "swim", session_type: "test", amount: 1000, test: { id: "css_400_200" } }]);
    expect(result.adjustments).toEqual(["Donnerstag, 01.10.: Leistungstest Schwimmen auf Montag, 05.10. verlegt (in 7 Tagen höchstens 4350 m, davon schon 3400 m)"]);
  });

  it("macht den Test zur lockeren Einheit, wenn kein spaeterer Tag passt", () => {
    const raw = weekPlan([[], [css()]]);

    const result = sanitizeWeekV2(raw, athlete, context(busy));

    expect(result.plan.days[1].sessions).toMatchObject([{ sport: "swim", session_type: "endurance", intensity: "easy", test: null }]);
    expect(result.plan.days[1].sessions[0].amount).toBeLessThanOrEqual(950);
    expect(result.adjustments[0]).toBe("Donnerstag, 01.10.: kein Leistungstest Schwimmen (in 7 Tagen höchstens 4350 m, davon schon 3400 m), lockere Einheit statt dessen");
  });

  it("laesst einen Test stehen, der in die 7 Tage passt", () => {
    const raw = weekPlan([[], [css()]]);

    const result = sanitizeWeekV2(raw, athlete, context([swim("2026-09-28", 1700)]));

    expect(result.plan.days[1].sessions[0].test?.id).toBe("css_400_200");
    expect(result.adjustments).toEqual([]);
  });

  it("zaehlt das Training davor und die geplanten Tage davor und kuerzt oder streicht, was nicht mehr passt", () => {
    const raw = weekPlan([[], [weekSession("swim", 2000)], [weekSession("swim", 1000)], [], [], [], [weekSession("swim", 1000)]]);

    const result = sanitizeWeekV2(raw, athlete, context([swim("2026-09-27", 2000)]));

    // Freitag: 2000 m am Sonntag davor und 2000 m am Donnerstag, es bleiben 350 m (weniger als eine Einheit).
    expect(result.plan.days.map((day) => day.sessions.map((item) => item.amount))).toEqual([[], [2000], [], [], [], [], [1000]]);
    expect(result.plan.days[2].focus).toBe("Ruhetag");
    expect(result.adjustments).toEqual(["Freitag, 02.10.: Schwimmen gestrichen (in 7 Tagen höchstens 4350 m, davon schon 4000 m)"]);
  });

  it("prueft heute nicht noch einmal (dafuer gelten die Werte aus Health)", () => {
    const raw = weekPlan([[weekSession("swim", 900)]]);

    const result = sanitizeWeekV2(raw, athlete, context(busy));

    expect(result.plan.days[0].sessions.map((item) => item.amount)).toEqual([900]);
  });

  it("nennt Claude, was vom Training davor in die geplanten Tage reicht", () => {
    const message = buildWeekUserMessageV2({ snapshot: athlete, context: context(busy) });

    expect(message).toContain(
      "  Die Grenze gilt für jede Spanne von 7 Tagen, auch über den Planbeginn: Vom Training davor zählen in den 7 Tagen bis Donnerstag 01.10. schon 3400 m, bis Freitag 02.10. schon 3400 m, bis Samstag 03.10. schon 3400 m, bis Sonntag 04.10. schon 3400 m, bis Montag 05.10. schon 1700 m, dazu was du an den Tagen davor planst. Lege Tests und lange Einheiten auf Tage mit genug Platz."
    );
  });
});

describe("Gleitende 7 Tage in der Vorschau", () => {
  it("rechnet das Fenster ab dem Tag der Vorschau aus dem Verlauf, am Tag selbst mit den Werten aus Health", () => {
    const recent = [swim("2026-09-24", 1700), swim("2026-09-29", 1700)];

    const preview = dayLimits(athlete, "2026-10-01", recent, true).sports.get("swim")!;
    const today = dayLimits(athlete, TODAY, recent).sports.get("swim")!;

    // Am 01.10. faellt der 24.09. heraus: nur 1700 m in den sechs Tagen davor.
    expect(preview.lastSeven).toBe(1700);
    expect(preview.maxAmount).toBe(2500);
    expect(today.lastSeven).toBe(3400);
    expect(today.maxAmount).toBe(950);
  });
});
