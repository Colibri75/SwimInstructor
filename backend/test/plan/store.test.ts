import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { FilePlanStore, MemoryPlanStore, StoredPlan } from "../../src/plan/store";
import { goodPlan } from "./fixtures";

const record: StoredPlan = {
  date: "2026-09-30",
  snapshotHash: "abc123",
  generatedAt: "2026-09-30T10:00:00.000Z",
  model: "claude-opus-5-5",
  plan: goodPlan,
  adjustments: ["Umfang gekürzt"]
};

describe("FilePlanStore", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), "swim-store-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("liefert null, solange noch nie ein Plan gespeichert wurde", async () => {
    expect(await new FilePlanStore(dir).latest()).toBeNull();
  });

  it("speichert einen Plan und liest ihn unveraendert wieder", async () => {
    const store = new FilePlanStore(dir);

    await store.save(record);

    expect(await store.latest()).toEqual(record);
  });

  it("ueberschreibt den frueheren Plan und ueberlebt einen Neustart (neue Instanz)", async () => {
    await new FilePlanStore(dir).save(record);
    await new FilePlanStore(dir).save({ ...record, date: "2026-10-01" });

    expect((await new FilePlanStore(dir).latest())?.date).toBe("2026-10-01");
  });

  it("legt das Datenverzeichnis an, wenn es fehlt", async () => {
    const nested = path.join(dir, "a", "b");

    await new FilePlanStore(nested).save(record);

    expect(await readdir(nested)).toEqual(["latest-plan.json"]);
  });

  it("hinterlaesst keine temporaeren Dateien", async () => {
    await new FilePlanStore(dir).save(record);

    expect(await readdir(dir)).toEqual(["latest-plan.json"]);
  });

  it("liest einen Plan aus der Zeit vor dem Equipment (ohne equipment-Feld) mit leerer Liste", async () => {
    const old = {
      ...record,
      plan: { ...goodPlan, sets: goodPlan.sets.map(({ equipment: _equipment, cue: _cue, ...rest }) => rest) }
    };
    await writeFile(path.join(dir, "latest-plan.json"), JSON.stringify(old), "utf8");

    const loaded = await new FilePlanStore(dir).latest();

    expect(loaded).not.toBeNull();
    expect(loaded?.plan.sets.map((s) => s.equipment)).toEqual([[], [], []]);
    // Auch die Kurzbeschreibung fuer die Uhr gab es damals noch nicht.
    expect(loaded?.plan.sets.map((s) => s.cue)).toEqual(["", "", ""]);
    expect(loaded?.plan.sets[1].name).toBe("Hauptsatz");
  });

  it("behaelt gespeichertes Equipment und verwirft ein unbekanntes Hilfsmittel samt Plan", async () => {
    const withGear = { ...record, plan: { ...goodPlan, sets: [{ ...goodPlan.sets[0], equipment: ["pull_buoy", "paddles"] }] } };
    await writeFile(path.join(dir, "latest-plan.json"), JSON.stringify(withGear), "utf8");
    expect((await new FilePlanStore(dir).latest())?.plan.sets[0].equipment).toEqual(["pull_buoy", "paddles"]);

    const unknown = { ...record, plan: { ...goodPlan, sets: [{ ...goodPlan.sets[0], equipment: ["jetpack"] }] } };
    await writeFile(path.join(dir, "latest-plan.json"), JSON.stringify(unknown), "utf8");
    expect(await new FilePlanStore(dir).latest()).toBeNull();
  });

  it("behandelt eine beschaedigte Datei als 'kein Plan'", async () => {
    await writeFile(path.join(dir, "latest-plan.json"), "{kaputt", "utf8");

    expect(await new FilePlanStore(dir).latest()).toBeNull();
  });

  it("behandelt eine Datei mit unpassendem Inhalt als 'kein Plan'", async () => {
    await writeFile(path.join(dir, "latest-plan.json"), JSON.stringify({ date: "gestern" }), "utf8");

    expect(await new FilePlanStore(dir).latest()).toBeNull();
  });

  it("meldet andere Lesefehler (hier: Pfad ist eine Datei statt Ordner) statt sie zu verschlucken", async () => {
    const asFile = path.join(dir, "datei");
    await writeFile(asFile, "x", "utf8");

    await expect(new FilePlanStore(asFile).latest()).rejects.toThrow();
  });
});

describe("MemoryPlanStore", () => {
  it("haelt den zuletzt gespeicherten Plan", async () => {
    const store = new MemoryPlanStore();
    expect(await store.latest()).toBeNull();

    await store.save(record);

    expect(await store.latest()).toEqual(record);
  });
});
