import { SportRegistry, SPORTS } from "../../src/sports/registry";
import { rowingTestSport } from "./rowingTestModule";

/**
 * Pruefungen, die jede Sportart bestehen muss. Jeder Umbauschritt haengt hier seine neuen Anforderungen an
 * (Prompt-Regeln, Sicherheitsregeln, Lastfaktor); sie gelten dann automatisch fuer jede Sportart. Gibt es Rudern schon
 * als echtes Modul, laeuft dieses statt der Test-Sportart durch die Pruefungen.
 */
const allSports = SPORTS.get(rowingTestSport.id) === undefined ? [...SPORTS.sports, rowingTestSport] : [...SPORTS.sports];
/** Die echten Sportarten ausser einem echten Rudern: Gegen sie muss sich die Test-Sportart unterscheiden. */
const otherRealSports = SPORTS.sports.filter((sport) => sport.id !== rowingTestSport.id);

describe.each(allSports.map((sport) => [sport.id, sport] as const))("Sportart %s", (_id, sport) => {
  it("laesst sich zusammen mit allen anderen anmelden und wiederfinden", () => {
    const registry = new SportRegistry(allSports);
    expect(registry.get(sport.id)).toBe(sport);
  });

  it("hat mindestens ein Ziel, sonst kann kein Schritt eine Intensitaet vorgeben", () => {
    expect(sport.targets.length).toBeGreaterThan(0);
  });

  it("laesst sich mit jedem eigenen Mass ohne Ziel und mit jedem eigenen Ziel planen", () => {
    const registry = new SportRegistry(allSports);
    for (const measure of sport.measures) {
      expect(registry.supports(sport.id, measure)).toBe(true);
      for (const target of sport.targets) expect(registry.supports(sport.id, measure, target)).toBe(true);
    }
  });

  it("hat ein Zieltempo-Fenster, in dem typische Wettkampfziele liegen", () => {
    const { minMetersPerSecond: min, maxMetersPerSecond: max } = sport.goalSpeed;
    expect(min).toBeGreaterThan(0);
    expect(max).toBeGreaterThan(min * 2);
    const registry = new SportRegistry(allSports);
    // Eine Stunde mit dem mittleren Tempo des Fensters ist immer ein plausibles Ziel.
    expect(registry.plausibleGoal(sport.id, ((min + max) / 2) * 3600, 3600)).toBe(true);
  });

  it("hat einen Lastfaktor ueber 0", () => {
    expect(sport.loadFactor).toBeGreaterThan(0);
  });

  it("hat mindestens einen Leistungstest, und jeder misst Werte der eigenen Sportart", () => {
    expect(sport.performanceTests.length).toBeGreaterThan(0);
    const own = sport.performanceMetrics.map((metric) => metric.id);
    for (const test of sport.performanceTests) {
      for (const metric of test.produces) expect(own).toContain(metric);
      expect(test.durationMinutes).toBeGreaterThan(0);
    }
    const registry = new SportRegistry(allSports);
    for (const metric of sport.performanceMetrics) expect(registry.metric(sport.id, metric.id)).toBe(metric);
  });

  it("nennt Masse und Ziele nur einmal", () => {
    expect(new Set(sport.measures).size).toBe(sport.measures.length);
    expect(new Set(sport.targets).size).toBe(sport.targets.length);
  });
});

it("die Test-Sportart hat ein eigenes Leistungsprofil", () => {
  expect(rowingTestSport.performanceMetrics.map((metric) => metric.id)).toContain("time_2000m");
  expect(otherRealSports.some((sport) => sport.performanceMetrics.some((metric) => metric.id === "time_2000m"))).toBe(false);
});

it("die Test-Sportart hat wirklich eigene Logik (Schlagzahl kennt keine echte Sportart)", () => {
  expect(rowingTestSport.targets).toContain("stroke_rate");
  expect(otherRealSports.some((sport) => sport.targets.includes("stroke_rate"))).toBe(false);
});
