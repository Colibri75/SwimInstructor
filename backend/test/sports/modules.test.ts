import { EMPTY_STATE, planningContext } from "../../src/plan/multi/sports";
import { checkTarget, normalizeStep } from "../../src/plan/multi/steps";
import { stepsTotals } from "../../src/plan/multi/tests";
import { bike } from "../../src/sports/modules/bike";
import { run } from "../../src/sports/modules/run";
import { effortDistanceStep, effortStep, paceRange, performanceValue, recentPaceSeconds, zoneRange } from "../../src/sports/modules/shared";
import { swim } from "../../src/sports/modules/swim";
import { PerformanceTestDefinition } from "../../src/sports/performance";
import { SPORTS } from "../../src/sports/registry";
import { SessionStep, SportDefinition, SportPerformance, SportPlanningContext, SportStateValues } from "../../src/sports/types";
import { STEP_TARGETS, StepTarget } from "../../src/sports/vocabulary";
import { multiSnapshot, RUNNER } from "../plan/multi/fixtures";

/**
 * Die Module selbst: Zielbereiche (`targetRange`), Testeinheiten und die gemeinsamen Bausteine aus shared.ts. Die
 * allgemeinen Pruefungen laufen ueber die Registry und gelten damit automatisch fuer jede neue Sportart.
 */

const MEASURED_AT = "2026-09-20T08:00:00Z";

function state(patch: Partial<SportStateValues> = {}): SportStateValues {
  return { ...EMPTY_STATE, ...patch };
}

function performance(values: Record<string, number>, zoneTargets: StepTarget[] = []): SportPerformance {
  return {
    values: Object.fromEntries(Object.entries(values).map(([metric, value]) => [metric, { value, source: "tested" as const, measuredAt: MEASURED_AT }])),
    zoneTargets
  };
}

function context(patch: Partial<SportPlanningContext> = {}): SportPlanningContext {
  return { state: EMPTY_STATE, ...patch };
}

/** Jeder Leistungswert der Sportart in der Mitte seines Bereichs, Zonen fuer jedes Ziel. */
function fullContext(sport: SportDefinition): SportPlanningContext {
  const values = Object.fromEntries(sport.performanceMetrics.map((metric) => [metric.id, Math.round((metric.min + metric.max) / 2)]));
  return context({ performance: performance(values, [...sport.targets]) });
}

/** Zusammenhaenge, fuer die jedes Modul sinnvolle Bereiche liefern muss: mit und ohne Profil, ohne Verlauf, mit allem. */
function contexts(sport: SportDefinition): Array<[string, SportPlanningContext]> {
  return [
    ["mit Profil", planningContext(multiSnapshot(), sport)],
    ["ohne Profil", planningContext(multiSnapshot({ performance: null }), sport)],
    ["ohne Verlauf und Ziel", context()],
    ["mit allen Werten und Zonen", fullContext(sport)]
  ];
}

const effortOf = (step: SessionStep): number | null => (step.target_type === "perceived_effort" ? step.target_value : null);

/** Dauer eines Schritts mit allen Wiederholungen, ohne Pausen; Strecken mit dem typischen Tempo der Sportart. */
function stepSeconds(sport: SportDefinition, step: SessionStep): number {
  const perRepetition = step.measure === "duration" ? (step.duration_seconds ?? 0) : (step.distance_meters ?? 0) / sport.planning.typicalSpeedMetersPerSecond;
  return perRepetition * step.repetitions;
}

const sportTable = SPORTS.sports.map((sport) => [sport.id, sport] as const);

