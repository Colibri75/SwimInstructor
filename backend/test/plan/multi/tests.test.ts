import { macroWeekStarts } from "../../../src/plan/calendar";
import { sportLimits } from "../../../src/plan/multi/limits";
import { chooseTest, entryTest, fitsToday, lastConfirmedTest, preferredTest, scheduleMacroTests, stepsTotals, testOf, testRef, TestWeek } from "../../../src/plan/multi/tests";
import { SnapshotV2 } from "../../../src/plan/snapshot";
import { SPORTS } from "../../../src/sports/registry";
import { multiSnapshot, RUNNER, TODAY } from "./fixtures";

const swim = SPORTS.get("swim")!;
const bike = SPORTS.get("bike")!;
const run = SPORTS.get("run")!;

describe("stepsTotals", () => {
  it("rechnet Umfang, Dauer und Strecke einer Testeinheit mit Pausen", () => {
    const swimTotals = stepsTotals(swim, swim.planning.testSessions.css_400_200, 1);
    const bikeTotals = stepsTotals(bike, bike.planning.testSessions.threshold_30min, 7);

    expect(swimTotals.amount).toBe(1000);
    expect(swimTotals.meters).toBe(1000);
    // 1000 s schwimmen plus 30 + 2 x 30 + 600 s Pause.
    expect(swimTotals.minutes).toBeCloseTo((1000 + 690) / 60);
    expect(bikeTotals.amount).toBe(58);
    expect(bikeTotals.meters).toBe(55 * 60 * 7);
  });
});

describe("Testwahl", () => {
  it("findet Tests ueber die Kennung und nimmt sonst den bevorzugten oder den ersten", () => {
    expect(testOf(run, "entry_easy_25min")?.id).toBe("entry_easy_25min");
    expect(testOf(run, null)).toBeUndefined();
    expect(testOf(run, "gibt_es_nicht")).toBeUndefined();
    expect(preferredTest(swim)?.id).toBe("css_400_200");
    expect(preferredTest(swim, { preferred: [{ sport: "swim", test_id: "time_trial_1000m" }] })?.id).toBe("time_trial_1000m");
    expect(preferredTest(swim, { preferred: [{ sport: "swim", test_id: "unbekannt" }] })?.id).toBe("css_400_200");
  });

  it("nimmt den angefragten Test, wenn er passt", () => {
    const limits = sportLimits(multiSnapshot(), swim);
    const chosen = chooseTest(limits, { requested: "time_trial_1000m", maxAmount: 2500, maxIntensity: "hard" });

    expect(chosen.plan?.test.id).toBe("time_trial_1000m");
    expect(chosen.plan?.amount).toBe(1500);
    expect(chosen.plan?.intensity).toBe("hard");
  });

  it("weicht auf den naechsten Test aus, wenn der erste nicht in die Grenze passt", () => {
    const limits = sportLimits(multiSnapshot(), swim);
    const chosen = chooseTest(limits, { requested: "time_trial_1000m", maxAmount: 1200, maxIntensity: "hard" });

    expect(chosen.plan?.test.id).toBe("css_400_200");
  });

  it("verlangt fuer einen Test mit Vollbelastung hart erlaubt und eine lange genug laengste Einheit", () => {
    const runner = sportLimits(multiSnapshot({ sports: { run: RUNNER } }), run);
    const beginner = sportLimits(multiSnapshot({ sports: { run: { ...RUNNER, longest_session_minutes: 25 } } }), run);

    expect(chooseTest(runner, { maxAmount: 65, maxIntensity: "hard" }).plan?.test.id).toBe("threshold_30min");
    // Nicht hart erlaubt oder zu kurze laengste Einheit: der lockere Einstiegstest.
    expect(chooseTest(runner, { maxAmount: 65, maxIntensity: "moderate" }).plan?.test.id).toBe("entry_easy_25min");
    expect(chooseTest(beginner, { maxAmount: 65, maxIntensity: "hard" }).plan).toMatchObject({ intensity: "easy", amount: 30 });
  });

  it("nennt den Grund des ersten Kandidaten, wenn kein Test passt", () => {
    const limits = sportLimits(multiSnapshot(), bike);

    expect(chooseTest(limits, { maxAmount: 120, maxIntensity: "easy", intensityReason: "Erholung schlecht" }).reason).toBe("30-Minuten-Test: keine Vollbelastung (Erholung schlecht)");
    expect(chooseTest(limits, { maxAmount: 120, maxIntensity: "moderate" }).reason).toContain('höchstens "moderate"');
    expect(chooseTest(limits, { maxAmount: 30, maxIntensity: "hard" }).reason).toBe("30-Minuten-Test: Testeinheit (58 min) über der Grenze (30 min)");
    expect(chooseTest(limits, { maxAmount: 120, maxMinutes: 45, maxIntensity: "hard" }).reason).toBe("30-Minuten-Test: Testeinheit (58 min) über der Tagesgrenze (45 min)");
    expect(chooseTest(sportLimits(multiSnapshot({ sports: { bike: { longest_session_minutes: 20 } } }), bike), { maxAmount: 120, maxIntensity: "hard" }).reason).toContain("unter 30 min");
  });

  it("meldet eine Sportart ohne Tests", () => {
    const limits = { ...sportLimits(multiSnapshot(), bike), sport: { ...bike, performanceTests: [] } };

    expect(chooseTest(limits, { maxAmount: 120, maxIntensity: "hard" })).toEqual({ plan: null, reason: "kein Test für diese Sportart" });
  });

  it("beschreibt einen Test fuer die App", () => {
    expect(testRef(run.performanceTests[0])).toEqual({
      id: "threshold_30min",
      display_name: "30-Minuten-Test",
      maximal_effort: true,
      produces: ["threshold_heart_rate", "threshold_pace_per_km"]
    });
  });
});

