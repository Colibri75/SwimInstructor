import { DEFAULT_LIMITS, dailyLimits, sanitizePlan } from "../../src/plan/sanity";
import { goodPlan, plan, planOfMeters, set, snapshot, sum } from "./fixtures";

describe("sanitizePlan: sinnvolle Plaene bleiben unveraendert", () => {
  it("laesst einen sauberen Plan ohne Korrektur durch", () => {
    const result = sanitizePlan(goodPlan, snapshot());

    expect(result.blocked).toBeNull();
    expect(result.adjustments).toEqual([]);
    expect(result.plan).toEqual(goodPlan);
  });

  it("ist idempotent: ein schon korrigierter Plan wird nicht noch einmal veraendert", () => {
    const first = sanitizePlan(planOfMeters(4000), snapshot());
    const second = sanitizePlan(first.plan, snapshot());

    expect(first.adjustments.length).toBeGreaterThan(0);
    expect(second.adjustments).toEqual([]);
    expect(second.plan).toEqual(first.plan);
  });
});

describe("sanitizePlan: Umfangssprung (gefaehrlicher Claude-Vorschlag)", () => {
  // laengste Einheit 2000 m -> Einheiten-Grenze 2500 m; Wochengrenze 3900 - 1500 = 2400 m
  it("kuerzt einen zu langen Plan auf die Grenze und behaelt Ein- und Ausschwimmen", () => {
    const result = sanitizePlan(planOfMeters(4000), snapshot());

    expect(result.blocked).toBeNull();
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(2400);
    expect(result.plan.total_distance_meters).toBe(sum(result.plan.sets));
    expect(result.plan.sets[0].name).toBe("Einschwimmen");
    expect(result.plan.sets[result.plan.sets.length - 1].name).toBe("Ausschwimmen");
    expect(result.adjustments.join(" ")).toContain("gekürzt");
  });

  it("skaliert die geschaetzte Dauer mit dem gekuerzten Umfang", () => {
    const result = sanitizePlan(planOfMeters(4800, { estimated_duration_minutes: 120 }), snapshot());

    expect(result.plan.estimated_duration_minutes).toBeLessThan(120);
    expect(result.plan.estimated_duration_minutes).toBeGreaterThanOrEqual(DEFAULT_LIMITS.minDurationMinutes);
  });

  it("kuerzt auch eine einzelne Dauerschwimm-Strecke", () => {
    const continuous = plan({
      sets: [set({ name: "Dauerschwimmen", repetitions: 1, distance_meters: 3600, rest_seconds: 0 })],
      total_distance_meters: 3600
    });

    const result = sanitizePlan(continuous, snapshot());

    expect(result.plan.sets).toHaveLength(1);
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(2400);
    expect(sum(result.plan.sets)).toBeGreaterThan(0);
  });

  it("begrenzt Einsteiger ohne Historie auf 1000 m", () => {
    const beginner = snapshot({
      volume: { last_seven_days_meters: 0, average_weekly_meters: 0, longest_session_meters: 0, sessions_last_seven_days: 0, sessions_last_four_weeks: 0 },
      pace: { recent_pace_seconds_per_hundred_meters: undefined },
      load: { days_since_last_workout: undefined, days_since_last_hard_session: undefined }
    });

    const result = sanitizePlan(planOfMeters(2000), beginner);

    expect(sum(result.plan.sets)).toBeLessThanOrEqual(1000);
  });

  it("uebersteigt nie die absolute Obergrenze, auch nicht bei sehr grossen Einheiten in der Historie", () => {
    const strong = snapshot({
      volume: { longest_session_meters: 6000, average_weekly_meters: 20_000, last_seven_days_meters: 0, sessions_last_seven_days: 2 }
    });

    const result = sanitizePlan(planOfMeters(6000), strong);

    expect(sum(result.plan.sets)).toBeLessThanOrEqual(DEFAULT_LIMITS.absoluteMaxSessionMeters);
  });

  it("macht einen Ruhetag daraus, wenn das Wochenvolumen schon ausgeschoepft ist", () => {
    // Wochengrenze 3000 * 1.3 = 3900, schon 3900 m geschwommen
    const maxedOut = snapshot({ volume: { last_seven_days_meters: 3900 } });

    const result = sanitizePlan(goodPlan, maxedOut);

    expect(result.plan.session_type).toBe("rest");
    expect(result.plan.sets).toEqual([]);
    expect(result.plan.total_distance_meters).toBe(0);
    expect(result.adjustments.join(" ")).toContain("Wochenumfang");
  });
});

