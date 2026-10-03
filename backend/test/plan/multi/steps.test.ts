import { planningContext } from "../../../src/plan/multi/sports";
import { checkTarget, normalizeStep, stepsAmount, trimSteps } from "../../../src/plan/multi/steps";
import { SessionStep } from "../../../src/sports/types";
import { SPORTS } from "../../../src/sports/registry";
import { rowingTestSport as rowing } from "../../sports/rowingTestModule";
import { multiSnapshot, step, swimStep } from "./fixtures";

const swim = SPORTS.get("swim")!;
const bike = SPORTS.get("bike")!;
const run = SPORTS.get("run")!;

const normalized = (raw: Parameters<typeof normalizeStep>[0], sport = swim, speed = 1, available?: ReadonlySet<string>): SessionStep => {
  const result = normalizeStep(raw, sport, speed, available).step;
  if (result === null) throw new Error("Schritt fehlt");
  return result;
};

describe("normalizeStep", () => {
  it("rechnet ein Mass, in dem die Sportart nicht plant, mit dem Tempo um", () => {
    // Schwimmen plant nur nach Strecke: 10 min bei 1 m/s sind 600 m.
    expect(normalized(step({ duration_seconds: 600 }), swim, 1)).toMatchObject({ measure: "distance", distance_meters: 600, duration_seconds: null });
  });

  it("nimmt das andere Feld, wenn das genannte fehlt, und verwirft Schritte ohne beides", () => {
    expect(normalized(step({ measure: "distance", distance_meters: null, duration_seconds: 300 }), run)).toMatchObject({ measure: "duration", duration_seconds: 300 });
    expect(normalized(step({ measure: "duration", duration_seconds: 0, distance_meters: 1000 }), run)).toMatchObject({ measure: "distance", distance_meters: 1000 });
    expect(normalizeStep(step({ measure: "distance", distance_meters: null, duration_seconds: null }), run, 3).step).toBeNull();
    expect(normalizeStep(step({ measure: "duration", distance_meters: 0, duration_seconds: null }), run, 3).step).toBeNull();
  });

  it("bringt Strecken auf das Raster und passt die Wiederholungen an", () => {
    expect(normalized(swimStep(25, { repetitions: 4 }))).toMatchObject({ distance_meters: 50, repetitions: 2 });
    expect(normalized(swimStep(75, { repetitions: 2 }))).toMatchObject({ distance_meters: 100, repetitions: 2 });
    expect(normalized(swimStep(9000))).toMatchObject({ distance_meters: 3800, repetitions: 2 });
    expect(normalized(swimStep(10, { repetitions: 1 }))).toMatchObject({ distance_meters: 50, repetitions: 1 });
  });

  it("rundet Dauern auf 5 Sekunden und haelt sie im Bereich der Sportart", () => {
    expect(normalized(step({ duration_seconds: 62 }), run).duration_seconds).toBe(60);
    expect(normalized(step({ duration_seconds: 3 }), run).duration_seconds).toBe(10);
    expect(normalized(step({ duration_seconds: 99_999 }), bike).duration_seconds).toBe(6 * 3600);
  });

  it("begrenzt Wiederholungen, Pausen und Texte und setzt einen Namen", () => {
    const result = normalized(swimStep(100, { repetitions: 500, rest_seconds: 5000, name: "  ", cue: "x".repeat(80), instructions: "y".repeat(900) }));

    expect(result).toMatchObject({ repetitions: 100, rest_seconds: 900, name: "Schritt" });
    expect(result.cue).toHaveLength(40);
    expect(result.instructions).toHaveLength(600);
  });

  it("laesst nur bekanntes Equipment zu, das der Athlet hat, und meldet das entfernte", () => {
    const raw = swimStep(100, { equipment: ["fins", "fins", "paddles", "laser_sword", "pull_buoy", "snorkel", "kickboard"] });

    expect(normalizeStep(raw, swim, 1, new Set(["fins", "pull_buoy"]))).toMatchObject({
      step: { equipment: ["fins", "pull_buoy"] },
      removedEquipment: ["paddles", "snorkel", "kickboard"]
    });
    expect(normalized(raw).equipment).toEqual(["fins", "paddles", "pull_buoy"]);
    expect(normalized(step({ equipment: ["fins"] }), run).equipment).toEqual([]);
  });
});