describe("lastConfirmedTest und entryTest", () => {
  it("nimmt nur getestete oder selbst eingegebene Werte, die ein Test der Sportart liefert", () => {
    const snapshot = multiSnapshot();

    expect(lastConfirmedTest(snapshot, swim)).toBe("2026-09-20");
    // Laufen: Schwellentempo nur geschaetzt, Schwellenpuls nur Faustformel.
    expect(lastConfirmedTest(snapshot, run)).toBeUndefined();
    expect(lastConfirmedTest(multiSnapshot({ performance: null }), swim)).toBeUndefined();
  });

  it("waehlt ohne tragfaehige Grundlage den Test ohne Vollbelastung", () => {
    expect(entryTest(run, multiSnapshot())?.id).toBe("entry_easy_25min");
    expect(entryTest(run, multiSnapshot({ sports: { run: RUNNER } }))?.id).toBe("threshold_30min");
    expect(entryTest(run, multiSnapshot(), { preferred: [{ sport: "run", test_id: "entry_easy_25min" }] })?.id).toBe("entry_easy_25min");
    // Rad hat keinen Test ohne Vollbelastung: der bevorzugte bleibt, Woche und Tag pruefen spaeter.
    expect(entryTest(bike, multiSnapshot({ sports: { bike: { longest_session_minutes: 10 } } }))?.id).toBe("threshold_30min");
    expect(entryTest({ ...bike, performanceTests: [] }, multiSnapshot())).toBeUndefined();
  });
});

