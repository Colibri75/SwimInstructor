import { SportRegistry, SportRegistryError, SPORTS } from "../../src/sports/registry";
import { SportDefinition } from "../../src/sports/types";

const stub = (patch: Partial<SportDefinition> = {}): SportDefinition => ({
  id: "yoga",
  displayName: "Yoga",
  measures: ["duration"],
  targets: ["perceived_effort"],
  goalSpeed: { minMetersPerSecond: 0.1, maxMetersPerSecond: 1 },
  ...patch
});

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
