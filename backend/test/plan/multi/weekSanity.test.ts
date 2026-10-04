import { sanitizeWeekV2, WeekContextV2, weekLimitsV2, withNote } from "../../../src/plan/multi/weekSanity";
import { multiSnapshot, RUNNER, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

const rested = { load: { days_since_last_hard_session: 5 }, sports: { swim: { meters_last_seven_days: 1000 }, bike: { minutes_last_seven_days: 30 } } };
const context = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent: [], ...patch });
const hard = (sport: string, amount: number) => weekSession(sport, amount, { intensity: "hard", session_type: "intervals" });
const testOf = (sport: string, amount: number, testId: string | null = null) => weekSession(sport, amount, { session_type: "test", intensity: "hard", test_id: testId });

describe("sanitizeWeekV2", () => {
  it("laesst eine Woche in den Grenzen unveraendert", () => {
    const raw = weekPlan([[weekSession("swim", 2000)], [weekSession("bike", 60)], [], [weekSession("swim", 1500), weekSession("run", 20)], [], [hard("bike", 60)], []]);
    const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

    expect(result.blocked).toBeNull();
    expect(result.adjustments).toEqual([]);
    expect(result.plan.rationale).toBe(raw.rationale);
    expect(result.plan.days.map((day) => day.sessions.map((item) => `${item.sport} ${item.amount} ${item.unit}`))).toEqual([
      ["swim 2000 meters"],
      ["bike 60 minutes"],
      [],
      ["swim 1500 meters", "run 20 minutes"],
      [],
      ["bike 60 minutes"],
      []
    ]);
    expect(result.plan.days[2].focus).toBe("Ruhetag");
    expect(result.plan.total_minutes).toBe(result.plan.days.reduce((sum, day) => sum + day.sessions.reduce((s, item) => s + item.minutes, 0), 0));
  });

  it.each([
    ["ohne Begruendung", { rationale: " ", days: weekPlan([]).days }, "Begründung fehlt"],
    ["ohne Tage", { rationale: "x", days: [] }, "Wochenplan ohne Tage"],
    ["mit zu vielen Tagen", { rationale: "x", days: Array.from({ length: 15 }, () => weekPlan([]).days[0]) }, "zu viele Tage (15)"],
    ["mit zu vielen Einheiten an einem Tag", weekPlan([Array.from({ length: 7 }, () => weekSession("swim", 400))]), "zu viele Einheiten an einem Tag"],
    ["mit einer unendlichen Zahl", weekPlan([[weekSession("swim", Infinity)]]), "Zahlenwert in einer Einheit ungültig"]
  ])("blockt eine Woche %s", (_name, raw, reason) => {
    expect(sanitizeWeekV2(raw, multiSnapshot(), context()).blocked).toBe(reason);
  });

  it("ergaenzt fehlende Tage als Ruhetag und ignoriert fremde und doppelte Tage", () => {
    const raw = weekPlan([[weekSession("swim", 1000)]]);
    raw.days = [raw.days[0], { ...raw.days[0], sessions: [weekSession("bike", 60)] }, { date: "2026-09-01", focus: "x", sessions: [weekSession("bike", 60)] }];
    const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

    expect(result.plan.days).toHaveLength(7);
    expect(result.plan.days[0].sessions.map((item) => item.sport)).toEqual(["swim"]);
    expect(result.adjustments[0]).toMatch(/^6 fehlende Tage als Ruhetag ergänzt/);
  });

  it("setzt Tage ohne Zeit als Ruhetag und entfernt Sportarten ohne Schwerpunkt", () => {
    const raw = weekPlan([[weekSession("swim", 1000)], [weekSession("kayak", 30)], [weekSession("run", 0)], [weekSession("swim", 1000, { session_type: "rest" })]]);
    const result = sanitizeWeekV2(raw, multiSnapshot(rested), context({ unavailable: ["2026-09-30"] }));

    expect(result.plan.days[0]).toEqual({ date: "2026-09-30", focus: "Keine Zeit", sessions: [] });
    expect(result.plan.days.slice(1, 4).every((day) => day.sessions.length === 0)).toBe(true);
    expect(result.adjustments).toEqual(["Mittwoch, 30.09.: keine Zeit, als Ruhetag gesetzt", "Einheiten von Sportarten ohne Schwerpunkt entfernt (kayak)"]);
  });

  it("kuerzt auf zwei Einheiten am Tag und hebt zu kleine Einheiten an oder streicht sie", () => {
    const raw = weekPlan([[], [weekSession("swim", 400), weekSession("bike", 30), weekSession("swim", 1500)], [weekSession("bike", 12)], [weekSession("bike", 5)]]);
    const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

    expect(result.plan.days[1].sessions.map((item) => item.amount)).toEqual([30, 1500]);
    expect(result.plan.days[2].sessions[0].amount).toBe(20);
    expect(result.plan.days[3].sessions).toEqual([]);
    expect(result.adjustments).toEqual([
      "Donnerstag, 01.10.: auf 2 Einheiten gekürzt",
      "Freitag, 02.10.: Radfahren von 10 min auf 20 min angehoben (kleinste sinnvolle Einheit)",
      "Samstag, 03.10.: Radfahren unter 20 min gestrichen"
    ]);
  });

  describe("gefaehrliche Plaene", () => {
    it("begrenzt den Laufumfang je Einheit und Woche", () => {
      const runner = multiSnapshot({ ...rested, sports: { ...rested.sports, run: RUNNER } });
      const raw = weekPlan([[], [weekSession("run", 90)], [weekSession("run", 60)], [], [weekSession("run", 80)], [weekSession("run", 70)], []]);
      const result = sanitizeWeekV2(raw, runner, context());
      const runs = result.plan.days.flatMap((day) => day.sessions.filter((item) => item.sport === "run"));

      // Laengste Einheit 60 min: je Einheit hoechstens 65 min; Schnitt 160 min: hoechstens 205 min in der Woche.
      expect(Math.max(...runs.map((item) => item.amount))).toBeLessThanOrEqual(65);
      expect(runs.reduce((sum, item) => sum + item.amount, 0)).toBeLessThanOrEqual(205);
      expect(result.adjustments).toContain("Laufen: Wochenumfang von 255 min auf höchstens 205 min gekürzt");
    });

    it("erlaubt keine harten Tage hintereinander, auch nicht ueber Sportarten und nach einem harten Tag vor dem Plan", () => {
      const raw = weekPlan([[hard("swim", 1500)], [hard("bike", 60)], [hard("bike", 45)], [], [hard("swim", 1500)], [hard("bike", 60)], []]);
      const result = sanitizeWeekV2(raw, multiSnapshot({ ...rested, load: { days_since_last_hard_session: 1 } }), context());
      const hardDays = result.plan.days.flatMap((day, index) => (day.sessions.some((item) => item.intensity === "hard") ? [index] : []));

      expect(hardDays).toEqual([1, 4]);
      expect(result.adjustments).toEqual(
        expect.arrayContaining([
          'Mittwoch, 30.09.: Schwimmen auf "moderate" gesenkt (gestern oder heute schon eine harte Einheit)',
          'Freitag, 02.10.: harte Einheit auf "moderate" gesenkt (nicht an zwei Tagen nacheinander)',
          'Montag, 05.10.: harte Einheit auf "moderate" gesenkt (nicht an zwei Tagen nacheinander)'
        ])
      );
    });

    it("erlaubt hoechstens zwei harte Tage in der Woche", () => {
      const raw = weekPlan([[], [hard("swim", 1500)], [], [hard("bike", 60)], [], [hard("swim", 1500)], []]);
      const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

      expect(result.plan.days.filter((day) => day.sessions.some((item) => item.intensity === "hard"))).toHaveLength(2);
      expect(result.adjustments).toContain('Montag, 05.10.: harte Einheit auf "moderate" gesenkt (höchstens 2 harte Tage)');
    });

    it("erlaubt am Tag nur eine harte Einheit", () => {
      const raw = weekPlan([[], [hard("swim", 1500), hard("bike", 60)]]);
      const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

      expect(result.plan.days[1].sessions.map((item) => item.intensity)).toEqual(["hard", "moderate"]);
    });

    it("setzt Ruhetage, wenn zu wenig Ruhe geplant ist", () => {
      const raw = weekPlan(Array.from({ length: 7 }, (_, index) => [weekSession(index % 2 === 0 ? "swim" : "bike", index % 2 === 0 ? 1000 : 30)]));
      const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

      expect(result.plan.days.filter((day) => day.sessions.length > 0)).toHaveLength(5);
      expect(result.adjustments.filter((note) => note.includes("als Ruhetag gesetzt (höchstens 5 Trainingstage)"))).toHaveLength(2);
    });

    it("laesst in einer vollen Woche mindestens einen Ruhetag, auch bei 7 Trainingstagen im Ziel", () => {
      const sessions = [weekSession("swim", 600), weekSession("bike", 30), weekSession("swim", 600), weekSession("bike", 30), weekSession("swim", 600), weekSession("bike", 30), weekSession("run", 15)];
      const raw = weekPlan(sessions.map((item) => [item]));
      const result = sanitizeWeekV2(raw, multiSnapshot({ ...rested, goal: { training_days_per_week: 7 } }), context());

      expect(result.plan.days.filter((day) => day.sessions.length === 0)).toHaveLength(1);
      // Der leichteste Tag (600 m Schwimmen sind 12 min), bei Gleichstand der spaeteste.
      expect(result.adjustments).toContain("Sonntag, 04.10.: als Ruhetag gesetzt (mindestens ein Ruhetag pro Woche)");
    });

    it("kuerzt die Woche auf die Wochenstunden und jeden Tag auf die Tagesgrenze", () => {
      const snapshot = multiSnapshot({ ...rested, goal: { weekly_hours: 2 } });
      const raw = weekPlan([[], [weekSession("bike", 120), weekSession("swim", 2000)], [], [weekSession("bike", 120)]]);
      const result = sanitizeWeekV2(raw, snapshot, context());

      expect(result.plan.total_minutes).toBeLessThanOrEqual(120);
      for (const day of result.plan.days) expect(day.sessions.reduce((sum, item) => sum + item.minutes, 0)).toBeLessThanOrEqual(60);
      expect(result.adjustments).toEqual(expect.arrayContaining([expect.stringMatching(/^Donnerstag, 01\.10\.: Tagesumfang von \d+ min auf höchstens 60 min gekürzt$/)]));
    });

    it("haelt einen Wiedereinsteiger locker und kurz", () => {
      const raw = weekPlan([[], [hard("run", 45)], [], [weekSession("run", 40, { intensity: "moderate" })]]);
      const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

      expect(result.plan.days[1].sessions[0]).toMatchObject({ intensity: "easy", session_type: "endurance", amount: 20 });
      expect(result.plan.days[3].sessions[0]).toMatchObject({ intensity: "easy", amount: 20 });
    });
  });

  describe("heute", () => {
    it("haelt die Grenzen fuer heute ein", () => {
      const raw = weekPlan([[weekSession("swim", 2500), hard("bike", 90)]]);
      const result = sanitizeWeekV2(raw, multiSnapshot({ load: { days_since_last_hard_session: 1 } }), context());

      // Heute: Schwimmen hoechstens 850 m (4350 - 3500), Rad hoechstens 30 min (120 - 90), nach hartem Tag nur moderate.
      expect(result.plan.days[0].sessions.map((item) => [item.amount, item.intensity])).toEqual([
        [850, "easy"],
        [30, "moderate"]
      ]);
    });

    it("streicht heute eine ausgeschoepfte Sportart und erzwingt bei Uebertrainingsrisiko Ruhe", () => {
      const full = sanitizeWeekV2(weekPlan([[weekSession("swim", 1000)]]), multiSnapshot({ sports: { swim: { meters_last_seven_days: 4300 } } }), context());
      const overreached = sanitizeWeekV2(weekPlan([[weekSession("bike", 30)], [weekSession("bike", 30)]]), multiSnapshot({ flags: ["overreaching_risk"] }), context());

      expect(full.plan.days[0].sessions).toEqual([]);
      expect(full.adjustments).toContain("Mittwoch, 30.09.: Schwimmen gestrichen (Wochenumfang ausgeschöpft)");
      expect(overreached.plan.days[0]).toMatchObject({ focus: "Ruhetag", sessions: [] });
      expect(overreached.plan.days[1].sessions).toHaveLength(1);
    });

    it("kennt heute nicht, wenn die Tage spaeter beginnen", () => {
      const dates = weekDates("2026-10-02");
      const limits = weekLimitsV2(multiSnapshot(), context({ dates }));

      expect(limits.today).toBeNull();
      expect(limits.hardBefore).toBe(false);
      expect(weekLimitsV2(multiSnapshot(), context({ dates, recent: [{ date: "2026-10-01", sport: "run", minutes: 30, meters: 5000, hard: true }] })).hardBefore).toBe(true);
    });
  });

  describe("Leistungstests", () => {
    const fresh = multiSnapshot({ ...rested, sports: { ...rested.sports, run: RUNNER } });

    it("setzt den Test mit dem Umfang der Testeinheit ein und rechnet ihn als harten Tag", () => {
      const raw = weekPlan([[], [testOf("bike", 90, "threshold_30min")], [hard("swim", 1500)], [], [weekSession("swim", 1000)]]);
      const result = sanitizeWeekV2(raw, fresh, context());

      expect(result.plan.days[1].sessions[0]).toMatchObject({
        session_type: "test",
        intensity: "hard",
        amount: 58,
        minutes: 58,
        focus: "30-Minuten-Test",
        test: { id: "threshold_30min", display_name: "30-Minuten-Test", maximal_effort: true, produces: ["threshold_heart_rate", "threshold_power"] }
      });
      expect(result.plan.days[2].sessions[0].intensity).toBe("moderate");
    });

    it("gibt einem Test Vorrang vor einer harten Einheit am Tag davor", () => {
      const raw = weekPlan([[], [hard("bike", 60)], [testOf("swim", 1000, "css_400_200")]]);
      const result = sanitizeWeekV2(raw, fresh, context());

      expect(result.plan.days[2].sessions[0].test?.id).toBe("css_400_200");
      expect(result.plan.days[1].sessions[0].intensity).toBe("moderate");
    });

    it("macht aus einem Test nach einem harten Tag vor dem Plan eine lockere Einheit", () => {
      const recent = [{ date: "2026-10-01", sport: "run", minutes: 50, meters: 10_000, hard: true }];
      const raw = weekPlan([[testOf("bike", 60, "threshold_30min")]], "2026-10-02");
      const result = sanitizeWeekV2(raw, fresh, context({ dates: weekDates("2026-10-02"), recent }));

      expect(result.plan.days[0].sessions[0]).toMatchObject({ session_type: "endurance", intensity: "easy", test: null, focus: "Locker statt Leistungstest" });
      expect(result.adjustments).toContain("Freitag, 02.10.: kein Leistungstest Radfahren (nicht an zwei Tagen nacheinander), lockere Einheit statt dessen");
    });

    it("ersetzt den Schwerpunkt eines Tages, der einen gestrichenen Test ankuendigt", () => {
      const raw = weekPlan([[], [testOf("run", 30, "threshold_30min")], [], [testOf("run", 30, "threshold_30min")]]);
      raw.days[1].focus = "Leistungstest Laufen";
      const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

      // Beide Tests fallen weg (Wiedereinstieg), der zweite Tag hiess aber nur "Training".
      expect(result.plan.days[1].focus).toBe("Locker statt Leistungstest");
      expect(result.plan.days[3].focus).toBe("Training");
    });

    it("erlaubt einen Test je Tag und je Sportart und nie an zwei Tagen hintereinander", () => {
      const raw = weekPlan([[], [testOf("swim", 1000), testOf("bike", 60)], [testOf("run", 47)], [testOf("swim", 1500)], [], [testOf("run", 47)]]);
      const result = sanitizeWeekV2(raw, fresh, context());
      const tests = result.plan.days.map((day) => day.sessions.filter((item) => item.test !== null).map((item) => item.sport));

      expect(tests).toEqual([[], ["swim"], [], [], [], ["run"], []]);
      expect(result.adjustments).toEqual(
        expect.arrayContaining([
          "Donnerstag, 01.10.: kein Leistungstest Radfahren (höchstens ein Test pro Tag), lockere Einheit statt dessen",
          "Freitag, 02.10.: kein Leistungstest Laufen (nicht an zwei Tagen nacheinander), lockere Einheit statt dessen",
          "Samstag, 03.10.: kein Leistungstest Schwimmen (höchstens ein Test je Sportart pro Woche), lockere Einheit statt dessen"
        ])
      );
    });

    it.each([
      ["abgeschaltet", { testSettings: { offer: false } }, {}, "Leistungstests sind abgeschaltet"],
      ["kurz vor dem Ziel", {}, { daysUntilGoal: 12 }, "kein Test in den letzten 14 Tagen vor dem Ziel"]
    ])("plant keinen Test, wenn er %s ist", (_name, patch, snapshotPatch, reason) => {
      const raw = weekPlan([[], [testOf("bike", 60, "threshold_30min")]]);
      const result = sanitizeWeekV2(raw, multiSnapshot({ ...rested, ...snapshotPatch }), context(patch));

      expect(result.plan.days[1].sessions[0]).toMatchObject({ test: null, intensity: "easy" });
      expect(result.adjustments[0]).toContain(reason);
    });

    it("plant einen Laufanfaenger nicht in einen Test, der nicht passt", () => {
      const raw = weekPlan([[], [testOf("run", 30, "threshold_30min")]]);
      const result = sanitizeWeekV2(raw, multiSnapshot(rested), context());

      // Wiedereinstieg: Test mit Vollbelastung geht nicht, der lockere (30 min) passt nicht in 20 min; es bleibt ein lockerer Lauf.
      expect(result.plan.days[1].sessions[0]).toMatchObject({ sport: "run", test: null, intensity: "easy", amount: 20 });
      expect(result.adjustments[0]).toBe("Donnerstag, 01.10.: kein Leistungstest Laufen (30-Minuten-Test: keine Vollbelastung (Wiedereinstieg nach Pause)), lockere Einheit statt dessen");
    });

    it("haelt heute auch fuer den Test die Grenzen fuer heute ein", () => {
      // Heute nach hartem Tag: kein Test mit Vollbelastung; der lockere Lauftest passt.
      const raw = weekPlan([[testOf("run", 30, "threshold_30min")]]);
      const result = sanitizeWeekV2(raw, multiSnapshot({ ...rested, load: { days_since_last_hard_session: 1 }, sports: { ...rested.sports, run: { ...RUNNER, minutes_last_seven_days: 60 } } }), context());

      expect(result.plan.days[0].sessions[0]).toMatchObject({ intensity: "easy", test: { id: "entry_easy_25min" }, amount: 30 });
    });

    it("plant Tests zusammen nur bis zu den Wochenstunden", () => {
      const snapshot = multiSnapshot({ ...rested, goal: { weekly_hours: 0.5 }, sports: { ...rested.sports, run: RUNNER } });
      const raw = weekPlan([[], [testOf("swim", 1000)], [], [testOf("run", 30, "entry_easy_25min")]]);
      const result = sanitizeWeekV2(raw, snapshot, context());

      expect(result.plan.days.flatMap((day) => day.sessions).filter((item) => item.test !== null)).toHaveLength(1);
      expect(result.plan.total_minutes).toBeLessThanOrEqual(30);
    });
  });

  it("zeigt hoechstens 12 Korrekturen und zaehlt den Rest", () => {
    const raw = weekPlan(Array.from({ length: 7 }, () => [hard("run", 200), hard("swim", 6000), hard("bike", 400)]));
    const result = sanitizeWeekV2(raw, multiSnapshot(), context());

    expect(result.adjustments).toHaveLength(13);
    expect(result.adjustments[12]).toMatch(/^… und \d+ weitere Korrekturen$/);
  });
});

describe("withNote", () => {
  it("haengt bis zu drei Korrekturen an und haelt die Laenge", () => {
    expect(withNote("Plan.", [])).toBe("Plan.");
    expect(withNote("Plan.", ["a", "b", "c", "d"])).toBe("Plan. Hinweis: Zur Sicherheit angepasst (a; b; c; und 1 weitere).");
    expect(withNote("x".repeat(1300), ["a"]).length).toBeLessThanOrEqual(1200);
  });
});
