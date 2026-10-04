import { EMPTY_STATE } from "../../src/plan/multi/sports";
import { stepsTotals } from "../../src/plan/multi/tests";
import { rowing } from "../../src/sports/modules/rowing";
import { SPORTS } from "../../src/sports/registry";

/** Die eigene Logik des Ruderns; die allgemeinen Pruefungen laufen fuer jede Sportart in conformance.test.ts und modules.test.ts. */
describe("Rudern", () => {
  const range = rowing.planning.targetRange;

  it("ist angemeldet und plant in Minuten", () => {
    expect(SPORTS.get("rowing")).toBe(rowing);
    expect(rowing.planning.limitUnit).toBe("minutes");
  });

  it("erlaubt Schlagzahl 16 bis 40 und Pulszonen nur mit Zonen aus der App", () => {
    expect(range("stroke_rate", { state: EMPTY_STATE })).toEqual({ min: 16, max: 40 });
    expect(range("heart_rate_zone", { state: EMPTY_STATE })).toBeNull();
    expect(range("heart_rate_zone", { state: EMPTY_STATE, performance: { values: {}, zoneTargets: ["heart_rate_zone"] } })).toEqual({ min: 1, max: 5 });
  });

  it("hat einen 2000-m-Test von knapp einer halben Stunde mit Ein- und Ausrudern", () => {
    const steps = rowing.planning.testSessions.time_trial_2000m ?? [];
    const totals = stepsTotals(rowing, steps, rowing.planning.typicalSpeedMetersPerSecond);
    expect(steps.map((step) => step.name)).toEqual(["Einrudern", "Steigerung", "Test 2000 m", "Ausrudern"]);
    expect(totals.amount).toBeGreaterThanOrEqual(25);
    expect(totals.amount).toBeLessThanOrEqual(30);
  });
});
