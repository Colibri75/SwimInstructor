import request from "supertest";
import { GenerationBudget } from "../../../src/plan/budget";
import { multiRoutes } from "../../../src/plan/multi/routes";
import { MultiPlanService } from "../../../src/plan/multi/service";
import { MemoryDayPlanStoreV2 } from "../../../src/plan/multi/store";
import { createLogger } from "../../../src/logger";
import { buildApp, TEST_TOKEN, testConfig } from "../../helpers";
import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { buildDayUserMessageV2, buildWeekUserMessageV2, MULTI_DAY_SYSTEM_PROMPT, MULTI_WEEK_SYSTEM_PROMPT } from "../../../src/plan/multi/prompts";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { DayWeather, OpenMeteoProvider, roundLocation, severeWeather, weatherText } from "../../../src/plan/weather";
import { dayPlan, multiSnapshot, RUNNER, session, step, swimStep, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

/** Gut trainiert in allen drei Sportarten, die letzte harte Einheit liegt Tage zurueck. */
const BIKER = { sessions_last_seven_days: 3, sessions_last_four_weeks: 12, minutes_last_seven_days: 180, average_weekly_minutes: 200, meters_last_seven_days: 60_000, average_weekly_meters: 70_000, longest_session_meters: 40_000, longest_session_minutes: 90, days_since_last_session: 1 };
const athlete = () => multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER, bike: BIKER, swim: { meters_last_seven_days: 1000 } } });
const context = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent: [], ...patch });
const sunny = (date: string): DayWeather => ({ date, temp_max_c: 20, temp_min_c: 10, precipitation_mm: 0, precipitation_probability: 0, wind_max_kmh: 10, weather_code: 0 });

describe("Koppeltraining", () => {
  it("bleibt bei Laufen direkt nach dem Rad und wird sonst eine eigene Einheit", () => {
    const raw = weekPlan([
      [weekSession("bike", 60), weekSession("run", 20, { brick: true })],
      [weekSession("run", 20, { brick: true })],
      [weekSession("run", 20), weekSession("bike", 45, { brick: true })],
      [weekSession("swim", 1000), weekSession("bike", 45, { brick: true })]
    ]);

    const result = sanitizeWeekV2(raw, athlete(), context());

    expect(result.plan.days.slice(0, 4).map((day) => day.sessions.map((item) => `${item.sport}${item.brick ? "*" : ""}`))).toEqual([["bike", "run*"], ["run"], ["run", "bike"], ["swim", "bike*"]]);
    expect(result.adjustments).toEqual(
      expect.arrayContaining(["Donnerstag, 01.10.: Laufen als eigene Einheit (Koppeltraining nur direkt nach Radfahren)", "Freitag, 02.10.: Radfahren als eigene Einheit (Koppeltraining nur direkt nach Schwimmen)"])
    );
  });

  it("loest sich still, wenn die erste Einheit gestrichen wird", () => {
    const raw = weekPlan([[weekSession("bike", 60), weekSession("run", 20, { brick: true })]]);
    const result = sanitizeWeekV2(raw, athlete(), context({ reports: [{ date: "2026-09-29", sport: "bike", minutes: 60, meters: 0, pain: 3 }] }));

    expect(result.plan.days[0].sessions.map((item) => [item.sport, item.brick])).toEqual([["run", false]]);
  });

  it("gilt auch im Tagesplan", () => {
    const raw = dayPlan([
      session("bike", { steps: [step({ duration_seconds: 1800 })] }),
      session("run", { brick: true, steps: [step({ duration_seconds: 900 })] })
    ]);
    const swapped = dayPlan([
      session("run", { steps: [step({ duration_seconds: 900 })] }),
      session("bike", { brick: true, steps: [step({ duration_seconds: 1800 })] })
    ]);

    expect(sanitizeDayV2(raw, athlete(), { date: TODAY }).plan.sessions.map((item) => item.brick)).toEqual([false, true]);
    const fixed = sanitizeDayV2(swapped, athlete(), { date: TODAY });
    expect(fixed.plan.sessions.map((item) => item.brick)).toEqual([false, false]);
    expect(fixed.adjustments).toContain("Radfahren als eigene Einheit (Koppeltraining nur direkt nach Schwimmen)");
  });
});