describe("scheduleMacroTests", () => {
  const goalDay = "2027-07-04";
  const weeksOf = (snapshot: SnapshotV2, options: { from?: string; to?: string; amount?: number } = {}): TestWeek[] =>
    macroWeekStarts(options.from ?? TODAY, options.to ?? goalDay).map((week_start, index) => ({
      week_start,
      phase: "base",
      deload: false,
      amounts: new Map(SPORTS.ids.map((id) => [id, options.amount ?? 1]))
    }));
  const testsBySport = (schedule: Map<string, { sport: string; test_id: string }[]>) => {
    const result: Record<string, string[]> = {};
    for (const [week, tests] of schedule) for (const test of tests) (result[test.sport] ??= []).push(`${week} ${test.test_id}`);
    return result;
  };

  it("setzt Einstiegstests ohne bestaetigten Wert in die erste Woche und wiederholt alle 6 Wochen", () => {
    const snapshot = multiSnapshot();
    const tests = testsBySport(scheduleMacroTests(snapshot, weeksOf(snapshot).slice(0, 14), TODAY));

    // Rad (35 %) ohne bestaetigten Wert in Woche 1. Laufen ohne Grundlage mit dem lockeren Test, der heute nicht in die
    // Grenze fuer den Wiedereinstieg (20 min) passt: eine Woche spaeter.
    expect(tests.bike).toEqual(["2026-09-28 threshold_30min", "2026-11-09 threshold_30min", "2026-12-21 threshold_30min"]);
    expect(tests.run).toEqual(["2026-10-05 entry_easy_25min", "2026-11-16 threshold_30min", "2026-12-28 threshold_30min"]);
    // Schwimmen: CSS getestet am 20.09., faellig ab 01.11.
    expect(tests.swim).toEqual(["2026-10-26 css_400_200", "2026-12-07 css_400_200"]);
  });

  it("setzt einen Einstiegstest, der heute nicht in die Grenze passt, fruehestens in die naechste Woche", () => {
    const pause = multiSnapshot({ performance: null });
    const back = multiSnapshot({ performance: null, sports: { run: { days_since_last_session: 2, longest_session_minutes: 20 } } });

    expect(fitsToday(pause, run, testOf(run, "entry_easy_25min")!)).toBe(false);
    expect(fitsToday(back, run, testOf(run, "entry_easy_25min")!)).toBe(true);
    // Nur Laufen in den Wochen, damit keine andere Sportart die Testplaetze belegt.
    const runOnly = weeksOf(pause).slice(0, 4).map((week) => ({ ...week, amounts: new Map([["run", 30]]) }));
    expect(testsBySport(scheduleMacroTests(pause, runOnly, TODAY)).run).toEqual(["2026-10-05 entry_easy_25min"]);
    expect(testsBySport(scheduleMacroTests(back, runOnly, TODAY)).run).toEqual(["2026-09-28 entry_easy_25min"]);
  });

  it("setzt nach einer Pause trotz bestaetigtem Wert erst den Test ohne Vollbelastung, eine Woche spaeter", () => {
    const injured = multiSnapshot({
      sports: { run: { days_since_last_session: 45 } },
      performance: { athlete: [], sports: [{ sport: "run", values: [{ metric: "threshold_pace_per_km", value: 315, source: "tested", measured_at: "2026-06-20T08:00:00Z" }], zones: [] }] }
    });
    const runOnly = weeksOf(injured).slice(0, 10).map((week) => ({ ...week, amounts: new Map([["run", 30]]) }));

    expect(entryTest(run, injured)?.id).toBe("entry_easy_25min");
    expect(fitsToday(injured, run, testOf(run, "threshold_30min")!)).toBe(false);
    // Faellig seit August, aber im Wiedereinstieg: lockerer Test in der naechsten Woche, danach alle 6 Wochen der bevorzugte.
    expect(testsBySport(scheduleMacroTests(injured, runOnly, TODAY)).run).toEqual(["2026-10-05 entry_easy_25min", "2026-11-16 threshold_30min"]);
  });

  it("legt eine Wiederholung bevorzugt in eine Entlastungswoche bis zwei Wochen nach dem Termin", () => {
    const snapshot = multiSnapshot();
    const weeks = weeksOf(snapshot).slice(0, 12);
    // Faellig in der Woche ab 26.10.: Entlastung zwei Wochen danach wird genommen, drei Wochen danach nicht mehr.
    const twoLater = weeks.map((week, index) => ({ ...week, deload: index === 6 }));
    const threeLater = weeks.map((week, index) => ({ ...week, deload: index === 7 }));

    expect(testsBySport(scheduleMacroTests(snapshot, twoLater, TODAY)).swim[0]).toBe("2026-11-09 css_400_200");
    expect(testsBySport(scheduleMacroTests(snapshot, threeLater, TODAY)).swim[0]).toBe("2026-10-26 css_400_200");
  });

  it("haelt sich an das eingestellte Intervall, den bevorzugten Test und das Abschalten", () => {
    const snapshot = multiSnapshot();
    const weeks = weeksOf(snapshot).slice(0, 16);
    const custom = testsBySport(scheduleMacroTests(snapshot, weeks, TODAY, { interval_weeks: 8, preferred: [{ sport: "swim", test_id: "time_trial_1000m" }] }));

    expect(custom.swim).toEqual(["2026-11-09 time_trial_1000m", "2027-01-04 time_trial_1000m"]);
    expect([...scheduleMacroTests(snapshot, weeks, TODAY, { offer: false }).values()].flat()).toEqual([]);
  });

  it("plant hoechstens zwei Tests pro Woche, Sportarten mit groesserem Schwerpunkt zuerst", () => {
    const snapshot = multiSnapshot({ performance: null });
    const schedule = scheduleMacroTests(snapshot, weeksOf(snapshot).slice(0, 4), TODAY);

    expect(schedule.get("2026-09-28")?.map((test) => test.sport)).toEqual(["swim", "bike"]);
    expect(schedule.get("2026-10-05")?.map((test) => test.sport)).toEqual(["run"]);
  });

  it("plant keinen Test beim Zuspitzen, in der Zielwoche, in den 14 Tagen davor oder ohne Training", () => {
    const snapshot = multiSnapshot({ performance: null, daysUntilGoal: 25 });
    const weeks: TestWeek[] = [
      { week_start: "2026-09-28", phase: "specific", deload: false, amounts: new Map([["swim", 0], ["bike", 60], ["run", 30]]) },
      { week_start: "2026-10-05", phase: "specific", deload: false, amounts: new Map([["swim", 1000], ["bike", 60], ["run", 30]]) },
      { week_start: "2026-10-12", phase: "taper", deload: false, amounts: new Map([["swim", 1000], ["bike", 60], ["run", 30]]) },
      { week_start: "2026-10-19", phase: "goal_week", deload: false, amounts: new Map([["swim", 1000], ["bike", 60], ["run", 30]]) }
    ];
    const schedule = scheduleMacroTests(snapshot, weeks, TODAY);

    // Ziel 25.10.: Woche ab 05.10. endet am 11.10., 14 Tage vor dem Ziel, also gesperrt. Laufen passt erst ab dieser Woche.
    expect(schedule.get("2026-09-28")?.map((test) => test.sport)).toEqual(["bike"]);
    expect([...schedule.values()].flat().some((test) => test.sport === "swim" || test.sport === "run")).toBe(false);
  });

  it("wartet, wenn in dieser Woche keine drei Tage mehr bleiben", () => {
    const snapshot = multiSnapshot({ performance: null });
    const schedule = scheduleMacroTests(snapshot, weeksOf(snapshot).slice(0, 2), "2026-10-03");

    expect(schedule.get("2026-09-28")).toEqual([]);
    expect(schedule.get("2026-10-05")?.length).toBe(2);
  });

  it("erlaubt Tests nach dem Ziel (Erhalten)", () => {
    const snapshot = multiSnapshot({ performance: null, daysUntilGoal: -10 });
    const weeks: TestWeek[] = [{ week_start: "2026-09-28", phase: "maintain", deload: false, amounts: new Map([["swim", 1000], ["bike", 60], ["run", 30]]) }];

    expect(scheduleMacroTests(snapshot, weeks, TODAY).get("2026-09-28")?.length).toBe(2);
  });
});