describe.each(sportTable)("Modul %s", (_id, sport) => {
  const planning = sport.planning;
  const testTable = sport.performanceTests.map((test) => [test.id, test] as const);

  it("hat Prompt-Regeln als Liste", () => {
    expect(planning.promptRules.trim()).not.toBe("");
    for (const line of planning.promptRules.split("\n")) expect(line).toMatch(/^- \S/);
  });

  it("liefert fuer Ziele ausserhalb der eigenen keinen Bereich", () => {
    for (const [, ctx] of contexts(sport)) {
      for (const target of STEP_TARGETS.filter((target) => !sport.targets.includes(target))) {
        expect(planning.targetRange(target, ctx)).toBeNull();
      }
    }
  });

  it("liefert fuer jedes eigene Ziel einen stimmigen Bereich oder null", () => {
    for (const [label, ctx] of contexts(sport)) {
      for (const target of sport.targets) {
        const range = planning.targetRange(target, ctx);
        if (range === null) continue;
        expect({ label, target, finite: Number.isFinite(range.min) && Number.isFinite(range.max) }).toEqual({ label, target, finite: true });
        expect(range.min).toBeGreaterThan(0);
        expect(range.min).toBeLessThanOrEqual(range.max);
      }
    }
  });

  it("erlaubt die gefuehlte Anstrengung immer von 1 bis 10 (Ersatz fuer jedes andere Ziel)", () => {
    expect(sport.targets).toContain("perceived_effort");
    for (const [, ctx] of contexts(sport)) expect(planning.targetRange("perceived_effort", ctx)).toEqual({ min: 1, max: 10 });
  });

  it("gibt ohne Zonen der App kein Pulszonenziel", () => {
    for (const ctx of [context(), context({ performance: performance({}, []) }), planningContext(multiSnapshot({ performance: null }), sport)]) {
      expect(planning.targetRange("heart_rate_zone", ctx)).toBeNull();
    }
  });

  it("hat fuer jeden Leistungstest eine Testeinheit und keine weitere", () => {
    expect(Object.keys(planning.testSessions).sort()).toEqual(sport.performanceTests.map((test) => test.id).sort());
  });

  describe.each(testTable)("Testeinheit %s", (testId, test: PerformanceTestDefinition) => {
    const steps = planning.testSessions[testId] ?? [];

    it("hat Schritte in den Massen und im Raster der Sportart", () => {
      expect(steps.length).toBeGreaterThan(0);
      for (const step of steps) {
        expect(planning.stepMeasures).toContain(step.measure);
        expect(Number.isInteger(step.repetitions) && step.repetitions >= 1).toBe(true);
        expect(step.rest_seconds).toBeGreaterThanOrEqual(0);
        if (step.measure === "distance") {
          expect(step.duration_seconds).toBeNull();
          const meters = step.distance_meters as number;
          expect(meters % planning.distanceStepMeters).toBe(0);
          expect(meters).toBeGreaterThanOrEqual(planning.minStepMeters);
          expect(meters).toBeLessThanOrEqual(planning.maxStepMeters);
        } else {
          expect(step.distance_meters).toBeNull();
          const seconds = step.duration_seconds as number;
          expect(seconds).toBeGreaterThanOrEqual(planning.minStepSeconds);
          expect(seconds).toBeLessThanOrEqual(planning.maxStepSeconds);
        }
      }
    });

    it("hat Namen, Anweisung, einen Kurztext fuer die Uhr und nur Hilfsmittel der Sportart", () => {
      for (const step of steps) {
        expect(step.name.trim()).not.toBe("");
        expect(step.instructions.trim()).not.toBe("");
        expect(step.cue.trim()).not.toBe("");
        expect(step.cue.length).toBeLessThanOrEqual(30);
        for (const item of step.equipment) expect(Object.keys(planning.equipment)).toContain(item);
      }
    });

    it("verwendet nur eigene Ziele mit Werten im Bereich, mit und ohne Leistungswerte", () => {
      for (const step of steps) {
        expect(step.target_type === null).toBe(step.target_value === null);
        if (step.target_type === null) continue;
        expect(sport.targets).toContain(step.target_type);
        for (const [label, ctx] of contexts(sport)) {
          const range = planning.targetRange(step.target_type, ctx);
          expect({ label, step: step.name, range: range !== null }).toEqual({ label, step: step.name, range: true });
          expect(step.target_value).toBeGreaterThanOrEqual(range?.min ?? Infinity);
          expect(step.target_value).toBeLessThanOrEqual(range?.max ?? -Infinity);
        }
      }
    });

    it("uebersteht die Normalisierung und Zielpruefung des Tagesplans unveraendert", () => {
      const intensity = test.maximalEffort ? "hard" : "easy";
      for (const step of steps) {
        const { step: normalized } = normalizeStep({ ...step, equipment: [...step.equipment] }, sport, planning.typicalSpeedMetersPerSecond);
        expect(normalized).toEqual(step);
        for (const [, ctx] of contexts(sport)) expect(checkTarget(step, sport, ctx, intensity)).toEqual({ step, changed: false });
      }
    });

    it("beginnt und endet locker", () => {
      expect(effortOf(steps[0])).toBeLessThanOrEqual(3);
      expect(effortOf(steps[steps.length - 1])).toBeLessThanOrEqual(3);
    });

    it("traegt die Testbelastung mindestens so lange wie angegeben", () => {
      const efforts = steps.map(effortOf).filter((effort): effort is number => effort !== null);
      const top = Math.max(...efforts);
      const mainSeconds = steps.filter((step) => effortOf(step) === top).reduce((sum, step) => sum + stepSeconds(sport, step), 0);
      expect(mainSeconds).toBeGreaterThanOrEqual(test.durationMinutes * 60);
    });

    it("hat bei Vollbelastung einen Schritt mit Anstrengung ab 9, sonst keinen harten", () => {
      const top = Math.max(...steps.map((step) => effortOf(step) ?? 0));
      if (test.maximalEffort) expect(top).toBeGreaterThanOrEqual(9);
      else expect(top).toBeLessThanOrEqual(4);
    });

    it("passt als ganze Einheit in die Grenzen der Sportart", () => {
      const totals = stepsTotals(sport, steps, planning.typicalSpeedMetersPerSecond);
      expect(totals.amount).toBeGreaterThanOrEqual(planning.limits.minSession);
      expect(totals.amount).toBeLessThanOrEqual(planning.limits.absoluteMaxSession);
    });
  });
});