describe("Drinnen und Wetter", () => {
  it("erlaubt drinnen nur mit Rolle oder Laufband, ohne Equipment-Angabe immer", () => {
    const raw = weekPlan([[weekSession("bike", 60, { indoor: true })], [weekSession("run", 30, { indoor: true })], [weekSession("swim", 1000, { indoor: true })]]);

    const withoutTrainer = sanitizeWeekV2(raw, athlete(), context({ equipment: ["treadmill"] }));
    const unknown = sanitizeWeekV2(raw, athlete(), context());

    expect(withoutTrainer.plan.days.slice(0, 3).map((day) => day.sessions[0].indoor)).toEqual([false, true, false]);
    expect(withoutTrainer.adjustments).toEqual(
      expect.arrayContaining(["Mittwoch, 30.09.: Radfahren draußen (kein Rolle angegeben)", "Freitag, 02.10.: Schwimmen draußen (drinnen gibt es nicht)"])
    );
    expect(unknown.plan.days.slice(0, 2).map((day) => day.sessions[0].indoor)).toEqual([true, true]);
  });

  it("holt wetterabhaengige Einheiten bei Gewitter nach drinnen, wenn das geht", () => {
    const storm = { ...sunny(TODAY), weather_code: 95 };
    const raw = weekPlan([[weekSession("bike", 60), weekSession("swim", 1000)], [weekSession("run", 30)]]);

    const result = sanitizeWeekV2(raw, athlete(), context({ weather: [storm, { ...sunny("2026-10-01"), wind_max_kmh: 70 }], equipment: ["indoor_trainer"] }));

    expect(result.plan.days[0].sessions.map((item) => [item.sport, item.indoor])).toEqual([["bike", true], ["swim", false]]);
    // Laufen ohne Laufband bleibt draussen; Claude bekommt das Wetter im Prompt.
    expect(result.plan.days[1].sessions[0].indoor).toBe(false);
    expect(result.adjustments).toContain("Mittwoch, 30.09.: Gewitter angesagt, Radfahren drinnen (Rolle)");
  });

  it("erkennt Unwetter, aber nicht Hitze oder leichten Regen", () => {
    expect(severeWeather({ ...sunny(TODAY), weather_code: 96 })).toBe("Gewitter angesagt");
    expect(severeWeather({ ...sunny(TODAY), wind_max_kmh: 65 })).toBe("Sturm angesagt (bis 65 km/h)");
    expect(severeWeather({ ...sunny(TODAY), precipitation_mm: 25, weather_code: 65 })).toBe("Starkregen angesagt (25 mm)");
    expect(severeWeather({ ...sunny(TODAY), temp_min_c: -3, weather_code: 71, precipitation_mm: 2 })).toBe("Glätte möglich");
    expect(severeWeather({ ...sunny(TODAY), temp_max_c: 34 })).toBeNull();
    expect(severeWeather({ ...sunny(TODAY), precipitation_mm: 3, weather_code: 61 })).toBeNull();
    expect(weatherText({ ...sunny(TODAY), temp_max_c: 31, precipitation_mm: 2.5, precipitation_probability: 60, weather_code: 61 })).toBe("10 bis 31 °C, Regen (60 %, 2,5 mm), Wind bis 10 km/h, heiß");
  });

  it("holt die Vorhersage bei Open-Meteo mit gerundetem Ort und merkt sie sich eine Stunde", async () => {
    let now = 0;
    const body = {
      daily: {
        time: ["2026-09-30", "2026-10-01"],
        weather_code: [61, 95],
        temperature_2m_max: [17.6, 21.2],
        temperature_2m_min: [9.4, null],
        precipitation_sum: [4.24, 12],
        precipitation_probability_max: [80, 90],
        wind_speed_10m_max: [22.4, 40]
      }
    };
    const fetchImpl = jest.fn().mockResolvedValue({ ok: true, status: 200, json: async () => body });
    const provider = new OpenMeteoProvider("Europe/Berlin", fetchImpl as unknown as typeof fetch, () => now);

    const days = await provider.forecast({ latitude: 52.5234, longitude: 13.4114 }, ["2026-09-30", "2026-10-01"]);
    now = 30 * 60 * 1000;
    await provider.forecast({ latitude: 52.51, longitude: 13.44 }, ["2026-09-30"]);

    // Ein Tag ohne Tiefstwert faellt weg.
    expect(days).toEqual([{ date: "2026-09-30", temp_max_c: 18, temp_min_c: 9, precipitation_mm: 4.2, precipitation_probability: 80, wind_max_kmh: 22, weather_code: 61 }]);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const url = new URL(String(fetchImpl.mock.calls[0][0]));
    expect([url.searchParams.get("latitude"), url.searchParams.get("longitude"), url.searchParams.get("timezone")]).toEqual(["52.5", "13.4", "Europe/Berlin"]);
    expect(roundLocation({ latitude: 48.137, longitude: 11.575 })).toEqual({ latitude: 48.1, longitude: 11.6 });
  });

  it("meldet Fehler der Quelle", async () => {
    const provider = new OpenMeteoProvider("Europe/Berlin", jest.fn().mockResolvedValue({ ok: false, status: 503 }) as unknown as typeof fetch);
    await expect(provider.forecast({ latitude: 52.5, longitude: 13.4 }, [TODAY])).rejects.toThrow("503");
    const empty = new OpenMeteoProvider("Europe/Berlin", jest.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({}) }) as unknown as typeof fetch);
    await expect(empty.forecast({ latitude: 52.5, longitude: 13.4 }, [TODAY])).rejects.toThrow("keine Tageswerte");
  });
});

