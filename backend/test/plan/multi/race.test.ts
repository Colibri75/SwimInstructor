import request from "supertest";
import { GenerationBudget } from "../../../src/plan/budget";
import { buildRaceUserMessage, raceBlockedReason, RACE_SYSTEM_PROMPT, sanitizeRace } from "../../../src/plan/multi/race";
import { multiRoutes } from "../../../src/plan/multi/routes";
import { MultiPlanService } from "../../../src/plan/multi/service";
import { MemoryDayPlanStoreV2 } from "../../../src/plan/multi/store";
import { createLogger } from "../../../src/logger";
import { buildApp, TEST_TOKEN, testConfig } from "../../helpers";
import { contractSnapshot, multiSnapshot } from "./fixtures";
import { olympicRaceRaw } from "./raceFixtures";

const snapshot = () => contractSnapshot();
const hotDay = { date: "2027-07-04", temp_max_c: 32, temp_min_c: 20, precipitation_mm: 0, precipitation_probability: 0, wind_max_kmh: 10, weather_code: 0 };

describe("Wettkampftag: Sicherheitsschicht", () => {
  it("laesst einen stimmigen Plan unveraendert und entfernt die Verpflegung beim Schwimmen", () => {
    const result = sanitizeRace(olympicRaceRaw(), snapshot());

    expect(result.blocked).toBeNull();
    expect(result.plan.disciplines.map((discipline) => [discipline.sport, discipline.distance_meters, discipline.target_minutes])).toEqual([
      ["swim", 1500, 30],
      ["bike", 40000, 80],
      ["run", 10000, 58]
    ]);
    expect(result.plan.total_minutes).toBe(168);
    expect(result.plan.nutrition.during.map((fuel) => fuel.sport)).toEqual(["bike", "run"]);
    expect(result.plan.transitions.map((transition) => `${transition.after_sport}>${transition.before_sport}`)).toEqual(["swim>bike", "bike>run"]);
    expect(result.adjustments).toEqual([]);
  });

  it("haelt die Verpflegung in den Grenzen nach Dauer und Wetter", () => {
    const raw = olympicRaceRaw();
    raw.nutrition.during[1] = { sport: "bike", carbs_g_per_hour: 120, fluid_ml_per_hour: 1500, sodium_mg_per_hour: 2000, notes: "Viel." };
    raw.nutrition.during[0] = { sport: "swim", carbs_g_per_hour: 20, fluid_ml_per_hour: 100, sodium_mg_per_hour: 0, notes: "?" };

    const normal = sanitizeRace(raw, snapshot());
    const hot = sanitizeRace(raw, snapshot(), { weather: hotDay });

    expect(normal.plan.nutrition.during[0]).toMatchObject({ sport: "bike", carbs_g_per_hour: 90, fluid_ml_per_hour: 800, sodium_mg_per_hour: 1000 });
    expect(hot.plan.nutrition.during[0].fluid_ml_per_hour).toBe(1000);
    expect(normal.adjustments).toEqual(["Schwimmen: keine Verpflegung während der Disziplin", "Verpflegung auf höchstens 90 g Kohlenhydrate, 800 ml Flüssigkeit und 1000 mg Natrium pro Stunde begrenzt"]);
  });

  it("erlaubt bei kurzen Wettkaempfen weniger Kohlenhydrate", () => {
    const sprint = multiSnapshot({ goal: { disciplines: [{ sport: "run", distance_meters: 10000, target_duration_seconds: 3000 }], emphasis: [{ sport: "run", percent: 100 }] } });
    const raw = olympicRaceRaw();
    raw.disciplines = [{ sport: "run", target_minutes: 50, pacing: [], notes: "" }];
    raw.nutrition.during = [{ sport: "run", carbs_g_per_hour: 60, fluid_ml_per_hour: 300, sodium_mg_per_hour: 0, notes: "" }];

    const result = sanitizeRace(raw, sprint);

    expect(result.plan.nutrition.during[0].carbs_g_per_hour).toBe(30);
    expect(result.plan.transitions).toEqual([]);
  });

  it("ergaenzt fehlende Disziplinen, entfernt fremde und ersetzt unplausible Zielzeiten", () => {
    const raw = olympicRaceRaw();
    raw.disciplines = [
      { ...raw.disciplines[2] },
      { sport: "bike", target_minutes: 10, pacing: [], notes: "" },
      { sport: "kayak", target_minutes: 30, pacing: [], notes: "" }
    ];

    const result = sanitizeRace(raw, snapshot());

    expect(result.plan.disciplines.map((discipline) => `${discipline.sport} ${discipline.target_minutes}`)).toEqual(["swim 30", "bike 80", "run 58"]);
    expect(result.adjustments).toEqual([
      "Schwimmen: fehlte im Plan, mit geschätzter Zeit ergänzt",
      "Radfahren: Zielzeit 10 min unplausibel, 80 min angenommen",
      "Disziplinen ohne Bezug zum Ziel entfernt (kayak)"
    ]);
  });

  it("haelt Pacing-Ziele im Bereich der Sportart und streicht fremde Ziele", () => {
    const raw = olympicRaceRaw();
    raw.disciplines[2].pacing = [
      { segment: "Alles", target_type: "pace_per_km", target_value: 60, cue: "Vollgas", instructions: "" },
      { segment: "Rest", target_type: "power", target_value: 300, cue: "Watt", instructions: "" }
    ];

    const result = sanitizeRace(raw, snapshot());
    const pacing = result.plan.disciplines[2].pacing;

    expect(pacing[0].target_value).toBeGreaterThan(60);
    expect(pacing[1]).toMatchObject({ target_type: null, target_value: null });
    expect(result.adjustments).toContain("Pacing-Ziele an die Grenzen für dich angepasst");
  });

  it("sortiert den Ablauf und laesst Eintraege ausserhalb des Tages weg", () => {
    const raw = olympicRaceRaw();
    raw.timeline = [
      { minutes_from_start: 30, title: "Wechsel", details: "" },
      { minutes_from_start: -2000, title: "Anreise", details: "" },
      { minutes_from_start: -60, title: "Aufwärmen", details: "" },
      { minutes_from_start: 10, title: " ", details: "" }
    ];

    expect(sanitizeRace(raw, snapshot()).plan.timeline.map((entry) => entry.title)).toEqual(["Aufwärmen", "Wechsel"]);
  });

  it("blockt bei einem Fitnessziel und ohne Ueberblick", () => {
    const fitness = multiSnapshot({ goal: { kind: "fitness" } as never });
    expect(raceBlockedReason(fitness)).toMatch(/keinen Wettkampf/);
    expect(sanitizeRace(olympicRaceRaw(), fitness).blocked).toMatch(/keinen Wettkampf/);
    expect(sanitizeRace({ ...olympicRaceRaw(), overview: " " }, snapshot()).blocked).toBe("Überblick fehlt");
  });
});

