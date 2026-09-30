import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { sanitizePlan } from "../../src/plan/sanity";
import { Snapshot, SnapshotSchema } from "../../src/plan/snapshot";
import { planOfMeters, sum } from "./fixtures";

const dir = path.join(__dirname, "..", "..", "scenarios");
const load = (name: string): Snapshot => SnapshotSchema.parse(JSON.parse(readFileSync(path.join(dir, name), "utf8")));

// Ein bewusst zu ehrgeiziger Claude-Vorschlag: 4,4 km, hart, mit unrealistisch schnellen Zeiten.
const overambitious = () => planOfMeters(4400, { session_type: "intervals", intensity: "hard" });

describe("Szenarien aus M3 (Fixtures fuer npm run eval:scenarios)", () => {
  it("enthaelt genau die fuenf Szenarien, und alle sind gueltige Snapshots", () => {
    const files = readdirSync(dir).filter((file) => file.endsWith(".json")).sort();

    expect(files).toEqual([
      "01-anfaenger.json",
      "02-fortschritt.json",
      "03-trainingspause.json",
      "04-zieldatum-nah.json",
      "05-uebertraining.json"
    ]);
    for (const file of files) expect(() => load(file)).not.toThrow();
  });

  it("1 Anfaenger: hoechstens 1000 m, Zielpace nicht schneller als fuer den Anfaenger realistisch", () => {
    const result = sanitizePlan(overambitious(), load("01-anfaenger.json"));

    expect(sum(result.plan.sets)).toBeLessThanOrEqual(1000);
    // aktuelle Pace 257,1 -> schnellste Vorgabe 154 s/100 m
    const paces = result.plan.sets.flatMap((s) => (s.target_pace_seconds_per_hundred_meters === null ? [] : [s.target_pace_seconds_per_hundred_meters]));
    expect(Math.min(...paces)).toBeGreaterThanOrEqual(154);
  });

  it("2 Fortschritt: gestern hart gewesen, also heute hoechstens moderat, und nur 855 m Wochenspielraum", () => {
    const result = sanitizePlan(overambitious(), load("02-fortschritt.json"));

    expect(result.plan.intensity).toBe("moderate");
    // Wochengrenze 3350 * 1,3 = 4355, schon 3500 gelaufen
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(855);
  });

  it("3 Trainingspause: vorsichtiger Wiedereinstieg, locker und hoechstens 800 m", () => {
    const result = sanitizePlan(overambitious(), load("03-trainingspause.json"));

    expect(result.plan.intensity).toBe("easy");
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(800);
  });

  it("4 Zieldatum nah: darf hart sein (letzte harte Einheit vor 2 Tagen), bleibt aber im Wochenspielraum", () => {
    const result = sanitizePlan(overambitious(), load("04-zieldatum-nah.json"));

    expect(result.plan.intensity).toBe("hard");
    // Wochengrenze 5000 * 1,3 = 6500, schon 5000 gelaufen
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(1500);
  });

  it("5 Uebertraining: ausnahmslos Ruhetag, egal was Claude vorschlaegt", () => {
    const result = sanitizePlan(overambitious(), load("05-uebertraining.json"));

    expect(result.plan.session_type).toBe("rest");
    expect(result.plan.sets).toEqual([]);
    expect(result.plan.total_distance_meters).toBe(0);
  });
});