describe("sanitizePlan: zu wenig sicherer Restumfang", () => {
  it("macht einen Ruhetag daraus, wenn nach dem Kuerzen weniger als ein sinnvoller Rest uebrig bleibt", () => {
    const limits = { ...DEFAULT_LIMITS, minSessionCapMeters: 310, minWeeklyCapMeters: 310, minMeaningfulSessionMeters: 310 };
    const nothing = snapshot({
      volume: { last_seven_days_meters: 0, average_weekly_meters: 0, longest_session_meters: 0, sessions_last_seven_days: 0 },
      load: { days_since_last_workout: undefined, days_since_last_hard_session: undefined }
    });
    // drei 150er: auf 310 m gekuerzt bleiben nur 300 m, das ist weniger als die Mindestgrenze
    const fragments = plan({
      sets: [set({ distance_meters: 150 }), set({ distance_meters: 150 }), set({ distance_meters: 150 })],
      total_distance_meters: 450
    });

    const result = sanitizePlan(fragments, nothing, limits);

    expect(result.plan.session_type).toBe("rest");
    expect(result.adjustments.join(" ")).toContain("zu wenig sicherer Restumfang");
  });
});

describe("sanitizePlan: Erholung und Ruhetage", () => {
  it("erzwingt bei Uebertrainingsrisiko einen Ruhetag und ersetzt die passende Begruendung", () => {
    const strained = snapshot({
      recovery: { status: "poor", warning_signals: ["elevated_resting_heart_rate", "low_heart_rate_variability", "short_sleep"] },
      flags: ["volume_spike", "recovery_poor", "overreaching_risk"]
    });
    const hardPlan = planOfMeters(2200, { session_type: "intervals", intensity: "hard", rationale: "Harte Intervalle fuer mehr Tempo." });

    const result = sanitizePlan(hardPlan, strained);

    expect(result.plan.session_type).toBe("rest");
    expect(result.plan.intensity).toBe("rest");
    expect(result.plan.sets).toEqual([]);
    expect(result.plan.rationale).toContain("Ruhe");
    expect(result.plan.rationale).not.toContain("Intervalle");
  });

  it("erzwingt einen Ruhetag nach fuenf Einheiten in sieben Tagen (fehlende Ruhetage)", () => {
    const busy = snapshot({ volume: { sessions_last_seven_days: 5, last_seven_days_meters: 2000 } });

    const result = sanitizePlan(goodPlan, busy);

    expect(result.plan.session_type).toBe("rest");
    expect(result.adjustments.join(" ")).toContain("Ruhetag");
  });

  it("erlaubt bei vier Einheiten noch Training", () => {
    const fourSessions = snapshot({ volume: { sessions_last_seven_days: 4 } });

    expect(sanitizePlan(goodPlan, fourSessions).plan.session_type).toBe("endurance");
  });

  it("senkt bei schlechter Erholung die Intensitaet auf easy und halbiert den Umfang", () => {
    const tired = snapshot({ recovery: { status: "poor", warning_signals: ["short_sleep", "low_heart_rate_variability"] }, flags: ["recovery_poor"] });
    const hardPlan = planOfMeters(2400, { session_type: "threshold", intensity: "hard" });

    const result = sanitizePlan(hardPlan, tired);

    // Grenze ohne Erholungsfaktor 2400 m, halbiert 1200 m
    expect(result.plan.intensity).toBe("easy");
    expect(result.plan.session_type).toBe("endurance");
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(1200);
    expect(result.plan.sets.every((s) => s.target_pace_seconds_per_hundred_meters === null)).toBe(true);
  });

  it("begrenzt bei maessiger Erholung auf moderate", () => {
    const meh = snapshot({ recovery: { status: "moderate", warning_signals: ["short_sleep"] } });

    const result = sanitizePlan(planOfMeters(1600, { session_type: "intervals", intensity: "hard" }), meh);

    expect(result.plan.intensity).toBe("moderate");
  });

  it("verbietet zwei harte Einheiten direkt hintereinander", () => {
    const hardYesterday = snapshot({ load: { days_since_last_workout: 1, days_since_last_hard_session: 1 } });

    const result = sanitizePlan(planOfMeters(1600, { session_type: "intervals", intensity: "hard" }), hardYesterday);

    expect(result.plan.intensity).toBe("moderate");
    expect(result.plan.session_type).toBe("endurance");
    expect(result.adjustments.join(" ")).toContain("harte Einheit");
  });

  it("erlaubt eine harte Einheit, wenn die letzte harte schon drei Tage her ist", () => {
    const rested = snapshot({ load: { days_since_last_workout: 3, days_since_last_hard_session: 3 } });
    const hardPlan = planOfMeters(1600, { session_type: "intervals", intensity: "hard" });

    expect(sanitizePlan(hardPlan, rested).plan.intensity).toBe("hard");
  });
});

