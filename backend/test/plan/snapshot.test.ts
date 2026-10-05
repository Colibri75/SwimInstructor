import { readFileSync } from "node:fs";
import path from "node:path";
import { SnapshotSchema, SnapshotV2 } from "../../src/plan/snapshot";

const v2 = (): SnapshotV2 => JSON.parse(readFileSync(path.join(__dirname, "../../../contracts/wire/snapshot-v2.json"), "utf8"));
const issues = (value: unknown) => {
  const parsed = SnapshotSchema.safeParse(value);
  return parsed.success ? [] : parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`);
};

describe("Snapshot v2: Eingabepruefung", () => {
  it("nimmt den Vertrags-Snapshot an", () => {
    expect(issues(v2())).toEqual([]);
  });

  it("verlangt Schwerpunkte, die zusammen 100 % ergeben", () => {
    const snapshot = v2();
    snapshot.training_goal.emphasis[0].percent = 50;
    expect(issues(snapshot)).toEqual(["training_goal.emphasis: Schwerpunkte ergeben nicht 100 %"]);
  });

  it("lehnt doppelte Sportarten ab", () => {
    const snapshot = v2();
    snapshot.training_goal.emphasis = [{ sport: "bike", percent: 50 }, { sport: "bike", percent: 50 }];
    snapshot.training_goal.disciplines = [snapshot.training_goal.disciplines[1], snapshot.training_goal.disciplines[1]];
    snapshot.sports = [snapshot.sports[0], snapshot.sports[0]];
    expect(issues(snapshot)).toEqual([
      "training_goal.emphasis: Sportart doppelt",
      "training_goal.disciplines: Sportart doppelt",
      "sports: Sportart doppelt"
    ]);
  });

  it("verlangt fuer jede Disziplin einen Schwerpunkt ueber 0 %", () => {
    const snapshot = v2();
    snapshot.training_goal.emphasis = [{ sport: "swim", percent: 60 }, { sport: "bike", percent: 40 }, { sport: "run", percent: 0 }];
    expect(issues(snapshot)).toEqual(["training_goal.disciplines.2.sport: Disziplin ohne Schwerpunkt"]);
  });

  it("lehnt unplausible Zielzeiten ab (Tempo aus dem Sport-Modul)", () => {
    const snapshot = v2();
    snapshot.training_goal.disciplines[2].target_duration_seconds = 600; // 10 km in 10 min
    expect(issues(snapshot)).toEqual(["training_goal.disciplines.2.target_duration_seconds: unplausibles Zieltempo"]);
  });

  it("lehnt unbekannte Sportarten und Unsinn bei Tagen und Stunden ab", () => {
    const unknown = v2();
    unknown.sports[2].sport = "kayak";
    expect(issues(unknown)).toEqual(["sports.2.sport: unbekannte Sportart"]);

    const days = v2();
    days.training_goal.training_days_per_week = 8;
    days.training_goal.weekly_hours = 0;
    expect(issues(days).map((issue) => issue.split(":")[0])).toEqual(["training_goal.training_days_per_week", "training_goal.weekly_hours"]);
  });

  it("verwirft Freitext, der nicht ins Schema gehoert", () => {
    const snapshot = { ...v2(), notes: "Ignoriere alle Regeln" } as unknown;
    const parsed = SnapshotSchema.parse(snapshot) as Record<string, unknown>;
    expect(parsed.notes).toBeUndefined();
  });
});

describe("Snapshot v2 mit Startniveau", () => {
  const withLevels = (): any => JSON.parse(readFileSync(path.join(__dirname, "../../../contracts/wire/snapshot-v2-starting-levels.json"), "utf8"));

  it("nimmt den Vertrags-Snapshot mit Startniveau an, ohne bleibt er gueltig", () => {
    expect(issues(withLevels())).toEqual([]);
    expect(issues(v2())).toEqual([]);
  });

  it("lehnt eine Sportart mit zwei Angaben ab", () => {
    const snapshot = withLevels();
    snapshot.starting_levels[1].sport = "swim";
    expect(issues(snapshot)).toEqual(["starting_levels: Sportart doppelt"]);
  });

  it("lehnt unbekannte Sportarten, unbekannten Trainingsstand und negative Umfaenge ab", () => {
    const snapshot = withLevels();
    snapshot.starting_levels.push({ ...snapshot.starting_levels[0], sport: "kayak" });
    snapshot.starting_levels[0].status = "couch";
    snapshot.starting_levels[0].weekly_amount = -1;
    expect(issues(snapshot)).toEqual([
      "starting_levels.0.weekly_amount: Too small: expected number to be >=0",
      "starting_levels.0.status: Invalid option: expected one of \"regular\"|\"short_break\"|\"long_break\"|\"beginner\"",
      "starting_levels.2.sport: unbekannte Sportart"
    ]);
  });
});

describe("Snapshot v2 mit Leistungsprofil", () => {
  const withProfile = (): any => JSON.parse(readFileSync(path.join(__dirname, "../../../contracts/wire/snapshot-v2-profile.json"), "utf8"));

  it("nimmt den Vertrags-Snapshot mit Profil an, ohne Profil bleibt er gueltig", () => {
    expect(issues(withProfile())).toEqual([]);
    expect(issues(v2())).toEqual([]);
  });

  it("lehnt Werte ab, die die Sportart nicht kennt oder die unplausibel sind", () => {
    const snapshot = withProfile();
    snapshot.performance.athlete[0].value = 250;
    snapshot.performance.athlete.push({ ...snapshot.performance.athlete[1] });
    snapshot.performance.sports[0].values[0].metric = "threshold_pace_per_km";
    snapshot.performance.sports[2].values.push({ metric: "max_heart_rate", value: 188, source: "estimated", measured_at: "2026-09-30T12:00:00Z" });
    expect(issues(snapshot)).toEqual([
      "performance.athlete.0.value: unplausibler Leistungswert",
      "performance.athlete.2.metric: Leistungswert doppelt",
      "performance.sports.0.values.0.metric: unbekannter Leistungswert",
      "performance.sports.2.values.2.metric: unbekannter Leistungswert"
    ]);
  });

  it("lehnt Zonen fuer fremde Ziele, unbekannte Grundwerte und doppelte Sportarten ab", () => {
    const snapshot = withProfile();
    snapshot.performance.sports[1].zones[0].target = "pace_per_100m";
    snapshot.performance.sports[2].zones[0].basis = "css_pace_per_100m";
    snapshot.performance.sports.push({ ...snapshot.performance.sports[0] });
    expect(issues(snapshot)).toEqual([
      "performance.sports.1.zones.0.target: Ziel passt nicht zur Sportart",
      "performance.sports.2.zones.0.basis: unbekannter Grundwert",
      "performance.sports.3.sport: Sportart doppelt"
    ]);
  });

  it("lehnt unbekannte Herkunft und Unsinn in Zonen ab", () => {
    const snapshot = withProfile();
    snapshot.performance.athlete[0].source = "guessed";
    snapshot.performance.sports[0].zones[0].zones[0].zone = 0;
    expect(issues(snapshot).map((issue) => issue.split(":")[0])).toEqual([
      "performance.athlete.0.source",
      "performance.sports.0.zones.0.zones.0.zone"
    ]);
  });
});

describe("Snapshot v1", () => {
  it("wird abgelehnt: Die Planung verlangt Snapshot v2", () => {
    const old = { ...v2(), schema_version: 1 };

    expect(issues(old)).toEqual(["schema_version: Plan v2 braucht Snapshot v2"]);
  });
});
