import { dayLimits, dayMinutesCap, goalDayOf, hardOn, lower, multiPhase, sportLimits, taperFactors, taperWeeks, testBlackoutReason, weeksToGoal } from "../../../src/plan/multi/limits";
import { amountToMeters, amountToMinutes, disciplineSeconds, emphasisOf, floorAmount, formatAmount, isPlanned, performanceFor, plannedSports, raceAmount, raceSeconds, roundAmount, sportName, stateOf, trainingSpeed, unitLabel } from "../../../src/plan/multi/sports";
import { SPORTS } from "../../../src/sports/registry";
import { multiSnapshot, RUNNER, TODAY } from "./fixtures";

const swim = SPORTS.get("swim")!;
const bike = SPORTS.get("bike")!;
const run = SPORTS.get("run")!;

describe("Bausteine je Sportart", () => {
  it("plant nur Sportarten mit Schwerpunkt, in der Reihenfolge der Registry", () => {
    const snapshot = multiSnapshot({ goal: { disciplines: [{ sport: "run", distance_meters: 10_000 }], emphasis: [{ sport: "run", percent: 70 }, { sport: "swim", percent: 30 }, { sport: "bike", percent: 0 }] } });

    expect(plannedSports(snapshot).map((sport) => sport.id)).toEqual(["swim", "run"]);
    expect(isPlanned(snapshot, "bike")).toBe(false);
    expect(isPlanned(snapshot, "rowing")).toBe(false);
    expect(emphasisOf(snapshot, "run")).toBe(70);
    expect(emphasisOf(snapshot, "rowing")).toBe(0);
  });

  it("nimmt fuer eine Sportart ohne Eintrag leere Werte und das typische Tempo", () => {
    const snapshot = multiSnapshot();
    snapshot.sports = snapshot.sports.filter((state) => state.sport !== "run");

    expect(stateOf(snapshot, "run").longest_session_minutes).toBe(0);
    expect(trainingSpeed(run, stateOf(snapshot, "run"))).toBe(run.planning.typicalSpeedMetersPerSecond);
  });

  it("rechnet das Tempo aus dem Verlauf und verwirft unplausible Werte", () => {
    expect(trainingSpeed(swim, { ...stateOf(multiSnapshot(), "swim") })).toBeCloseTo(3350 / (67 * 60));
    expect(trainingSpeed(swim, { ...stateOf(multiSnapshot(), "swim"), average_weekly_meters: 3_000_000 })).toBe(swim.planning.typicalSpeedMetersPerSecond);
  });

  it("rechnet zwischen Strecke und Dauer um, rundet auf das Raster und beschriftet", () => {
    expect(amountToMinutes(swim, 1600, 0.8)).toBeCloseTo(1600 / 0.8 / 60);
    expect(amountToMinutes(bike, 60, 7)).toBe(60);
    expect(amountToMeters(swim, 1600, 0.8)).toBe(1600);
    expect(amountToMeters(run, 30, 3)).toBe(5400);
    expect(floorAmount(swim, 1449)).toBe(1400);
    expect(floorAmount(run, -3)).toBe(0);
    expect(roundAmount(swim, 1449)).toBe(1450);
    expect(unitLabel(swim)).toBe("m");
    expect(formatAmount(run, 29.6)).toBe("30 min");
    expect(sportName("bike")).toBe("Radfahren");
    expect(sportName("rowing")).toBe("rowing");
  });

  it("schaetzt die Dauer des Wettkampfs ohne Zielzeit aus dem typischen Tempo", () => {
    const snapshot = multiSnapshot();

    expect(disciplineSeconds({ sport: "run", distance_meters: 10_000 })).toBeCloseTo(10_000 / 2.8);
    expect(disciplineSeconds({ sport: "rowing", distance_meters: 2000 })).toBe(0);
    expect(raceSeconds(snapshot)).toBeCloseTo(1800 + 4800 + 10_000 / 2.8);
    expect(raceAmount(snapshot, swim)).toBe(1500);
    expect(raceAmount(snapshot, bike)).toBe(80);
    expect(raceAmount(multiSnapshot({ goal: { disciplines: [{ sport: "swim", distance_meters: 1500 }] } }), run)).toBe(0);
  });

  it("legt Werte fuer alle Sportarten und die eigenen zusammen, die eigenen gehen vor", () => {
    const snapshot = multiSnapshot();
    const performance = performanceFor(snapshot, "run");

    expect(performance?.values.max_heart_rate.value).toBe(188);
    expect(performance?.values.threshold_pace_per_km.source).toBe("estimated");
    expect(performance?.zoneTargets).toEqual(["heart_rate_zone", "pace_per_km"]);
    expect(performanceFor(multiSnapshot({ performance: null }), "run")).toBeUndefined();
    expect(performanceFor(multiSnapshot({ performance: { athlete: [], sports: [] } }), "run")).toEqual({ values: {}, zoneTargets: [] });
  });
});