describe("Wettkampftag: Prompt", () => {
  it("nennt Disziplinen, Zielzeiten, Pacing-Bereiche, Verpflegung, Wetter und Notizen", () => {
    const message = buildRaceUserMessage({ snapshot: snapshot(), today: "2027-06-25", startTime: "09:30", weather: hotDay, notes: "Gels nur mit Wasser", bodyWeightKg: 72.4, performance: "Leistungswerte: …" });

    expect(message).toContain("Schreibe den Plan für den Wettkampftag am Sonntag, 2027-07-04 (in 9 Tagen).");
    expect(message).toContain("Start: 09:30.");
    expect(message).toMatch(/- Schwimmen \(sport "swim"\): 1500 m, Zielzeit 30 min; Pacing-Ziele: .*kein Essen und Trinken möglich\./);
    expect(message).toContain("- Laufen (sport \"run\"): 10000 m, ohne Zielzeit, geschätzt etwa 60 min");
    expect(message).toContain("Zusammen etwa 170 min: Kohlenhydrate höchstens 90 g pro Stunde.");
    expect(message).toContain("Wetter am Wettkampftag (Vorhersage): 20 bis 32 °C, klar, Wind bis 10 km/h, heiß.");
    expect(message).toContain("Körpergewicht: 72 kg.");
    expect(message).toContain('"Gels nur mit Wasser"');
    expect(RACE_SYSTEM_PROMPT).toContain("nichts Neues am Wettkampftag");
  });
});

describe("Route /v1/plan/race", () => {
  function setup(forecast = jest.fn().mockResolvedValue([hotDay])) {
    const complete = jest.fn().mockResolvedValue({ raw: olympicRaceRaw(), model: "claude-opus-5-5", usage: { inputTokens: 10, outputTokens: 20 } });
    const service = new MultiPlanService({
      generator: { complete },
      store: new MemoryDayPlanStoreV2(),
      budget: new GenerationBudget(100, 100),
      weather: { forecast },
      logger: createLogger(testConfig),
      timezone: "Europe/Berlin",
      now: () => new Date("2027-06-25T10:00:00Z")
    });
    return { app: buildApp({ registerV1Routes: multiRoutes(service) }), complete, forecast };
  }
  const auth = { Authorization: `Bearer ${TEST_TOKEN}` };
  const body = (extra: Record<string, unknown> = {}) => ({ plan_version: 2, snapshot: snapshot(), today: "2027-06-25", ...extra });

  it("liefert den Plan mit Wetter, wenn der Tag in der Vorhersage liegt", async () => {
    const { app, complete, forecast } = setup();

    const response = await request(app).post("/v1/plan/race").set(auth).send(body({ location: { latitude: 52.5, longitude: 13.4 }, start_time: "09:30" }));

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ plan_version: 2, race_day: "2027-07-04", weather: hotDay });
    expect(forecast).toHaveBeenCalledWith({ latitude: 52.5, longitude: 13.4 }, ["2027-07-04"]);
    expect(complete.mock.calls[0][3]).toEqual({ macro: true });
  });

  it("fragt kein Wetter, wenn der Tag zu weit weg ist", async () => {
    const { app, forecast } = setup();

    const response = await request(app).post("/v1/plan/race").set(auth).send(body({ today: "2027-05-01", location: { latitude: 52.5, longitude: 13.4 } }));

    expect(response.status).toBe(200);
    expect(response.body.weather).toBeUndefined();
    expect(forecast).not.toHaveBeenCalled();
  });

  it("prueft die Anfrage", async () => {
    const { app } = setup();
    const fitness = { ...snapshot(), training_goal: { ...snapshot().training_goal, kind: "fitness", disciplines: [] } };

    const badTime = await request(app).post("/v1/plan/race").set(auth).send(body({ start_time: "25:00" }));
    const badGoal = await request(app).post("/v1/plan/race").set(auth).send(body({ snapshot: fitness }));
    const noToken = await request(app).post("/v1/plan/race").send(body());

    expect(badTime.status).toBe(400);
    expect(badGoal.status).toBe(400);
    expect(badGoal.body.details[0].path).toBe("snapshot.training_goal");
    expect(noToken.status).toBe(401);
  });
});
