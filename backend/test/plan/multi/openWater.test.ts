import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { OPEN_WATER_RULES, openWaterBlocked } from "../../../src/plan/multi/openWater";
import { buildDayUserMessageV2, buildWeekUserMessageV2, MULTI_WEEK_SYSTEM_PROMPT } from "../../../src/plan/multi/prompts";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { SnapshotSchema, SnapshotV2 } from "../../../src/plan/snapshot";
import { DayWeather } from "../../../src/plan/weather";
import { dayPlan, multiSnapshot, RUNNER, session, swimStep, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

const SWIMMER = { meters_last_seven_days: 6000, average_weekly_meters: 6000, longest_session_meters: 2500, sessions_last_four_weeks: 12 };
const context = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent: [], ...patch });
const warm = (date: string): DayWeather => ({ date, temp_max_c: 24, temp_min_c: 14, precipitation_mm: 0, precipitation_probability: 0, wind_max_kmh: 10, weather_code: 0 });

/** Ziel in `days` Tagen, das Schwimmen im Freiwasser (oder im Becken). */
function athlete(days: number, openWater = true): SnapshotV2 {
  const base = multiSnapshot({ daysUntilGoal: days, load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER, swim: SWIMMER } });
  return {
    ...base,
    training_goal: {
      ...base.training_goal,
      disciplines: base.training_goal.disciplines.map((discipline) => (discipline.sport === "swim" ? { ...discipline, open_water: openWater } : discipline))
    }
  };
}

const swims = (result: ReturnType<typeof sanitizeWeekV2>) =>
  result.plan.days.flatMap((day) => day.sessions.filter((item) => item.sport === "swim").map((item) => `${day.date}:${item.amount}${item.open_water ? "*" : ""}`));

describe("Freiwasser im Wochenplan", () => {
  it("setzt in den Wochen vor einem Ziel im Freiwasser die laengste lockere Schwimmeinheit dorthin", () => {
    const raw = weekPlan([[weekSession("swim", 1500)], [], [weekSession("swim", 2000)], [], [weekSession("swim", 1800, { intensity: "hard", session_type: "intervals" })]]);

    const result = sanitizeWeekV2(raw, athlete(40), context({ equipment: ["open_water"] }));

    expect(swims(result)).toEqual(["2026-09-30:1500", "2026-10-02:2000*", "2026-10-04:1800"]);
    expect(result.adjustments).toContain("Freitag, 02.10.: Schwimmen im Freiwasser (Ziel im Freiwasser)");
  });

  it("laesst eine von Claude geplante Freiwasser-Einheit stehen und setzt keine zweite", () => {
    const raw = weekPlan([[weekSession("swim", 1500, { open_water: true })], [], [weekSession("swim", 2000)]]);

    const result = sanitizeWeekV2(raw, athlete(40), context({ equipment: ["open_water"] }));

    expect(swims(result)).toEqual(["2026-09-30:1500*", "2026-10-02:2000"]);
  });

  it("setzt nichts, wenn das Ziel weit weg, im Becken oder ohne Zugang ist", () => {
    const raw = weekPlan([[weekSession("swim", 1500)], [], [weekSession("swim", 2000)]]);
    const far = OPEN_WATER_RULES.raceWeeks * 7 + 10;

    expect(swims(sanitizeWeekV2(raw, athlete(far), context({ equipment: ["open_water"] })))).toEqual(["2026-09-30:1500", "2026-10-02:2000"]);
    expect(swims(sanitizeWeekV2(raw, athlete(40, false), context({ equipment: ["open_water"] })))).toEqual(["2026-09-30:1500", "2026-10-02:2000"]);
    expect(swims(sanitizeWeekV2(raw, athlete(40), context({ equipment: [] })))).toEqual(["2026-09-30:1500", "2026-10-02:2000"]);
  });

  it("holt Freiwasser ohne Zugang, bei Unwetter, Kaelte und fuer Tests ins Becken", () => {
    const raw = weekPlan([
      [weekSession("swim", 1500, { open_water: true })],
      [weekSession("swim", 1500, { open_water: true })],
      [weekSession("run", 30, { open_water: true })]
    ]);
    const weather = [{ ...warm("2026-09-30"), weather_code: 95 }, { ...warm("2026-10-01"), temp_max_c: 12 }];

    const result = sanitizeWeekV2(raw, athlete(200), context({ equipment: ["open_water"], weather }));
    const noAccess = sanitizeWeekV2(weekPlan([[weekSession("swim", 1500, { open_water: true })]]), athlete(200), context({ equipment: [] }));

    expect(result.plan.days.slice(0, 3).map((day) => day.sessions[0]?.open_water)).toEqual([false, false, false]);
    expect(result.adjustments).toEqual(
      expect.arrayContaining([
        "Mittwoch, 30.09.: Gewitter angesagt, Schwimmen im Becken",
        "Donnerstag, 01.10.: zu kalt fürs Freiwasser (höchstens 12 °C), Schwimmen im Becken",
        "Freitag, 02.10.: Laufen im Becken (Freiwasser gibt es nicht)"
      ])
    );
    expect(noAccess.adjustments).toContain("Mittwoch, 30.09.: Schwimmen im Becken (kein Zugang zu Freiwasser angegeben)");
  });

  it("nennt Claude Zugang, Ziel und Regel im Prompt", () => {
    const message = buildWeekUserMessageV2({ snapshot: athlete(40), context: context({ equipment: ["open_water"] }) });
    const noAccess = buildWeekUserMessageV2({ snapshot: athlete(40), context: context({ equipment: [] }) });

    expect(MULTI_WEEK_SYSTEM_PROMPT).toContain("open_water true heißt im Freiwasser");
    expect(message).toContain("- Schwimmen: 1500 m in 30 min im Freiwasser.");
    expect(message).toContain("- Schwimmen: Freiwasser möglich (open_water true)");
    expect(message).toContain("plane in diesen Tagen mindestens eine Schwimmen-Einheit dort");
    expect(noAccess).toContain("- Schwimmen: kein Zugang zu Freiwasser angegeben (open_water false).");
    expect(noAccess).toContain("bring Elemente davon ins Becken");
  });
});

