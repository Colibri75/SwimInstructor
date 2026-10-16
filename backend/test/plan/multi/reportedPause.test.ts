import { SnapshotSchema, SnapshotV2 } from "../../../src/plan/snapshot";
import { afterPauseRestriction, dayLimits, reportedPauseReason } from "../../../src/plan/multi/limits";
import { buildDayUserMessageV2, buildWeekUserMessageV2 } from "../../../src/plan/multi/prompts";
import { sanitizeWeekV2 } from "../../../src/plan/multi/weekSanity";
import { multiSnapshot, RUNNER, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

/** Mittwoch 30.09. mit einer gemeldeten Pause. */
const paused = (pause: SnapshotV2["reported_pause"]): SnapshotV2 => ({
  ...multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER } }),
  reported_pause: pause
});

describe("Gemeldete Pause", () => {
  it("macht die Tage der Pause zu Ruhetagen, auch eine noch laufende", () => {
    const vacation = paused({ kind: "vacation", from: "2026-10-01", to: "2026-10-02" });
    expect(reportedPauseReason(vacation, "2026-09-30")).toBeNull();
    expect(String(reportedPauseReason(vacation, "2026-10-01"))).toBe("gemeldete Pause (Urlaub)");
    expect(reportedPauseReason(vacation, "2026-10-03")).toBeNull();

    const ongoing = paused({ kind: "sick", from: "2026-09-29" });
    expect(String(dayLimits(ongoing, TODAY).restReason)).toBe("gemeldete Pause (krank)");
    expect(dayLimits(ongoing, "2026-10-20").restReason).not.toBeNull();
  });

  it("laesst nach Krankheit oder Verletzung so viele Tage nur locker zu, wie die Pause dauerte, hoechstens 7", () => {
    const sick = paused({ kind: "sick", from: "2026-09-27", to: "2026-09-29" });
    expect(afterPauseRestriction(sick, "2026-09-29")).toBeNull();
    expect(afterPauseRestriction(sick, "2026-10-02")?.until).toBe("2026-10-02");
    expect(afterPauseRestriction(sick, "2026-10-03")).toBeNull();

    const long = paused({ kind: "injury", from: "2026-09-01", to: "2026-09-29" });
    expect(afterPauseRestriction(long, "2026-10-06")?.until).toBe("2026-10-06");
    expect(afterPauseRestriction(long, "2026-10-07")).toBeNull();

    expect(afterPauseRestriction(paused({ kind: "vacation", from: "2026-09-20", to: "2026-09-29" }), TODAY)).toBeNull();
    expect(afterPauseRestriction(paused({ kind: "sick", from: "2026-09-29" }), TODAY)).toBeNull();
  });

  it("bremst den Tag danach auf locker und ohne Leistungstest", () => {
    const limits = dayLimits(paused({ kind: "sick", from: "2026-09-27", to: "2026-09-29" }), TODAY);
    expect(limits.restReason).toBeNull();
    expect(limits.maxIntensity).toBe("easy");
    expect(limits.intensityReasons.map(String)).toContain("nach gemeldeter Pause (krank) bis 02.10. nur locker");
    expect(String(limits.testBlockedReason)).toBe("nach gemeldeter Pause (krank) bis 02.10. nur locker");
  });

  it("streicht in den 14 Tagen die Einheiten der Pause und macht die Tage danach locker", () => {
    const raw = weekPlan([
      [weekSession("run", 30)],
      [weekSession("run", 40, { intensity: "hard", session_type: "intervals" })],
      [weekSession("run", 30)],
      [weekSession("run", 40, { intensity: "moderate", session_type: "endurance" })]
    ]);
    // Krank am 30.09., wieder gesund ab 01.10.: der 01.10. ist locker, der 03.10. wieder frei.
    const snapshot = paused({ kind: "sick", from: "2026-09-30", to: "2026-09-30" });

    const result = sanitizeWeekV2(raw, snapshot, { today: TODAY, dates: weekDates(), unavailable: [], recent: [] });

    expect(result.plan.days[0].sessions).toEqual([]);
    expect(result.plan.days[1].sessions[0].intensity).toBe("easy");
    expect(result.adjustments).toEqual(
      expect.arrayContaining([expect.stringContaining("Ruhetag erzwungen (gemeldete Pause (krank))"), expect.stringContaining("nach gemeldeter Pause (krank) bis 01.10. nur locker")])
    );
    expect(result.plan.days[3].sessions[0].intensity).toBe("moderate");
  });

  it("nennt die Pause in den Prompts", () => {
    const week = buildWeekUserMessageV2({
      snapshot: paused({ kind: "sick", from: "2026-09-28", to: "2026-10-01" }),
      context: { today: TODAY, dates: weekDates(), unavailable: [], recent: [] }
    });
    expect(week).toContain("- gemeldete Pause (krank): 2026-09-30, 2026-10-01 sind Ruhetage");
    expect(week).toContain("- nach gemeldeter Pause (krank) bis 05.10. nur locker: 2026-10-02, 2026-10-03, 2026-10-04, 2026-10-05 nur lockere Einheiten");

    const day = buildDayUserMessageV2({ snapshot: paused({ kind: "injury", from: "2026-09-25", to: "2026-09-29" }), date: TODAY, recent: [] });
    expect(day).toContain('Intensität höchstens "easy" (nach gemeldeter Pause (verletzt) bis 04.10. nur locker)');
  });

  it("nimmt die Pause im Snapshot nur mit gueltigen Tagen an", () => {
    const base = multiSnapshot();
    expect(SnapshotSchema.safeParse({ ...base, reported_pause: { kind: "sick", from: "2026-09-28" } }).success).toBe(true);
    expect(SnapshotSchema.safeParse({ ...base, reported_pause: { kind: "sick", from: "2026-09-28", to: "2026-09-27" } }).success).toBe(false);
    expect(SnapshotSchema.safeParse({ ...base, reported_pause: { kind: "sick", from: "2026-02-30" } }).success).toBe(false);
    expect(SnapshotSchema.safeParse({ ...base, reported_pause: { kind: "bored", from: "2026-09-28" } }).success).toBe(false);
  });
});