describe("Kalender", () => {
  it("macht Tage mit zu wenig freier Zeit zu Ruhetagen und kuerzt die anderen auf die freie Zeit", () => {
    const raw = weekPlan([[weekSession("bike", 60)], [weekSession("bike", 90)], [weekSession("swim", 1500)]]);
    const result = sanitizeWeekV2(raw, athlete(), context({ availability: [{ date: TODAY, minutes: 15 }, { date: "2026-10-01", minutes: 45 }] }));

    expect(result.plan.days[0]).toMatchObject({ focus: "Keine Zeit", sessions: [] });
    expect(result.plan.days[1].sessions[0].minutes).toBeLessThanOrEqual(45);
    expect(result.adjustments).toEqual(
      expect.arrayContaining(["Mittwoch, 30.09.: laut Kalender keine Zeit, als Ruhetag gesetzt", "Donnerstag, 01.10.: Tagesumfang von 90 min auf höchstens 45 min gekürzt (freie Zeit laut Kalender)"])
    );
  });

  it("begrenzt den Tagesplan auf die freie Zeit", () => {
    const raw = dayPlan([session("bike", { steps: [step({ duration_seconds: 3600 })] })]);
    const result = sanitizeDayV2(raw, athlete(), { date: TODAY, availableMinutes: 30 });

    expect(result.plan.sessions[0].duration_minutes).toBeLessThanOrEqual(30);
    expect(result.adjustments.some((line) => line.includes("(freie Zeit laut Kalender)"))).toBe(true);
  });
});

