import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { DayPlanV2 } from "../../../src/plan/multi/daySanity";
import { asRawDayPlan, DAY_PLAN_V2_FILE, FileDayPlanStoreV2, MemoryDayPlanStoreV2, StoredDayV2 } from "../../../src/plan/multi/store";
import { step, swimStep } from "./fixtures";

const plan: DayPlanV2 = {
  rationale: "Lockerer Tag mit Bezug zum Ziel, 3500 m in 7 Tagen.",
  coach_notes: ["Viel trinken."],
  sessions: [
    {
      sport: "swim",
      session_type: "endurance",
      intensity: "easy",
      focus: "Grundlage",
      test: null,
      amount: 850,
      unit: "meters",
      distance_meters: 850,
      duration_minutes: 17,
      steps: [swimStep(300, { name: "Einschwimmen", equipment: ["pull_buoy"] }), swimStep(400), swimStep(150, { name: "Ausschwimmen" })]
    },
    {
      sport: "run",
      session_type: "test",
      intensity: "easy",
      focus: "Einstiegstest locker",
      test: { id: "entry_easy_25min", display_name: "Einstiegstest locker", maximal_effort: false, produces: ["threshold_pace_per_km"] },
      amount: 35,
      unit: "minutes",
      distance_meters: 5900,
      duration_minutes: 35,
      steps: [step({ name: "Einlaufen", duration_seconds: 600 }), step({ duration_seconds: 1500 })]
    }
  ]
};

const record: StoredDayV2 = {
  date: "2026-09-30",
  hash: "abc123",
  generatedAt: "2026-09-30T10:00:00.000Z",
  model: "claude-opus-5-5",
  plan,
  adjustments: ["Schwimmen: Umfang gekürzt"]
};

describe("FileDayPlanStoreV2", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), "multi-store-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("liefert null, solange noch nie ein Plan gespeichert wurde", async () => {
    expect(await new FileDayPlanStoreV2(dir).latest()).toBeNull();
  });

  it("speichert einen Plan und liest ihn unveraendert wieder, auch nach einem Neustart (neue Instanz)", async () => {
    await new FileDayPlanStoreV2(dir).save(record);

    expect(await new FileDayPlanStoreV2(dir).latest()).toEqual(record);
  });

  it("ueberschreibt den frueheren Plan und hinterlaesst keine temporaeren Dateien", async () => {
    const store = new FileDayPlanStoreV2(dir);

    await store.save(record);
    await store.save({ ...record, date: "2026-10-01" });

    expect((await store.latest())?.date).toBe("2026-10-01");
    expect(await readdir(dir)).toEqual([DAY_PLAN_V2_FILE]);
  });

  it("legt eine eigene Datei neben dem Plan v1 an und das Datenverzeichnis, wenn es fehlt", async () => {
    const nested = path.join(dir, "a", "b");

    await new FileDayPlanStoreV2(nested).save(record);

    expect(DAY_PLAN_V2_FILE).toBe("latest-plan-v2.json");
    expect(await readdir(nested)).toEqual(["latest-plan-v2.json"]);
  });

  it("behandelt eine beschaedigte Datei als 'kein Plan'", async () => {
    await writeFile(path.join(dir, DAY_PLAN_V2_FILE), "{kaputt", "utf8");

    expect(await new FileDayPlanStoreV2(dir).latest()).toBeNull();
  });

  it.each([
    ["unpassender Inhalt", { date: "gestern" }],
    ["Datum ohne Kalenderformat", { ...record, date: "30.09.2026" }],
    ["Zeitpunkt kein ISO-Datum", { ...record, generatedAt: "heute" }],
    ["unbekannte Intensitaet", { ...record, plan: { ...plan, sessions: [{ ...plan.sessions[0], intensity: "brutal" }] } }],
    ["Schritt ohne Pflichtfeld", { ...record, plan: { ...plan, sessions: [{ ...plan.sessions[0], steps: [{ name: "Hauptteil" }] }] } }]
  ])("behandelt eine Datei mit ungueltigem Schema als 'kein Plan': %s", async (_name, content) => {
    await writeFile(path.join(dir, DAY_PLAN_V2_FILE), JSON.stringify(content), "utf8");

    expect(await new FileDayPlanStoreV2(dir).latest()).toBeNull();
  });

  it("meldet andere Lesefehler (hier: Pfad ist eine Datei statt Ordner) statt sie zu verschlucken", async () => {
    const asFile = path.join(dir, "datei");
    await writeFile(asFile, "x", "utf8");

    await expect(new FileDayPlanStoreV2(asFile).latest()).rejects.toMatchObject({ code: "ENOTDIR" });
  });
});

describe("MemoryDayPlanStoreV2", () => {
  it("haelt den zuletzt gespeicherten Plan", async () => {
    const store = new MemoryDayPlanStoreV2();
    expect(await store.latest()).toBeNull();

    await store.save(record);
    await store.save({ ...record, hash: "neu" });

    expect(await store.latest()).toEqual({ ...record, hash: "neu" });
  });

  it("startet mit einem vorgegebenen Plan", async () => {
    expect(await new MemoryDayPlanStoreV2(record).latest()).toBe(record);
  });
});

describe("asRawDayPlan", () => {
  it("bringt einen gespeicherten Plan in die Form, die Claude liefert (test wird test_id)", () => {
    const raw = asRawDayPlan(plan);

    expect(raw.rationale).toBe(plan.rationale);
    expect(raw.coach_notes).toEqual(plan.coach_notes);
    expect(raw.sessions).toHaveLength(2);
    expect(raw.sessions[0]).toEqual({
      sport: "swim",
      session_type: "endurance",
      intensity: "easy",
      focus: "Grundlage",
      test_id: null,
      steps: plan.sessions[0].steps
    });
    expect(raw.sessions[1].test_id).toBe("entry_easy_25min");
    // Berechnete Felder gehoeren nicht zu Claudes Ausgabe.
    expect(raw.sessions[1]).not.toHaveProperty("test");
    expect(raw.sessions[1]).not.toHaveProperty("amount");
    expect(raw.sessions[1]).not.toHaveProperty("duration_minutes");
  });

  it("kopiert die Schritte samt Equipment, statt sie mit dem gespeicherten Plan zu teilen", () => {
    const raw = asRawDayPlan(plan);

    expect(raw.sessions[0].steps[0]).not.toBe(plan.sessions[0].steps[0]);
    expect(raw.sessions[0].steps[0].equipment).not.toBe(plan.sessions[0].steps[0].equipment);

    raw.sessions[0].steps[0].equipment.push("fins");
    raw.sessions[0].steps[0].repetitions = 9;

    expect(plan.sessions[0].steps[0].equipment).toEqual(["pull_buoy"]);
    expect(plan.sessions[0].steps[0].repetitions).toBe(1);
  });
});