describe("sportLimits", () => {
  it("leitet Einheit und Woche aus der laengsten Einheit und dem Schnitt ab", () => {
    const limits = sportLimits(multiSnapshot(), swim);

    expect(limits.pause).toBe(false);
    expect(limits.sessionCap).toBe(2500);
    expect(limits.weeklyCap).toBe(4350);
    expect(limits.lastSeven).toBe(3500);
  });

  it("haelt die Einheit unter der absoluten Grenze und nie unter der kleinsten Grenze", () => {
    expect(sportLimits(multiSnapshot({ sports: { swim: { longest_session_meters: 9000 } } }), swim).sessionCap).toBe(4500);
    expect(sportLimits(multiSnapshot({ sports: { swim: { longest_session_meters: 100, average_weekly_meters: 0 } } }), swim)).toMatchObject({ sessionCap: 1000, weeklyCap: 1500 });
  });

  it("laesst nach einer Pause oder ohne Verlauf nur kurz und wenig zu", () => {
    const never = sportLimits(multiSnapshot(), run);
    const pause = sportLimits(multiSnapshot({ sports: { run: { ...RUNNER, days_since_last_session: 30 } } }), run);
    const active = sportLimits(multiSnapshot({ sports: { run: RUNNER } }), run);

    expect(never).toMatchObject({ pause: true, sessionCap: 20, weeklyCap: 60 });
    expect(pause).toMatchObject({ pause: true, sessionCap: 20, weeklyCap: 60 });
    expect(active).toMatchObject({ pause: false, sessionCap: 65, weeklyCap: 205 });
  });
});

describe("dayLimits", () => {
  it("erzwingt bei Uebertrainingsrisiko einen Ruhetag und keinen Test", () => {
    const today = dayLimits(multiSnapshot({ flags: ["overreaching_risk"] }), TODAY);

    expect(today.restReason).toContain("Übertrainingsrisiko");
    expect(today.testBlockedReason).toBe(today.restReason);
  });

  it("halbiert bei schlechter Erholung Umfang und Tagesminuten und erlaubt nur locker", () => {
    const good = dayLimits(multiSnapshot({ load: { days_since_last_hard_session: 5 } }), TODAY);
    const poor = dayLimits(multiSnapshot({ recovery: { status: "poor" }, load: { days_since_last_hard_session: 5 } }), TODAY);
    const flagged = dayLimits(multiSnapshot({ flags: ["recovery_poor"], load: { days_since_last_hard_session: 5 } }), TODAY);

    expect(good.maxIntensity).toBe("hard");
    expect(good.maxMinutes).toBe(225);
    expect(poor.maxIntensity).toBe("easy");
    expect(poor.maxMinutes).toBe(113);
    expect(poor.sports.get("bike")?.maxAmount).toBe(15);
    expect(flagged.maxIntensity).toBe("easy");
  });

  it("erlaubt bei maessiger Erholung hoechstens moderate", () => {
    const today = dayLimits(multiSnapshot({ recovery: { status: "moderate" }, load: { days_since_last_hard_session: 5 } }), TODAY);

    expect(today.maxIntensity).toBe("moderate");
    expect(today.intensityReasons).toEqual(["Erholung mäßig"]);
  });

  it("verbietet hart nach einem harten Tag (Snapshot oder Verlauf) und nach zwei harten Tagen in 7 Tagen", () => {
    const base = { load: { days_since_last_hard_session: 5 } };
    const snapshotHard = dayLimits(multiSnapshot({ load: { days_since_last_hard_session: 1 } }), TODAY);
    const yesterday = dayLimits(multiSnapshot(base), TODAY, [{ date: "2026-09-29", sport: "bike", minutes: 60, meters: 0, hard: true }]);
    const twoInWeek = dayLimits(multiSnapshot(base), TODAY, [
      { date: "2026-09-25", sport: "bike", minutes: 60, meters: 0, hard: true },
      { date: "2026-09-27", sport: "run", minutes: 40, meters: 0, hard: true }
    ]);
    const longAgo = dayLimits(multiSnapshot(base), TODAY, [
      { date: "2026-09-20", sport: "bike", minutes: 60, meters: 0, hard: true },
      { date: "2026-09-27", sport: "run", minutes: 40, meters: 0, hard: true }
    ]);

    expect(snapshotHard.maxIntensity).toBe("moderate");
    expect(yesterday.intensityReasons).toEqual(["gestern oder heute schon eine harte Einheit"]);
    expect(twoInWeek.intensityReasons).toEqual(["schon 2 harte Tage in den letzten 7 Tagen"]);
    expect(longAgo.maxIntensity).toBe("hard");
  });

  it("nennt den Grund, wenn eine Sportart heute nicht mehr geht", () => {
    const full = dayLimits(multiSnapshot({ sports: { swim: { meters_last_seven_days: 4300 } } }), TODAY);
    const tiny = dayLimits(multiSnapshot({ recovery: { status: "poor" } }), TODAY);

    expect(full.sports.get("swim")).toMatchObject({ blockedReason: "Wochenumfang ausgeschöpft", maxAmount: 50 });
    expect(tiny.sports.get("run")).toMatchObject({ blockedReason: "zu wenig sicherer Umfang", maxAmount: 10 });
    expect(tiny.sports.get("run")?.intensityReasons).toContain("Wiedereinstieg nach Pause");
  });

  it("gibt einem Tag hoechstens die Haelfte der Wochenstunden, mindestens 45 Minuten", () => {
    expect(dayMinutesCap(multiSnapshot())).toBe(225);
    expect(dayMinutesCap(multiSnapshot({ goal: { weekly_hours: 1 } }))).toBe(45);
  });

  it("erkennt harte Tage im Verlauf", () => {
    const recent = [{ date: "2026-09-29", sport: "run", minutes: 30, meters: 5000, hard: true }, { date: "2026-09-28", sport: "run", minutes: 30, meters: 5000 }];

    expect(hardOn(recent, "2026-09-29")).toBe(true);
    expect(hardOn(recent, "2026-09-28")).toBe(false);
  });
});