describe("Kraft und Mobilitaet", () => {
  const strength = (minutes = 30) => ({ kind: "strength" as const, minutes, focus: "Rumpf" });
  const mobility = (minutes = 10) => ({ kind: "mobility" as const, minutes, focus: "Hüfte" });

  it("gibt es nur, wenn der Athlet sie will, und so oft er will", () => {
    const raw = weekPlan([[weekSession("swim", 1000)], [], [weekSession("bike", 45)], []]);
    raw.days[0].extras = [strength(), mobility()];
    raw.days[1].extras = [mobility(), mobility()];
    raw.days[2].extras = [strength(60)];
    raw.days[3].extras = [mobility(2)];

    const none = sanitizeWeekV2(raw, athlete(), context());
    const some = sanitizeWeekV2(raw, athlete(), context({ supplements: { strength_per_week: 1, mobility_per_week: 2 } }));

    expect(none.plan.days.every((day) => day.extras.length === 0)).toBe(true);
    expect(some.plan.days.slice(0, 4).map((day) => day.extras.map((extra) => `${extra.kind} ${extra.minutes}`))).toEqual([["strength 30", "mobility 10"], ["mobility 10"], [], []]);
    expect(some.adjustments).toEqual(expect.arrayContaining(["Freitag, 02.10.: Kraft gestrichen (höchstens 1-mal pro Woche)", "Samstag, 03.10.: Mobilität gestrichen (höchstens 2-mal pro Woche)"]));
  });

  it("legt Kraft nicht vor einen harten Tag und nicht in die Woche vor dem Ziel", () => {
    const raw = weekPlan([[weekSession("swim", 1000)], [weekSession("bike", 60, { intensity: "hard", session_type: "intervals" })]]);
    raw.days[0].extras = [strength()];
    const supplements = { strength_per_week: 2, mobility_per_week: 0 };

    const beforeHard = sanitizeWeekV2(raw, athlete(), context({ supplements }));
    const nearGoal = sanitizeWeekV2(weekPlan([[weekSession("swim", 1000)]]), multiSnapshot({ daysUntilGoal: 5 }), context({ supplements }));

    expect(beforeHard.plan.days[0].extras).toEqual([]);
    expect(beforeHard.adjustments).toContain("Mittwoch, 30.09.: kein Krafttraining am Tag vor einer harten Einheit");
    expect(nearGoal.plan.days[0].extras).toEqual([]);
  });

  it("baut im Tagesplan die Uebungen in Bereichen und nur die vorgesehenen Arten", () => {
    const raw = {
      ...dayPlan([session("swim", { steps: [swimStep(300, { name: "Einschwimmen" }), swimStep(400), swimStep(150, { name: "Ausschwimmen" })] })]),
      extras: [
        {
          ...mobility(12),
          exercises: [
            { name: "Hüftbeuger-Dehnung", sets: 9, reps: null, seconds: 600, rest_seconds: 0, cue: "Hüfte dehnen", instructions: "Ausfallschritt." },
            { name: "Kniebeuge", sets: 3, reps: 80, seconds: null, rest_seconds: 900, cue: "", instructions: "Tief." },
            { name: " ", sets: 2, reps: 10, seconds: null, rest_seconds: 30, cue: "x", instructions: "" }
          ]
        },
        { ...strength(), exercises: [{ name: "Plank", sets: 3, reps: null, seconds: 40, rest_seconds: 30, cue: "Halten", instructions: "" }] }
      ]
    };
    const supplements = { strength_per_week: 2, mobility_per_week: 3 };

    const result = sanitizeDayV2(raw, athlete(), { date: TODAY, supplements, plannedExtras: ["mobility"] });

    expect(result.plan.extras).toEqual([
      {
        kind: "mobility",
        minutes: 10,
        focus: "Hüfte",
        exercises: [
          { name: "Hüftbeuger-Dehnung", sets: 5, reps: null, seconds: 180, rest_seconds: 0, cue: "Hüfte dehnen", instructions: "Ausfallschritt." },
          { name: "Kniebeuge", sets: 3, reps: 30, seconds: null, rest_seconds: 180, cue: "Kniebeuge", instructions: "Tief." }
        ]
      }
    ]);
    expect(result.adjustments).toContain("Kraft heute gestrichen (nicht vorgesehen)");
  });
});

describe("Prompts: Triathlon", () => {
  it("nennen Koppeltraining, drinnen, Kraft, Kalender und Wetter in der Woche", () => {
    const message = buildWeekUserMessageV2({
      snapshot: athlete(),
      context: context({
        equipment: ["indoor_trainer"],
        supplements: { strength_per_week: 2, mobility_per_week: 0 },
        availability: [{ date: "2026-10-01", minutes: 60 }],
        weather: [{ ...sunny(TODAY), weather_code: 95 }]
      })
    });

    expect(message).toContain("- Möglich: Radfahren direkt nach Schwimmen; Laufen direkt nach Radfahren (brick true bei der zweiten Einheit des Tages).");
    expect(message).toContain("- Radfahren: drinnen möglich (Rolle, indoor true).");
    expect(message).toContain("- Laufen: nur draußen (kein Laufband angegeben, indoor false).");
    expect(message).toContain("- Kraft (strength): 2-mal pro Woche, je 15 bis 45 min.");
    expect(message).toContain("- Donnerstag 2026-10-01; laut Kalender etwa 60 min frei");
    expect(message).toContain("- Mittwoch 2026-09-30; Wetter 10 bis 20 °C, Gewitter, Wind bis 10 km/h, Gewitter angesagt");
    expect(MULTI_WEEK_SYSTEM_PROMPT).toContain("brick true heißt Koppeltraining");
    expect(MULTI_DAY_SYSTEM_PROMPT).toContain("drei bis acht Übungen");
  });

  it("nennen im Tagesplan die Vorgabe mit Koppeltraining und Kraft", () => {
    const message = buildDayUserMessageV2({
      snapshot: athlete(),
      date: TODAY,
      supplements: { strength_per_week: 1, mobility_per_week: 1 },
      availableMinutes: 90,
      weather: sunny(TODAY),
      dayTarget: {
        sessions: [
          { sport: "bike", session_type: "endurance", intensity: "easy", amount: 60, focus: "Grundlage" },
          { sport: "run", session_type: "endurance", intensity: "easy", amount: 15, focus: "Koppellauf", brick: true }
        ],
        extras: [{ kind: "mobility", minutes: 10, focus: "Hüfte" }]
      }
    });

    expect(message).toContain("- Laufen: Typ endurance, Intensität easy, etwa 15 min, direkt nach der ersten Einheit (Koppeltraining, brick true), Schwerpunkt \"Koppellauf\".");
    expect(message).toContain("- Mobilität (mobility): etwa 10 min, Schwerpunkt \"Hüfte\".");
    expect(message).toContain("- Mobilität (mobility): heute laut Wochenplan, je 5 bis 30 min.");
    expect(message).not.toContain("- Kraft (strength)");
    expect(message).toContain("- Freie Zeit heute laut Kalender: etwa 90 min");
    expect(message).toContain("- Wetter heute: 10 bis 20 °C, klar, Wind bis 10 km/h.");
  });

  it("sagen ohne Wunsch: keine Kraft und Mobilitaet", () => {
    expect(buildWeekUserMessageV2({ snapshot: athlete(), context: context() })).toContain("Kraft und Mobilität: keine (extras leer).");
  });
});