describe("sanitizePlan: Trainingspause und Umfangsspitze", () => {
  it("begrenzt den Wiedereinstieg nach einer Pause auf 800 m und easy", () => {
    const afterBreak = snapshot({ load: { days_since_last_workout: 20, days_since_last_hard_session: undefined }, flags: ["training_pause"] });

    const result = sanitizePlan(planOfMeters(2000, { intensity: "hard", session_type: "intervals" }), afterBreak);

    expect(result.plan.intensity).toBe("easy");
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(800);
    expect(sum(result.plan.sets)).toBeGreaterThan(0);
  });

  it("drosselt nach einer Umfangsspitze auf moderate und 60 Prozent", () => {
    const spike = snapshot({ flags: ["volume_spike"] });

    const result = sanitizePlan(planOfMeters(2400, { intensity: "hard", session_type: "intervals" }), spike);

    // Grenze 2400 m, mal 0,6 = 1440 m
    expect(result.plan.intensity).toBe("moderate");
    expect(sum(result.plan.sets)).toBeLessThanOrEqual(1440);
  });
});

describe("sanitizePlan: unrealistische Zeiten", () => {
  it("begrenzt Zielpaces, die deutlich schneller als der Schwimmer sind", () => {
    // aktuelle Pace 255 -> schnellste erlaubte 153; Zielpace 94,7 -> 85; das Maximum zaehlt
    const beginner = snapshot({ pace: { recent_pace_seconds_per_hundred_meters: 255 } });
    const fast = plan({ sets: [set({ repetitions: 4, target_pace_seconds_per_hundred_meters: 60 })], total_distance_meters: 800 });

    const result = sanitizePlan(fast, beginner);

    expect(result.plan.sets[0].target_pace_seconds_per_hundred_meters).toBe(153);
    expect(result.adjustments.join(" ")).toContain("Zielpace");
  });

  it("verlangt ohne Pace-Historie hoechstens das 1,3-Fache der Zielpace", () => {
    const unknown = snapshot({ pace: { recent_pace_seconds_per_hundred_meters: undefined } });
    const fast = plan({ sets: [set({ repetitions: 4, target_pace_seconds_per_hundred_meters: 80 })], total_distance_meters: 800 });

    const result = sanitizePlan(fast, unknown);

    // 94,7 * 1,3 = 123,1 -> gerundet 123
    expect(result.plan.sets[0].target_pace_seconds_per_hundred_meters).toBe(123);
  });

  it("laesst realistische Zielpaces unveraendert", () => {
    const result = sanitizePlan(goodPlan, snapshot());

    expect(result.plan.sets[1].target_pace_seconds_per_hundred_meters).toBe(140);
  });

  it("verwirft absurd langsame Zielpaces statt sie zu uebernehmen", () => {
    const slow = plan({ sets: [set({ repetitions: 4, target_pace_seconds_per_hundred_meters: 9000 })], total_distance_meters: 800 });

    expect(sanitizePlan(slow, snapshot()).plan.sets[0].target_pace_seconds_per_hundred_meters).toBeNull();
  });
});

