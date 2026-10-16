import { mondayOf } from "../../../src/plan/calendar";
import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { lapGrid, poolClosed } from "../../../src/plan/multi/profile";
import { buildDayUserMessageV2, buildMacroUserMessageV2, buildWeekUserMessageV2, MULTI_DAY_SYSTEM_PROMPT } from "../../../src/plan/multi/prompts";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { SnapshotSchema } from "../../../src/plan/snapshot";
import { SPORTS } from "../../../src/sports/registry";
import { contractSnapshot, dayPlan, multiSnapshot, session, swimStep, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

// TODAY (2026-09-30) ist ein Mittwoch.
const WEDNESDAY = 3;
const rested = { load: { days_since_last_hard_session: 5 }, sports: { swim: { meters_last_seven_days: 1000 }, bike: { minutes_last_seven_days: 30 } } };
const swim = SPORTS.get("swim")!;
const swimSession = (meters: number[]) => session("swim", { steps: meters.map((m) => swimStep(m)) });
const context = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent: [], ...patch });

const FULL_PROFILE = {
  age: 52,
  training_years: 1,
  injuries: [
    { area: "knee" as const, status: "current" as const },
    { area: "achilles" as const, status: "recurring" as const }
  ],
  sports: [
    { sport: "swim", skills: ["breaststroke", "freestyle"], lap_length_meters: 25, pool_weekdays: [1, 3, 5] },
    { sport: "run", long_session_weekday: 7 }
  ],
  life_stress: "high" as const,
  shift_work: true,
  intensity_preference: "easy" as const
};

describe("Athletenprofil im Snapshot", () => {
  const withProfile = (profile: unknown) => ({ ...JSON.parse(JSON.stringify(contractSnapshot())), athlete_profile: profile });

  it("nimmt ein vollstaendiges Profil an", () => {
    expect(SnapshotSchema.safeParse(withProfile(FULL_PROFILE)).success).toBe(true);
  });

  it.each([
    ["unbekannte Faehigkeit", { sports: [{ sport: "swim", skills: ["crawl"] }] }],
    ["Faehigkeit einer Sportart ohne Faehigkeiten", { sports: [{ sport: "run", skills: ["freestyle"] }] }],
    ["Bahnlaenge, die die Sportart nicht kennt", { sports: [{ sport: "swim", lap_length_meters: 33 }] }],
    ["Bahn bei einer Sportart ohne Bahn", { sports: [{ sport: "bike", pool_weekdays: [1] }] }],
    ["Wochentag doppelt", { sports: [{ sport: "swim", pool_weekdays: [1, 1] }] }],
    ["Sportart doppelt", { sports: [{ sport: "run" }, { sport: "run" }] }],
    ["Koerperstelle doppelt", { injuries: [{ area: "knee", status: "past" }, { area: "knee", status: "current" }] }],
    ["Alter unplausibel", { age: 4 }],
    ["Freitext", { age: 40, notes: "x" }]
  ])("lehnt ab oder verwirft: %s", (name, profile) => {
    const parsed = SnapshotSchema.safeParse(withProfile(profile));
    if (name === "Freitext") {
      // Unbekannte Felder verwirft das Schema, statt sie in den Prompt zu lassen.
      expect(parsed.success && parsed.data.athlete_profile).toEqual({ age: 40 });
    } else {
      expect(parsed.success).toBe(false);
    }
  });
});