describe("Phasen und Testsperre", () => {
  it("sperrt Tests in den letzten 14 Tagen vor dem Ziel, nicht davor und nicht nach dem Ziel", () => {
    const snapshot = multiSnapshot({ daysUntilGoal: 20 });

    expect(testBlackoutReason(snapshot, "2026-10-05")).toBeNull();
    expect(testBlackoutReason(snapshot, "2026-10-06")).toContain("14 Tagen");
    expect(testBlackoutReason(snapshot, "2026-10-20")).toContain("14 Tagen");
    expect(testBlackoutReason(snapshot, "2026-10-21")).toBeNull();
    expect(testBlackoutReason(multiSnapshot({ daysUntilGoal: -3 }), TODAY)).toBeNull();
  });

  it("spitzt lange Wettkaempfe zwei Wochen zu, kurze eine", () => {
    const olympic = multiSnapshot();
    const long = multiSnapshot({ goal: { disciplines: [{ sport: "bike", distance_meters: 180_000, target_duration_seconds: 6 * 3600 }] } });

    expect(taperWeeks(olympic)).toBe(1);
    expect(taperFactors(olympic)).toEqual([0.6]);
    expect(taperWeeks(long)).toBe(2);
    expect(taperFactors(long)).toEqual([0.75, 0.55]);
  });

  it("ordnet jeder Woche ihre Phase zu", () => {
    const goal = "2027-01-03";

    expect(goalDayOf(multiSnapshot({ daysUntilGoal: 95 }))).toBe(goal);
    expect(weeksToGoal("2026-12-28", goal)).toBe(0);
    expect(multiPhase("2026-12-28", goal, TODAY, 1)).toBe("goal_week");
    expect(multiPhase("2026-12-21", goal, TODAY, 1)).toBe("taper");
    expect(multiPhase("2026-12-14", goal, TODAY, 2)).toBe("taper");
    expect(multiPhase("2026-10-26", goal, TODAY, 1)).toBe("specific");
    expect(multiPhase("2026-10-19", goal, TODAY, 1)).toBe("base");
    expect(multiPhase("2026-12-28", "2026-09-01", TODAY, 1)).toBe("maintain");
  });

  it("nimmt die niedrigere Intensitaet", () => {
    expect(lower("hard", "easy")).toBe("easy");
    expect(lower("rest", "moderate")).toBe("rest");
  });
});