describe("sanitizePlan: Rechenfehler und Formalien", () => {
  it("korrigiert eine falsche Gesamtdistanz auf die Summe der Abschnitte", () => {
    const result = sanitizePlan(plan({ total_distance_meters: 3000 }), snapshot());

    expect(result.plan.total_distance_meters).toBe(1600);
    expect(result.adjustments.join(" ")).toContain("Gesamtdistanz korrigiert");
  });

  it("rundet Distanzen auf 25 m und begrenzt Pausen und Wiederholungen", () => {
    const messy = plan({
      sets: [set({ repetitions: 4, distance_meters: 130, rest_seconds: 9999 })],
      total_distance_meters: 520
    });

    const result = sanitizePlan(messy, snapshot());

    expect(result.plan.sets[0].distance_meters).toBe(125);
    expect(result.plan.sets[0].rest_seconds).toBe(DEFAULT_LIMITS.maxRestSeconds);
  });

  it("raeumt bei einem Ruhetag stehengebliebene Abschnitte auf", () => {
    const rest = plan({ session_type: "rest", intensity: "rest", total_distance_meters: 1600 });

    const result = sanitizePlan(rest, snapshot());

    expect(result.plan.sets).toEqual([]);
    expect(result.plan.total_distance_meters).toBe(0);
    expect(result.plan.estimated_duration_minutes).toBe(0);
  });

  it("laesst eine ausfuehrliche Uebungserklaerung unveraendert und kuerzt erst weit darueber", () => {
    const explained = "Zipper: Der Daumen streift beim Armzug an Bauch und Brust entlang, der Ellbogen bleibt hoch. ".repeat(3).trim();
    const plain = plan({ sets: [set({ repetitions: 4, instructions: explained })], total_distance_meters: 800 });
    const endless = plan({ sets: [set({ repetitions: 4, instructions: "y".repeat(5000) })], total_distance_meters: 800 });

    expect(explained.length).toBeLessThan(DEFAULT_LIMITS.maxInstructionLength);
    expect(sanitizePlan(plain, snapshot()).plan.sets[0].instructions).toBe(explained);
    expect(sanitizePlan(endless, snapshot()).plan.sets[0].instructions).toHaveLength(DEFAULT_LIMITS.maxInstructionLength);
  });

  it("entfernt doppeltes Equipment und begrenzt es auf drei Hilfsmittel je Abschnitt", () => {
    const crowded = plan({
      sets: [set({ repetitions: 4, equipment: ["pull_buoy", "pull_buoy", "paddles", "ankle_band", "snorkel", "fins"] })],
      total_distance_meters: 800
    });

    const result = sanitizePlan(crowded, snapshot());

    expect(result.plan.sets[0].equipment).toEqual(["pull_buoy", "paddles", "ankle_band"]);
    expect(result.adjustments).toEqual([]);
  });

  it("behaelt das Equipment, wenn ein Abschnitt gekuerzt wird", () => {
    const geared = plan({
      sets: [set({ name: "Hauptsatz", repetitions: 20, distance_meters: 200, equipment: ["paddles"] })],
      total_distance_meters: 4000
    });

    const result = sanitizePlan(geared, snapshot());

    expect(result.plan.sets[0].equipment).toEqual(["paddles"]);
    expect(result.plan.total_distance_meters).toBeLessThan(4000);
  });

  it("entfernt Hilfsmittel, die der Athlet nicht hat, und sagt es", () => {
    const geared = plan({
      sets: [set({ repetitions: 4, equipment: ["pull_buoy", "paddles"] }), set({ name: "Beine", repetitions: 4, equipment: ["fins", "kickboard"] })],
      total_distance_meters: 1600
    });

    const result = sanitizePlan(geared, snapshot(), undefined, { availableEquipment: ["pull_buoy", "kickboard"] });

    expect(result.plan.sets.map((s) => s.equipment)).toEqual([["pull_buoy"], ["kickboard"]]);
    expect(result.adjustments).toEqual(["Hilfsmittel entfernt, die du nicht hast: Paddles, Flossen"]);
  });

  it("entfernt jedes Hilfsmittel bei leerer Liste und laesst ohne Angabe alles stehen", () => {
    const geared = plan({ sets: [set({ repetitions: 4, equipment: ["pull_buoy", "paddles"] })], total_distance_meters: 800 });

    expect(sanitizePlan(geared, snapshot(), undefined, { availableEquipment: [] }).plan.sets[0].equipment).toEqual([]);
    expect(sanitizePlan(geared, snapshot()).plan.sets[0].equipment).toEqual(["pull_buoy", "paddles"]);
    expect(sanitizePlan(geared, snapshot(), undefined, { availableEquipment: ["pull_buoy", "paddles"] }).adjustments).toEqual([]);
  });

  it("kuerzt zu lange Texte und begrenzt die Zahl der Hinweise", () => {
    const wordy = plan({ rationale: "x".repeat(5000), coach_notes: Array.from({ length: 12 }, () => "y".repeat(1000)) });

    const result = sanitizePlan(wordy, snapshot());

    expect(result.plan.rationale.length).toBeLessThanOrEqual(DEFAULT_LIMITS.maxRationaleLength);
    expect(result.plan.coach_notes).toHaveLength(DEFAULT_LIMITS.maxNotes);
    expect(result.plan.coach_notes.every((n) => n.length <= DEFAULT_LIMITS.maxNoteLength)).toBe(true);
  });
});