describe("Freiwasser im Tagesplan", () => {
  it("behaelt Freiwasser bei passendem Wetter und holt es sonst ins Becken", () => {
    const raw = dayPlan([session("swim", { open_water: true, steps: [swimStep(1500)] })]);

    expect(sanitizeDayV2(raw, athlete(40), { date: TODAY, equipment: ["open_water"], weather: warm(TODAY) }).plan.sessions[0].open_water).toBe(true);
    const cold = sanitizeDayV2(raw, athlete(40), { date: TODAY, equipment: ["open_water"], weather: { ...warm(TODAY), temp_max_c: 10 } });
    expect(cold.plan.sessions[0].open_water).toBe(false);
    expect(cold.adjustments).toContain("zu kalt fürs Freiwasser (höchstens 10 °C): Schwimmen im Becken");
  });

  it("nennt die Vorgabe des Wochenplans im Prompt", () => {
    const message = buildDayUserMessageV2({
      snapshot: athlete(40),
      date: TODAY,
      equipment: ["open_water"],
      dayTarget: { sessions: [{ sport: "swim", session_type: "endurance", intensity: "easy", amount: 1500, focus: "Orientierung", open_water: true }] }
    });

    expect(message).toContain("im Freiwasser (open_water true)");
  });
});

describe("Ziel im Freiwasser", () => {
  it("geht nur bei Sportarten mit Freiwasser", () => {
    const base = athlete(40);
    const bikeInLake = { ...base, training_goal: { ...base.training_goal, disciplines: base.training_goal.disciplines.map((d) => (d.sport === "bike" ? { ...d, open_water: true } : d)) } };

    expect(SnapshotSchema.safeParse(base).success).toBe(true);
    expect(SnapshotSchema.safeParse(bikeInLake).success).toBe(false);
  });

  it("ohne Vorhersage gibt es keinen Einwand", () => {
    expect(openWaterBlocked(undefined)).toBeNull();
    expect(openWaterBlocked(warm(TODAY))).toBeNull();
  });
});