describe("Routen: Ort, Kalender, Kraft", () => {
  function setup(raw: unknown, forecast: jest.Mock) {
    const complete = jest.fn().mockResolvedValue({ raw, model: "m", usage: { inputTokens: 1, outputTokens: 1 } });
    const service = new MultiPlanService({
      generator: { complete },
      store: new MemoryDayPlanStoreV2(),
      budget: new GenerationBudget(100, 100),
      weather: { forecast },
      logger: createLogger(testConfig),
      timezone: "Europe/Berlin",
      now: () => new Date("2026-09-30T10:00:00Z")
    });
    return { app: buildApp({ registerV1Routes: multiRoutes(service) }), complete };
  }
  const auth = { Authorization: `Bearer ${TEST_TOKEN}` };

  it("holt fuer die Woche das Wetter am Ort und nimmt Kalender und Kraft an", async () => {
    const forecast = jest.fn().mockResolvedValue([{ ...sunny(TODAY), weather_code: 95 }]);
    const { app, complete } = setup(weekPlan([[weekSession("bike", 60)]]), forecast);

    const response = await request(app)
      .post("/v1/plan/week")
      .set(auth)
      .send({
        plan_version: 2,
        snapshot: athlete(),
        from_date: TODAY,
        today: TODAY,
        location: { latitude: 52.5, longitude: 13.4 },
        availability: [{ date: "2026-10-01", minutes: 0 }],
        supplements: { strength_per_week: 1, mobility_per_week: 2 },
        equipment: ["indoor_trainer"]
      });

    expect(response.status).toBe(200);
    expect(forecast).toHaveBeenCalledWith({ latitude: 52.5, longitude: 13.4 }, weekDates());
    expect(response.body.plan.days[0].sessions[0].indoor).toBe(true);
    expect(complete.mock.calls[0][1]).toContain("laut Kalender keine Zeit");
  });

  it("plant ohne Wetter weiter, wenn die Quelle ausfaellt, und prueft die neuen Felder", async () => {
    const forecast = jest.fn().mockRejectedValue(new Error("offline"));
    const { app } = setup(dayPlan([session("swim", { steps: [swimStep(300, { name: "Einschwimmen" }), swimStep(400), swimStep(150, { name: "Ausschwimmen" })] })]), forecast);
    const body = { plan_version: 2, snapshot: athlete(), location: { latitude: 52.5, longitude: 13.4 }, available_minutes: 60, supplements: { strength_per_week: 0, mobility_per_week: 1 } };

    const ok = await request(app).post("/v1/plan/today").set(auth).send(body);
    const badLocation = await request(app).post("/v1/plan/today").set(auth).send({ ...body, location: { latitude: 120, longitude: 0 } });
    const badSupplements = await request(app).post("/v1/plan/today").set(auth).send({ ...body, supplements: { strength_per_week: 5, mobility_per_week: 0 } });
    const badDate = await request(app).post("/v1/plan/week").set(auth).send({ plan_version: 2, snapshot: athlete(), from_date: TODAY, today: TODAY, availability: [{ date: "2026-13-01", minutes: 30 }] });

    expect(ok.status).toBe(200);
    expect(ok.body.plan.extras).toEqual([]);
    expect([badLocation.status, badSupplements.status, badDate.status]).toEqual([400, 400, 400]);
    expect(badDate.body.details[0].path).toBe("availability.0.date");
  });
});