describe("sanitizePlan: unbrauchbare Plaene werden geblockt", () => {
  const cases: Array<[string, Parameters<typeof plan>[0]]> = [
    ["negative Wiederholungen", { sets: [set({ repetitions: -3 })] }],
    ["Distanz null", { sets: [set({ distance_meters: 0 })] }],
    ["negative Pause", { sets: [set({ rest_seconds: -10 })] }],
    ["NaN als Distanz", { sets: [set({ distance_meters: Number.NaN })] }],
    ["Unendlich als Wiederholungen", { sets: [set({ repetitions: Number.POSITIVE_INFINITY })] }],
    ["negative Zielpace", { sets: [set({ target_pace_seconds_per_hundred_meters: -5 })] }],
    ["Trainingsplan ohne Abschnitte", { sets: [], total_distance_meters: 0 }],
    ["leere Begruendung", { rationale: "   " }],
    ["zu viele Abschnitte", { sets: Array.from({ length: 25 }, () => set()) }],
    ["wahnsinniger Umfang", { sets: [set({ repetitions: 50, distance_meters: 3800 })], total_distance_meters: 190000 }],
    ["negative Gesamtdistanz", { total_distance_meters: -1 }],
    ["unendliche Dauer", { estimated_duration_minutes: Number.POSITIVE_INFINITY }]
  ];

  it.each(cases)("blockt: %s", (_name, overrides) => {
    const result = sanitizePlan(plan(overrides), snapshot());

    expect(result.blocked).not.toBeNull();
    expect(result.adjustments).toEqual([]);
  });
});

describe("sanitizePlan: Begruendung bleibt nach Korrekturen stimmig", () => {
  it("haengt die Korrekturen an die Begruendung, damit sie nicht mehr den alten Umfang behauptet", () => {
    const original = plan({ ...planOfMeters(4000), rationale: "Mit 4000 m bleibt der Umfang moderat." });

    const result = sanitizePlan(original, snapshot());

    expect(result.plan.rationale).toContain("Mit 4000 m bleibt der Umfang moderat.");
    expect(result.plan.rationale).toContain("Hinweis: Zur Sicherheit angepasst");
    expect(result.plan.rationale).toContain("Umfang von 4000 m auf");
  });

  it("laesst die Begruendung unveraendert, wenn nichts korrigiert wurde", () => {
    expect(sanitizePlan(goodPlan, snapshot()).plan.rationale).toBe(goodPlan.rationale);
  });

  it("erwaehnt eine rein rechnerische Korrektur (falsche Summe) nicht in der Begruendung", () => {
    const result = sanitizePlan(plan({ total_distance_meters: 3000 }), snapshot());

    expect(result.adjustments.join(" ")).toContain("Gesamtdistanz korrigiert");
    expect(result.plan.rationale).toBe(goodPlan.rationale);
  });

  it("haelt die Begruendung auch mit Hinweis unter der Laengengrenze und bleibt idempotent", () => {
    const long = plan({ ...planOfMeters(4000), rationale: "x".repeat(DEFAULT_LIMITS.maxRationaleLength) });

    const first = sanitizePlan(long, snapshot());
    const second = sanitizePlan(first.plan, snapshot());

    expect(first.plan.rationale.length).toBeLessThanOrEqual(DEFAULT_LIMITS.maxRationaleLength);
    expect(first.plan.rationale).toContain("Hinweis: Zur Sicherheit angepasst");
    expect(second.plan).toEqual(first.plan);
  });
});

describe("dailyLimits", () => {
  it("fasst Umfang, Intensitaet und Tempo fuer heute zusammen", () => {
    expect(dailyLimits(snapshot())).toEqual({
      restReason: null,
      maxIntensity: "hard",
      intensityReasons: [],
      maxDistanceMeters: 2400,
      fastestPace: 85
    });
  });

  it("nennt einen Pflicht-Ruhetag mit Grund", () => {
    const strained = snapshot({ flags: ["overreaching_risk"] });

    expect(dailyLimits(strained).restReason).toContain("Übertrainingsrisiko");
  });

  it("macht aus einem erschoepften Wochenumfang einen Ruhetag", () => {
    expect(dailyLimits(snapshot({ volume: { last_seven_days_meters: 3900 } })).restReason).toBe("Wochenumfang ausgeschöpft");
  });

  it("stimmt mit dem ueberein, was sanitizePlan tatsaechlich durchsetzt", () => {
    const tired = snapshot({ recovery: { status: "poor", warning_signals: ["short_sleep", "low_heart_rate_variability"] }, flags: ["recovery_poor"] });
    const limits = dailyLimits(tired);

    const result = sanitizePlan(planOfMeters(4000, { intensity: "hard", session_type: "intervals" }), tired);

    expect(result.plan.intensity).toBe(limits.maxIntensity);
    expect(result.plan.total_distance_meters).toBeLessThanOrEqual(limits.maxDistanceMeters);
  });
});

