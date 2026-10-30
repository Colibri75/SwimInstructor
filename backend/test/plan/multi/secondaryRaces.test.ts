import { SnapshotSchema, SnapshotV2 } from "../../../src/plan/snapshot";
import { dayLimits } from "../../../src/plan/multi/limits";
import { buildMacroUserMessageV2, buildWeekUserMessageV2, goalSectionV2 } from "../../../src/plan/multi/prompts";
import { secondaryRaceRestriction, secondaryRaceTestReason } from "../../../src/plan/multi/secondaryRaces";
import { scheduleMacroTests } from "../../../src/plan/multi/tests";
import { sanitizeWeekV2 } from "../../../src/plan/multi/weekSanity";
import { macroWeekStarts } from "../../../src/plan/calendar";
import { multiSnapshot, RUNNER, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

type Races = NonNullable<SnapshotV2["training_goal"]["secondary_races"]>;

/** Mittwoch 30.09., Ziel im Juli 2027, dazu Nebenwettkaempfe. */
const withRaces = (races: Races): SnapshotV2 => {
  const base = multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER } });
  return { ...base, training_goal: { ...base.training_goal, secondary_races: races } };
};

const tenK = (date: string, priority: "b" | "c" = "b"): Races[number] => ({ date, priority, disciplines: [{ sport: "run", distance_meters: 10_000 }] });