describe("checkTarget", () => {
  const snapshot = multiSnapshot();
  const swimContext = planningContext(snapshot, swim);
  const bikeContext = planningContext(snapshot, bike);
  const runContext = planningContext(snapshot, run);
  const at = (target_type: SessionStep["target_type"], target_value: number | null, measure: "distance" | "duration" = "duration"): SessionStep =>
    normalized(step({ target_type, target_value, measure, distance_meters: measure === "distance" ? 400 : null }), measure === "distance" ? swim : run);

  it("setzt einen Wert ausserhalb des Bereichs auf die Grenze", () => {
    // CSS 1:45: nicht schneller als 88 % (92 s).
    expect(checkTarget(at("pace_per_100m", 60, "distance"), swim, swimContext, "hard")).toMatchObject({ step: { target_value: 92 }, changed: true });
    expect(checkTarget(at("pace_per_100m", 120, "distance"), swim, swimContext, "hard")).toMatchObject({ step: { target_value: 120 }, changed: false });
  });

  it("begrenzt Zone und Anstrengung nach der Intensitaet der Einheit", () => {
    expect(checkTarget(at("heart_rate_zone", 4), run, runContext, "easy").step.target_value).toBe(2);
    expect(checkTarget(at("heart_rate_zone", 4), run, runContext, "moderate").step.target_value).toBe(3);
    expect(checkTarget(at("heart_rate_zone", 5), run, runContext, "hard").step.target_value).toBe(5);
    expect(checkTarget(at("perceived_effort", 9), run, runContext, "easy").step.target_value).toBe(4);
    expect(checkTarget(at("perceived_effort", 9), run, runContext, "moderate").step.target_value).toBe(6);
  });

  it("macht aus einem Ziel, das fuer den Athleten nicht geht, die gefuehlte Anstrengung", () => {
    // Puls ohne Zonen: Zone 4 entspricht Anstrengung 7, bei moderate hoechstens 6.
    const noProfile = planningContext(multiSnapshot({ performance: null }), run);
    expect(checkTarget(at("heart_rate_zone", 4), run, noProfile, "moderate")).toMatchObject({ step: { target_type: "perceived_effort", target_value: 6 }, changed: true });
    expect(checkTarget(at("heart_rate_zone", 1), run, noProfile, "hard").step.target_value).toBe(2);
    // Watt ohne FTP: nach der Intensitaet.
    expect(checkTarget(at("power", 250), bike, bikeContext, "hard").step).toMatchObject({ target_type: "perceived_effort", target_value: 8 });
    // Ein Ziel, das die Sportart nicht kennt (Puls beim Schwimmen).
    expect(checkTarget(at("heart_rate_zone", 2, "distance"), swim, swimContext, "easy").step).toMatchObject({ target_type: "perceived_effort", target_value: 3 });
  });

  it("laesst das Ziel weg, wenn die Sportart keine gefuehlte Anstrengung kennt", () => {
    const context = planningContext(multiSnapshot(), rowing);

    expect(checkTarget(at("power", 200), rowing, context, "easy")).toMatchObject({ step: { target_type: null, target_value: null }, changed: true });
  });

  it("raeumt halbe Ziele auf", () => {
    expect(checkTarget(at("pace_per_km", null), run, runContext, "easy")).toMatchObject({ step: { target_type: null, target_value: null }, changed: true });
    expect(checkTarget(at(null, 5), run, runContext, "easy").changed).toBe(true);
    expect(checkTarget(at(null, null), run, runContext, "easy").changed).toBe(false);
  });

  it("rundet ein Tempoziel in km/h auf eine Nachkommastelle", () => {
    const sport = { ...bike, targets: [...bike.targets], planning: { ...bike.planning, targetRange: () => ({ min: 10, max: 50 }) } };

    expect(checkTarget(at("speed", 27.46), sport, bikeContext, "easy").step.target_value).toBe(27.5);
  });
});

describe("stepsAmount und trimSteps", () => {
  const warmUp = normalized(swimStep(400));
  const main = normalized(swimStep(100, { repetitions: 10, rest_seconds: 20 }));
  const coolDown = normalized(swimStep(200));

  it("zaehlt Meter ohne Pausen, Minuten mit Pausen", () => {
    expect(stepsAmount([warmUp, main, coolDown], swim, 1)).toBe(1600);
    const runSteps = [normalized(step({ duration_seconds: 300, repetitions: 4, rest_seconds: 60 }), run)];
    expect(stepsAmount(runSteps, run, 3)).toBe(24);
  });

  it("kuerzt zuerst die Wiederholungen des groessten Schritts", () => {
    const trimmed = trimSteps([warmUp, main, coolDown], swim, 1, 1200);

    expect(trimmed.map((item) => [item.repetitions, item.distance_meters])).toEqual([[1, 400], [6, 100], [1, 200]]);
  });

  it("kuerzt die Laenge, wenn nur eine Wiederholung bleibt, und streicht zu kurze Schritte", () => {
    const long = normalized(step({ duration_seconds: 3600 }), run);
    const short = normalized(step({ duration_seconds: 600 }), run);

    expect(trimSteps([long], run, 3, 45)[0].duration_seconds).toBe(2700);
    expect(trimSteps([short], run, 3, 0)).toEqual([]);
    expect(trimSteps([normalized(swimStep(400))], swim, 1, 20)).toEqual([]);
    expect(trimSteps([normalized(swimStep(400))], swim, 1, 330)[0].distance_meters).toBe(300);
  });

  it("kuerzt nach Minuten inklusive Pausen", () => {
    // 500 m bei 0,8 m/s plus 756 s Pause sind 24 min: auf 23 min heisst 450 m.
    const withRest = normalized(swimStep(500, { rest_seconds: 756 }));
    const trimmed = trimSteps([withRest], swim, 0.8, 23, "minutes");

    expect(trimmed[0].distance_meters).toBe(450);
  });

  it("rechnet bei Minuten eine Strecke ueber das Tempo um", () => {
    const meters = normalized(step({ measure: "distance", distance_meters: 6000, duration_seconds: null }), run);
    const trimmed = trimSteps([meters], run, 2.5, 30);

    expect(stepsAmount(trimmed, run, 2.5)).toBeLessThanOrEqual(30);
    expect(trimmed[0].distance_meters).toBe(4500);
  });
});