describe("Umfang der Testeinheiten", () => {
  const totals = (sport: SportDefinition, testId: string) => stepsTotals(sport, sport.planning.testSessions[testId] ?? [], sport.planning.typicalSpeedMetersPerSecond);

  it("Schwimmen: CSS-Test 1000 m, 1000-m-Test 1500 m", () => {
    expect(totals(swim, "css_400_200").amount).toBe(1000);
    expect(totals(swim, "time_trial_1000m").amount).toBe(1500);
  });

  it("Rad: 30-Minuten-Test 58 min mit Ein- und Ausfahren", () => {
    expect(totals(bike, "threshold_30min").amount).toBeCloseTo(58, 6);
  });

  it("Laufen: 30-Minuten-Test etwa 47 min, Einstiegstest 30 min", () => {
    expect(totals(run, "threshold_30min").amount).toBeCloseTo(47, 6);
    expect(totals(run, "entry_easy_25min").amount).toBeCloseTo(30, 6);
  });

  it("Schwimmen testet genau die Strecken der Formeln (400 und 200 m, 1000 m) mit Vollbelastung", () => {
    const hardDistances = (testId: string) =>
      (swim.planning.testSessions[testId] ?? []).filter((step) => (effortOf(step) ?? 0) >= 9).map((step) => [step.distance_meters, step.repetitions]);
    expect(hardDistances("css_400_200")).toEqual([
      [400, 1],
      [200, 1]
    ]);
    expect(hardDistances("time_trial_1000m")).toEqual([[1000, 1]]);
  });
});