describe("Nebenwettkaempfe", () => {
  it("nimmt sie im Snapshot nur gueltig an", () => {
    const base = multiSnapshot();
    const parse = (races: unknown) => SnapshotSchema.safeParse({ ...base, training_goal: { ...base.training_goal, secondary_races: races } }).success;
    expect(parse([tenK("2026-10-03"), tenK("2026-11-15", "c")])).toBe(true);
    expect(parse([])).toBe(true);
    expect(parse([tenK("2026-10-03"), tenK("2026-10-03", "c")])).toBe(false);
    expect(parse([tenK("2026-02-30")])).toBe(false);
    expect(parse([{ ...tenK("2026-10-03"), priority: "a" }])).toBe(false);
    expect(parse([{ ...tenK("2026-10-03"), disciplines: [] }])).toBe(false);
    expect(parse([{ ...tenK("2026-10-03"), disciplines: [{ sport: "rudern", distance_meters: 5000 }] }])).toBe(false);
    expect(parse(["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"].map((date) => tenK(date)))).toBe(false);
    // Nicht am Tag des Hauptwettkampfs.
    expect(parse([tenK(base.training_goal.target_date.slice(0, 10))])).toBe(false);
  });

  it("macht den Tag selbst zum Tag ohne Training und bremst die Tage davor und danach", () => {
    const b = withRaces([tenK("2026-10-03")]);
    expect(String(dayLimits(b, "2026-10-03").restReason)).toBe("Nebenwettkampf heute");

    const before = dayLimits(b, TODAY);
    expect(before.restReason).toBeNull();
    expect(before.maxIntensity).toBe("moderate");
    expect(before.intensityReasons.map(String)).toContain("Nebenwettkampf am 03.10.: kurz vorher weniger");
    expect(before.sports.get("run")?.maxAmount).toBeLessThan(dayLimits(withRaces([]), TODAY).sports.get("run")?.maxAmount ?? 0);
    expect(String(before.testBlockedReason)).toBe("kein Test rund um den Nebenwettkampf am 03.10.");

    expect(secondaryRaceRestriction(b, "2026-10-05")?.maxIntensity).toBe("easy");
    expect(secondaryRaceRestriction(b, "2026-10-06")).toBeNull();
    expect(secondaryRaceTestReason(b, "2026-10-05")).not.toBeNull();
    expect(secondaryRaceTestReason(b, "2026-10-06")).toBeNull();
    expect(secondaryRaceRestriction(b, "2026-09-29")).toBeNull();

    // C zaehlt wie eine harte Einheit: nur der Tag davor und danach hoechstens mittel, kein weniger Umfang.
    const c = withRaces([tenK("2026-10-01", "c")]);
    expect(secondaryRaceRestriction(c, TODAY)).toMatchObject({ maxIntensity: "moderate", amountFactor: 1 });
    expect(secondaryRaceRestriction(c, "2026-10-02")?.maxIntensity).toBe("moderate");
    expect(secondaryRaceRestriction(c, "2026-10-03")).toBeNull();
    expect(secondaryRaceTestReason(c, "2026-10-03")).toBeNull();
  });

  it("streicht in den 14 Tagen das Training am Wettkampftag und bremst davor und danach", () => {
    const raw = weekPlan([
      [weekSession("run", 40, { intensity: "hard", session_type: "intervals" })],
      [],
      [weekSession("run", 30)],
      [weekSession("run", 30)],
      [weekSession("run", 40, { intensity: "moderate", session_type: "endurance" })],
      [],
      [weekSession("run", 40, { intensity: "moderate", session_type: "endurance" })]
    ]);
    const result = sanitizeWeekV2(raw, withRaces([tenK("2026-10-03")]), { today: TODAY, dates: weekDates(), unavailable: [], recent: [] });

    expect(result.plan.days[0].sessions[0].intensity).toBe("moderate");
    expect(result.plan.days[3].sessions).toEqual([]);
    expect(result.plan.days[4].sessions[0].intensity).toBe("easy");
    // Ab dem dritten Tag danach bremst der Nebenwettkampf nicht mehr.
    expect(result.adjustments.filter((line) => line.includes("06.10.") && line.includes("Nebenwettkampf"))).toEqual([]);
    expect(result.adjustments).toEqual(expect.arrayContaining([expect.stringContaining("Nebenwettkampf heute")]));
  });

  it("nennt sie in den Prompts und legt keinen Test in eine Woche mit B-Wettkampf", () => {
    const snapshot = withRaces([tenK("2026-10-03"), tenK("2026-11-15", "c")]);
    expect(goalSectionV2(snapshot, TODAY)).toContain(
      "- Nebenwettkämpfe (das Ziel oben bleibt der Hauptwettkampf): 2026-10-03 (B, kurz zuspitzen): Laufen 10,0 km; 2026-11-15 (C, wie eine harte Einheit): Laufen 10,0 km."
    );
    // Mit Zielzeit und im Freiwasser wie beim Ziel.
    const detailed = withRaces([
      { date: "2026-10-03", priority: "b", disciplines: [{ sport: "swim", distance_meters: 1500, open_water: true }, { sport: "run", distance_meters: 10_000, target_duration_seconds: 3000 }] }
    ]);
    expect(SnapshotSchema.safeParse(detailed).success).toBe(true);
    expect(goalSectionV2(detailed, TODAY)).toContain("2026-10-03 (B, kurz zuspitzen): Schwimmen 1500 m im ");
    expect(goalSectionV2(detailed, TODAY)).toMatch(/Laufen 10,0 km in [^;.]+\./);
    const week = buildWeekUserMessageV2({ snapshot, context: { today: TODAY, dates: weekDates(), unavailable: [], recent: [] } });
    expect(week).toContain("- 2026-10-03: 2026-10-03 (B, kurz zuspitzen): Laufen 10,0 km. Keine Einheiten, der Wettkampf ist die Einheit.");
    expect(week).toContain('- 2026-10-04: Erholung nach dem Nebenwettkampf am 03.10., Intensität höchstens "easy", kein Leistungstest.');

    const goalDay = snapshot.training_goal.target_date.slice(0, 10);
    const weeks = macroWeekStarts(TODAY, goalDay);
    expect(buildMacroUserMessageV2(snapshot, { today: TODAY, goalDay, weeks })).toContain("- 2026-09-28: base, noch");
    expect(buildMacroUserMessageV2(snapshot, { today: TODAY, goalDay, weeks })).toMatch(/- 2026-09-28: base, noch [^\n]*; Nebenwettkampf B am 2026-10-03/);

    const plain = scheduleMacroTests(withRaces([]), weeks.map((week_start) => ({ week_start, phase: "base", deload: false, amounts: new Map([["run", 30]]) })), TODAY);
    const raced = scheduleMacroTests(snapshot, weeks.map((week_start) => ({ week_start, phase: "base", deload: false, amounts: new Map([["run", 30]]) })), TODAY);
    expect(plain.get("2026-09-28")?.length).toBeGreaterThan(0);
    expect(raced.get("2026-09-28")).toEqual([]);
  });
});
