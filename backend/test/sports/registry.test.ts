import { SportRegistry, SportRegistryError, SPORTS } from "../../src/sports/registry";
import { SportDefinition } from "../../src/sports/types";

const stub = (patch: Partial<SportDefinition> = {}): SportDefinition => ({
  id: "yoga",
  displayName: "Yoga",
  measures: ["duration"],
  targets: ["perceived_effort"],
  goalSpeed: { minMetersPerSecond: 0.1, maxMetersPerSecond: 1 },
  loadFactor: 1,
  performanceMetrics: [],
  performanceTests: [],
  ...patch
});

const lactate = { id: "lactate_power", displayName: "Laktatleistung", unit: "W", min: 50, max: 500 };
const rampTest = { id: "ramp", displayName: "Rampe", produces: ["lactate_power"], maximalEffort: true, durationMinutes: 20 };

function problemOf(sports: SportDefinition[]): string | undefined {
  try {
    new SportRegistry(sports);
    return undefined;
  } catch (error) {
    return error instanceof SportRegistryError ? error.problem : "other";
  }
}

describe("SportRegistry", () => {
  it("kennt Schwimmen, Rad und Laufen in dieser Reihenfolge", () => {
    expect(SPORTS.ids).toEqual(["swim", "bike", "run"]);
    expect(SPORTS.get("run")?.displayName).toBe("Laufen");
    expect(SPORTS.get("kayak")).toBeUndefined();
  });

  it("lehnt unvollstaendige oder doppelte Sportarten ab", () => {
    expect(problemOf([stub({ id: "Yoga-1" })])).toBe("malformed_id");
    expect(problemOf([stub({ id: "y" })])).toBe("malformed_id");
    expect(problemOf([stub(), stub()])).toBe("duplicate");
    expect(problemOf([stub({ displayName: "  " })])).toBe("missing_display_name");
    expect(problemOf([stub({ measures: [] })])).toBe("no_measures");
    expect(problemOf([stub({ measures: ["laps" as never] })])).toBe("unknown_measure");
    expect(problemOf([stub({ targets: ["watts" as never] })])).toBe("unknown_target");
    expect(problemOf([stub({ goalSpeed: { minMetersPerSecond: 0, maxMetersPerSecond: 1 } })])).toBe("invalid_goal_speed");
    expect(problemOf([stub({ goalSpeed: { minMetersPerSecond: 2, maxMetersPerSecond: 1 } })])).toBe("invalid_goal_speed");
    expect(problemOf([stub({ goalSpeed: { minMetersPerSecond: 1, maxMetersPerSecond: Infinity } })])).toBe("invalid_goal_speed");
    expect(problemOf([stub({ goalSpeed: { minMetersPerSecond: Number.NaN, maxMetersPerSecond: 1 } })])).toBe("invalid_goal_speed");
    expect(problemOf([stub()])).toBeUndefined();
  });

  it.each([0, -1, Infinity, Number.NaN])("lehnt den Lastfaktor %p ab", (loadFactor) => {
    expect(problemOf([stub({ loadFactor })])).toBe("invalid_load_factor");
  });

  it.each([
    ["Kennung", { ...lactate, id: "Lactate" }],
    ["fuer alle Sportarten", { ...lactate, id: "max_heart_rate" }],
    ["ohne Namen", { ...lactate, displayName: " " }],
    ["ohne Einheit", { ...lactate, unit: "" }],
    ["Bereich ab 0", { ...lactate, min: 0 }],
    ["Bereich verkehrt", { ...lactate, min: 600 }],
    ["Bereich offen", { ...lactate, max: Infinity }]
  ])("lehnt ungueltige Leistungswerte ab: %s", (_why, metric) => {
    expect(problemOf([stub({ performanceMetrics: [metric] })])).toBe("invalid_performance_metric");
  });

  it("lehnt doppelte Leistungswerte ab", () => {
    expect(problemOf([stub({ performanceMetrics: [lactate, lactate] })])).toBe("invalid_performance_metric");
  });

  it.each([
    ["Kennung", [{ ...rampTest, id: "Ramp Test" }]],
    ["doppelt", [rampTest, rampTest]],
    ["ohne Namen", [{ ...rampTest, displayName: "" }]],
    ["ohne Ergebnis", [{ ...rampTest, produces: [] }]],
    ["fremdes Ergebnis", [{ ...rampTest, produces: ["max_heart_rate"] }]],
    ["ohne Dauer", [{ ...rampTest, durationMinutes: 0 }]],
    ["krumme Dauer", [{ ...rampTest, durationMinutes: 2.5 }]]
  ])("lehnt ungueltige Tests ab: %s", (_why, tests) => {
    expect(problemOf([stub({ performanceMetrics: [lactate], performanceTests: tests })])).toBe("invalid_performance_test");
  });

  it("nimmt eine Sportart mit eigenem Wert und Test an", () => {
    expect(problemOf([stub({ performanceMetrics: [lactate], performanceTests: [rampTest] })])).toBeUndefined();
  });

  it("findet Leistungswerte je Sportart und fuer alle Sportarten", () => {
    expect(SPORTS.metric(undefined, "max_heart_rate")?.unit).toBe("bpm");
    expect(SPORTS.metric("run", "max_heart_rate")).toBeUndefined();
    expect(SPORTS.metric("swim", "css_pace_per_100m")?.unit).toBe("s/100m");
    expect(SPORTS.metric("run", "css_pace_per_100m")).toBeUndefined();
    expect(SPORTS.metric("bike", "threshold_heart_rate")?.displayName).toBe("Schwellenpuls");
    expect(SPORTS.metric("kayak", "threshold_heart_rate")).toBeUndefined();
    expect(SPORTS.metric(undefined, "vo2max")).toBeUndefined();
  });

  it("meldet den Fehler lesbar", () => {
    expect(() => new SportRegistry([stub(), stub()])).toThrow("Sportart yoga: duplicate");
  });

  it("prueft, ob ein Ziel ein plausibles Tempo hat", () => {
    expect(SPORTS.plausibleGoal("swim", 3800, 3600)).toBe(true);
    expect(SPORTS.plausibleGoal("swim", 3800, 60)).toBe(false);
    expect(SPORTS.plausibleGoal("run", 10_000, 600)).toBe(false);
    expect(SPORTS.plausibleGoal("run", 10_000, 3000)).toBe(true);
    expect(SPORTS.plausibleGoal("bike", 40_000, 4 * 3600)).toBe(true);
    expect(SPORTS.plausibleGoal("bike", 40_000, 0)).toBe(false);
    expect(SPORTS.plausibleGoal("kayak", 1000, 600)).toBe(false);
  });

  it("prueft Mass und Ziel eines Schritts", () => {
    expect(SPORTS.supports("run", "duration", "pace_per_km")).toBe(true);
    expect(SPORTS.supports("run", "distance")).toBe(true);
    expect(SPORTS.supports("run", "distance", "pace_per_100m")).toBe(false);
    expect(SPORTS.supports("run", "repetitions")).toBe(false);
    expect(SPORTS.supports("kayak", "distance")).toBe(false);
  });
});