describe("Schwimmen: Zielbereiche", () => {
  const range = swim.planning.targetRange;
  const swimState = state({ average_weekly_minutes: 67, average_weekly_meters: 3350 }); // 120 s/100 m inklusive Pausen
  const olympic = { distance_meters: 1500, target_duration_seconds: 1800 }; // Zielpace 120 s/100 m

  it("richtet die Pace mit bekannter CSS nach 88 % der CSS-Pace, langsamstens 10:00/100 m", () => {
    expect(range("pace_per_100m", planningContext(multiSnapshot(), swim))).toEqual({ min: Math.round(105 * 0.88), max: 600 });
    expect(range("pace_per_100m", context({ performance: performance({ css_pace_per_100m: 120 }) }))).toEqual({ min: 106, max: 600 });
  });

  it("nimmt ohne Leistungswerte die aktuelle Pace und die Zielpace (die langsamere Grenze gilt)", () => {
    // aktuell 120 * 0,6 = 72, Ziel 120 * 0,9 = 108
    expect(range("pace_per_100m", planningContext(multiSnapshot({ performance: null }), swim))).toEqual({ min: 108, max: 600 });
    expect(range("pace_per_100m", context({ state: swimState, discipline: olympic }))).toEqual({ min: 108, max: 600 });
  });

  it("faellt ohne CSS im Profil auf Verlauf und Ziel zurueck", () => {
    const withoutCss = context({ state: swimState, discipline: olympic, performance: performance({ max_heart_rate: 188 }, ["pace_per_100m"]) });
    expect(range("pace_per_100m", withoutCss)).toEqual({ min: 108, max: 600 });
  });

  it("nimmt ohne Zielzeit nur die aktuelle Pace", () => {
    expect(range("pace_per_100m", context({ state: swimState }))).toEqual({ min: 72, max: 600 });
    expect(range("pace_per_100m", context({ state: swimState, discipline: { distance_meters: 1500 } }))).toEqual({ min: 72, max: 600 });
  });

  it("bleibt ohne Verlauf vorsichtig langsamer als das Ziel und gibt ohne beides kein Pace-Ziel", () => {
    expect(range("pace_per_100m", context({ discipline: olympic }))).toEqual({ min: 156, max: 600 });
    expect(range("pace_per_100m", context())).toBeNull();
    expect(range("pace_per_100m", context({ discipline: { distance_meters: 1500 } }))).toBeNull();
  });

  it("haelt die schnellste Pace bei 0:40/100 m, auch bei unplausiblem Verlauf", () => {
    expect(range("pace_per_100m", context({ state: state({ average_weekly_minutes: 10, average_weekly_meters: 3000 }) }))).toEqual({ min: 40, max: 600 });
  });

  it("kennt die gefuehlte Anstrengung, aber kein Pulsziel, auch mit Pulszonen", () => {
    const withZones = planningContext(multiSnapshot(), swim);
    expect(withZones.performance?.zoneTargets).toContain("heart_rate_zone");
    expect(range("perceived_effort", withZones)).toEqual({ min: 1, max: 10 });
    expect(range("heart_rate_zone", withZones)).toBeNull();
    expect(range("pace_per_km", withZones)).toBeNull();
  });
});

describe("Rad: Zielbereiche", () => {
  const range = bike.planning.targetRange;

  it("gibt Watt nur mit bekannter Schwellenleistung, dann 40 bis 150 % davon", () => {
    expect(range("power", planningContext(multiSnapshot(), bike))).toBeNull();
    expect(range("power", context())).toBeNull();
    expect(range("power", context({ performance: performance({ threshold_power: 250 }) }))).toEqual({ min: 100, max: 375 });
    expect(range("power", context({ performance: performance({ threshold_power: 233 }) }))).toEqual({ min: 93, max: 350 });
  });

  it("gibt Pulszonen nur, wenn die App Zonen gerechnet hat", () => {
    expect(range("heart_rate_zone", planningContext(multiSnapshot(), bike))).toEqual({ min: 1, max: 5 });
    expect(range("heart_rate_zone", planningContext(multiSnapshot({ performance: null }), bike))).toBeNull();
    expect(range("heart_rate_zone", context({ performance: performance({ threshold_heart_rate: 160 }, ["power"]) }))).toBeNull();
  });

  it("erlaubt Trittfrequenz 50 bis 120 und gefuehlte Anstrengung 1 bis 10", () => {
    expect(range("cadence", context())).toEqual({ min: 50, max: 120 });
    expect(range("perceived_effort", context())).toEqual({ min: 1, max: 10 });
  });

  it("kennt kein Tempo- oder Paceziel", () => {
    const full = fullContext(bike);
    expect(range("speed", full)).toBeNull();
    expect(range("pace_per_km", full)).toBeNull();
    expect(range("pace_per_100m", full)).toBeNull();
  });
});