describe("Bahn: Raster und Tage", () => {
  it("erlaubt im 25-m-Becken 25er und laesst das 50-m-Raster sonst stehen", () => {
    const lap = (meters: number) => multiSnapshot({ athleteProfile: { sports: [{ sport: "swim", lap_length_meters: meters }] } });
    expect(lapGrid(lap(25), swim, false)).toEqual({ step: 25, min: 25 });
    expect(lapGrid(lap(25), swim, true)).toBeUndefined();
    expect(lapGrid(lap(50), swim, false)).toBeUndefined();
    expect(lapGrid(multiSnapshot(), swim, false)).toBeUndefined();
  });

  it("kennt die Tage ohne Bahn", () => {
    const snapshot = multiSnapshot({ athleteProfile: { sports: [{ sport: "swim", pool_weekdays: [1, 5] }] } });
    expect(poolClosed(snapshot, swim, TODAY)).toBe(true);
    expect(poolClosed(snapshot, swim, "2026-10-02")).toBe(false);
    expect(poolClosed(snapshot, SPORTS.get("run")!, TODAY)).toBe(false);
    expect(poolClosed(multiSnapshot(), swim, TODAY)).toBe(false);
  });

  it("Tagesplan: 75 m bleiben im 25-m-Becken, sonst werden sie zu 100 m", () => {
    const raw = dayPlan([swimSession([200, 75, 200])]);
    const short = sanitizeDayV2(raw, multiSnapshot({ ...rested, athleteProfile: { sports: [{ sport: "swim", lap_length_meters: 25 }] } }), { date: TODAY });
    const usual = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY });
    expect(short.plan.sessions[0].steps.map((item) => item.distance_meters)).toEqual([200, 75, 200]);
    expect(usual.plan.sessions[0].steps.map((item) => item.distance_meters)).toEqual([200, 100, 200]);
  });

  it("Tagesplan: streicht Schwimmen im Becken an einem Tag ohne Bahn, Freiwasser bleibt", () => {
    const snapshot = multiSnapshot({ ...rested, athleteProfile: { sports: [{ sport: "swim", pool_weekdays: [1, 5] }] } });
    const pool = sanitizeDayV2(dayPlan([swimSession([400, 800])]), snapshot, { date: TODAY });
    expect(pool.plan.sessions).toEqual([]);
    expect(pool.adjustments.join(" ")).toContain("heute kein Becken laut deinen Angaben");

    const lake = sanitizeDayV2(dayPlan([session("swim", { open_water: true, steps: [swimStep(1000)] })]), snapshot, { date: TODAY, equipment: ["open_water"] });
    expect(lake.plan.sessions.map((item) => item.sport)).toEqual(["swim"]);
  });

  it("Wochenplan: streicht Schwimmen im Becken nur an den Tagen ohne Bahn", () => {
    const snapshot = multiSnapshot({ ...rested, athleteProfile: { sports: [{ sport: "swim", pool_weekdays: [5] }] } });
    // Mittwoch (heute) und Freitag.
    const raw = weekPlan([[weekSession("swim", 1500)], [], [weekSession("swim", 1500)], [], [], [], []]);
    const result = sanitizeWeekV2(raw, snapshot, context());
    expect(result.plan.days.map((day) => day.sessions.map((item) => item.sport))).toEqual([[], [], ["swim"], [], [], [], []]);
    expect(result.adjustments.join(" ")).toContain("kein Becken an diesem Tag laut deinen Angaben");
  });
});

describe("Abschnitt Über den Athleten", () => {
  const snapshot = multiSnapshot({ ...rested, athleteProfile: FULL_PROFILE });

  it("steht in Tag, Woche und Gesamtplan, mit allen Angaben in Worten", () => {
    const day = buildDayUserMessageV2({ snapshot, date: TODAY });
    const week = buildWeekUserMessageV2({ snapshot, context: context() });
    const macro = buildMacroUserMessageV2(snapshot, { today: TODAY, goalDay: "2027-07-04", weeks: [mondayOf(TODAY)] });
    for (const message of [day, week, macro]) {
      expect(message).toContain("Über den Athleten (eigene Angaben, siehe Leitplanke 13):");
      expect(message).toContain("- 52 Jahre alt, seit 1 Jahr im Ausdauersport.");
      expect(message).toContain("- Verletzungen: Knie (gerade aktuell), Achillessehne (kommt immer wieder).");
      expect(message).toContain(
        "- Schwimmen: kann Kraul, Brust; kann nicht: Rückenkraul, Schmetterling, Rollwende. Becken 25 m (Strecken als Vielfache von 25 m erlaubt). Becken nur Montag, Mittwoch, Freitag (an den anderen Tagen nur Freiwasser, wenn erlaubt, sonst keine Einheit Schwimmen)."
      );
      expect(message).toContain("- Laufen: lange Einheit am liebsten Sonntag.");
      expect(message).toContain("- Alltag: hohe Belastung durch Beruf oder Familie, Schichtarbeit.");
      expect(message).toContain("- Intensität: lieber locker");
    }
    expect(day).toContain("Vielfache von 25 m, 25 bis");
  });

  it("nennt einen Tag ohne Bahn in den Grenzen fuer heute", () => {
    const closed = multiSnapshot({ ...rested, athleteProfile: { sports: [{ sport: "swim", pool_weekdays: [WEDNESDAY + 1] }] } });
    expect(buildDayUserMessageV2({ snapshot: closed, date: TODAY })).toContain("- Heute kein Becken (laut Athlet): Schwimmen nur im Freiwasser (open_water true), wenn erlaubt, sonst nicht.");
  });

  it("fehlt ohne Angaben, und die Leitplanke erklaert die Angaben", () => {
    expect(buildDayUserMessageV2({ snapshot: multiSnapshot(rested), date: TODAY })).not.toContain("Über den Athleten");
    expect(MULTI_DAY_SYSTEM_PROMPT).toContain("13. Unter \"Über den Athleten\"");
  });
});