describe("Laufen: Zielbereiche", () => {
  const range = run.planning.targetRange;
  const runnerState = state(RUNNER); // 160 min auf 30 km: 320 s/km inklusive Gehpausen
  const tenK = { distance_meters: 10_000, target_duration_seconds: 3000 }; // Zielpace 300 s/km

  it("richtet die Pace mit Schwellentempo nach 85 % davon, langsamstens 15:00/km", () => {
    expect(range("pace_per_km", planningContext(multiSnapshot(), run))).toEqual({ min: Math.round(290 * 0.85), max: 900 });
    expect(range("pace_per_km", context({ performance: performance({ threshold_pace_per_km: 300 }) }))).toEqual({ min: 255, max: 900 });
  });

  it("nimmt ohne Schwellentempo Verlauf und Zielpace", () => {
    // aktuell 320 * 0,7 = 224, Ziel 300 * 0,9 = 270
    expect(range("pace_per_km", context({ state: runnerState, discipline: tenK }))).toEqual({ min: 270, max: 900 });
    expect(range("pace_per_km", context({ state: runnerState, discipline: { distance_meters: 10_000 } }))).toEqual({ min: 224, max: 900 });
    expect(range("pace_per_km", context({ state: runnerState, performance: performance({ threshold_heart_rate: 165 }) }))).toEqual({ min: 224, max: 900 });
  });

  it("bleibt ohne Verlauf langsamer als das Ziel und gibt ohne beides kein Pace-Ziel", () => {
    expect(range("pace_per_km", context({ discipline: tenK }))).toEqual({ min: 360, max: 900 });
    // Snapshot aus contracts/: Laufen ohne Verlauf und ohne Zielzeit.
    expect(range("pace_per_km", planningContext(multiSnapshot({ performance: null }), run))).toBeNull();
  });

  it("gibt Pulszonen nur mit Zonen aus dem Profil", () => {
    expect(range("heart_rate_zone", planningContext(multiSnapshot(), run))).toEqual({ min: 1, max: 5 });
    expect(range("heart_rate_zone", context({ state: runnerState }))).toBeNull();
  });

  it("erlaubt Schrittfrequenz 140 bis 200 und gefuehlte Anstrengung 1 bis 10", () => {
    expect(range("cadence", context())).toEqual({ min: 140, max: 200 });
    expect(range("perceived_effort", context())).toEqual({ min: 1, max: 10 });
  });

  it("kennt weder Watt noch Tempo noch Schwimm-Pace", () => {
    const full = fullContext(run);
    for (const target of ["power", "speed", "pace_per_100m", "stroke_rate"] as const) expect(range(target, full)).toBeNull();
  });
});

describe("Gemeinsame Bausteine (shared.ts)", () => {
  describe("recentPaceSeconds", () => {
    it("rechnet die Pace der letzten 4 Wochen je Strecke", () => {
      const swimState = state({ average_weekly_minutes: 67, average_weekly_meters: 3350 });
      expect(recentPaceSeconds(swimState, 100)).toBeCloseTo(120, 6);
      expect(recentPaceSeconds(swimState, 1000)).toBeCloseTo(1200, 6);
    });

    it("hat ohne Meter oder ohne Minuten keine Pace", () => {
      expect(recentPaceSeconds(state({ average_weekly_minutes: 60, average_weekly_meters: 0 }), 100)).toBeUndefined();
      expect(recentPaceSeconds(state({ average_weekly_minutes: 0, average_weekly_meters: 3000 }), 100)).toBeUndefined();
      expect(recentPaceSeconds(EMPTY_STATE, 1000)).toBeUndefined();
    });
  });

  describe("paceRange", () => {
    const options = { recentFactor: 0.6, goalFactor: 0.9, unknownGoalFactor: 1.3, absoluteFastest: 40, slowest: 600 };

    it("nimmt nur die aktuelle Pace, wenn kein Ziel bekannt ist", () => {
      expect(paceRange({ ...options, recent: 120, goal: undefined })).toEqual({ min: 72, max: 600 });
      expect(paceRange({ ...options, recent: 121, goal: undefined })).toEqual({ min: 73, max: 600 }); // 72,6 gerundet
    });

    it("nimmt ohne aktuelle Pace die Zielpace mal dem vorsichtigen Faktor", () => {
      expect(paceRange({ ...options, recent: undefined, goal: 120 })).toEqual({ min: 156, max: 600 });
    });

    it("nimmt mit beidem die langsamere der beiden Grenzen", () => {
      expect(paceRange({ ...options, recent: 120, goal: 100 })).toEqual({ min: 90, max: 600 });
      expect(paceRange({ ...options, recent: 200, goal: 100 })).toEqual({ min: 120, max: 600 });
    });

    it("gibt ohne beides kein Pace-Ziel", () => {
      expect(paceRange({ ...options, recent: undefined, goal: undefined })).toBeNull();
    });

    it("haelt die Untergrenze zwischen schnellster und langsamster Pace", () => {
      expect(paceRange({ ...options, recent: 50, goal: undefined })).toEqual({ min: 40, max: 600 });
      expect(paceRange({ ...options, recent: undefined, goal: 500 })).toEqual({ min: 600, max: 600 });
    });
  });

  describe("zoneRange", () => {
    it("gibt Zonen 1 bis 5 nur fuer Ziele, fuer die die App Zonen gerechnet hat", () => {
      const withZones = context({ performance: performance({}, ["heart_rate_zone"]) });
      expect(zoneRange(withZones, "heart_rate_zone")).toEqual({ min: 1, max: 5 });
      expect(zoneRange(withZones, "power")).toBeNull();
      expect(zoneRange(context(), "heart_rate_zone")).toBeNull();
    });

    it("kennt eine andere Zahl von Zonen", () => {
      expect(zoneRange(context({ performance: performance({}, ["power"]) }), "power", 7)).toEqual({ min: 1, max: 7 });
    });
  });

  describe("performanceValue", () => {
    it("liest einen Wert egal welcher Herkunft, sonst undefined", () => {
      const ctx = planningContext(multiSnapshot(), run);
      expect(performanceValue(ctx, "threshold_pace_per_km")).toBe(290); // geschaetzt
      expect(performanceValue(ctx, "threshold_heart_rate")).toBe(165); // Faustformel
      expect(performanceValue(ctx, "max_heart_rate")).toBe(188); // fuer alle Sportarten
      expect(performanceValue(ctx, "threshold_power")).toBeUndefined();
      expect(performanceValue(context(), "threshold_pace_per_km")).toBeUndefined();
    });
  });

  describe("effortStep und effortDistanceStep", () => {
    it("baut einen Schritt nach Dauer mit gefuehlter Anstrengung, standardmaessig einmal ohne Pause", () => {
      expect(effortStep("Einfahren", 12, 3, "Locker einfahren", "Locker einrollen.")).toEqual({
        name: "Einfahren",
        repetitions: 1,
        measure: "duration",
        distance_meters: null,
        duration_seconds: 720,
        target_type: "perceived_effort",
        target_value: 3,
        rest_seconds: 0,
        instructions: "Locker einrollen.",
        cue: "Locker einfahren",
        equipment: []
      });
    });

    it("rundet die Dauer auf ganze Sekunden und uebernimmt Wiederholungen und Pause", () => {
      const step = effortStep("Steigerung", 20 / 60, 7, "Steigern", "Zuegig.", 2, 40);
      expect(step).toMatchObject({ duration_seconds: 20, repetitions: 2, rest_seconds: 40, target_value: 7 });
      expect(effortStep("Kurz", 0.51, 5, "Kurz", "Kurz.").duration_seconds).toBe(31);
    });

    it("baut einen Schritt nach Strecke ohne Dauer", () => {
      expect(effortDistanceStep("Test 400 m", 400, 10, "400 m maximal", "So schnell wie moeglich.", 1, 600)).toEqual({
        name: "Test 400 m",
        repetitions: 1,
        measure: "distance",
        distance_meters: 400,
        duration_seconds: null,
        target_type: "perceived_effort",
        target_value: 10,
        rest_seconds: 600,
        instructions: "So schnell wie moeglich.",
        cue: "400 m maximal",
        equipment: []
      });
      expect(effortDistanceStep("Ausschwimmen", 100, 2, "Locker", "Locker.")).toMatchObject({ repetitions: 1, rest_seconds: 0, distance_meters: 100, duration_seconds: null });
    });

    it("gibt jedem Schritt eine eigene Hilfsmittel-Liste", () => {
      expect(effortStep("A", 1, 1, "A", "A").equipment).not.toBe(effortStep("B", 1, 1, "B", "B").equipment);
    });
  });
});
