import { macroWeekStarts } from "../../../src/plan/macro";
import { MacroContextV2, macroSportLimits, sanitizeMacroV2 } from "../../../src/plan/multi/macroSanity";
import { MultiMacroPlanRaw } from "../../../src/plan/multi/schemas";
import { macroPlan, multiSnapshot, TODAY } from "./fixtures";

const GOAL_DAY = "2027-07-04";
const ALL_WEEKS = macroWeekStarts(TODAY, GOAL_DAY);
const context = (weeks = ALL_WEEKS.slice(0, 8), patch: Partial<MacroContextV2> = {}): MacroContextV2 => ({ today: TODAY, goalDay: GOAL_DAY, weeks, ...patch });
const amounts = (plan: { weeks: { sports: { sport: string; amount: number }[] }[] }, sport: string) => plan.weeks.map((week) => week.sports.find((entry) => entry.sport === sport)?.amount);
const flat = (swim: number, bike: number, run: number) => () => ({ swim, bike, run });

describe("macroSportLimits", () => {
  it("nennt je Sportart die Grenzen fuer den Gesamtplan", () => {
    const [swim, bike, run] = macroSportLimits(multiSnapshot());

    expect(swim).toMatchObject({ firstWeekCap: 4350, floor: 1500, growthFactor: 1.1, race: 1500, absoluteWeekly: 22_500 });
    expect(bike).toMatchObject({ firstWeekCap: 120, floor: 120, race: 80 });
    // Laufen ohne Verlauf: Wiedereinstieg, erste Woche hoechstens 60 min.
    expect(run.firstWeekCap).toBe(60);
    expect(run.floor).toBe(60);
    expect(run.race).toBeCloseTo(10_000 / 2.8 / 60);
  });
});

describe("sanitizeMacroV2", () => {
  it("laesst einen Plan in den Grenzen unveraendert und rechnet Minuten, Strecke und Last", () => {
    const raw = macroPlan(ALL_WEEKS.slice(0, 3), (index) => ({ swim: [3500, 3800, 4100][index], bike: [100, 110, 120][index], run: [30, 40, 45][index] }));
    const result = sanitizeMacroV2(raw, multiSnapshot(), context(ALL_WEEKS.slice(0, 3)));

    expect(result.blocked).toBeNull();
    expect(result.adjustments).toEqual([]);
    expect(result.plan.rationale).toBe(raw.rationale);
    const week = result.plan.weeks[0];
    expect(week).toMatchObject({ week_start: "2026-09-28", phase: "base", deload: false, focus: "Grundlage" });
    expect(week.sports[0]).toMatchObject({ sport: "swim", unit: "meters", amount: 3500, minutes: 70, distance_meters: 3500, sessions: 3 });
    expect(week.sports[1]).toMatchObject({ sport: "bike", unit: "minutes", amount: 100, minutes: 100 });
    expect(week.sports[2]).toMatchObject({ sport: "run", amount: 30, distance_meters: 5050, sessions: 2 });
    expect(week.total_minutes).toBe(200);
    expect(week.load).toBe(70 + 80 + 30);
  });

  it.each([
    ["ohne Begruendung", { rationale: " ", weeks: macroPlan(ALL_WEEKS.slice(0, 1), flat(1000, 60, 20)).weeks }, "Begründung fehlt"],
    ["ohne Wochen", { rationale: "x", weeks: [] }, "Gesamtplan ohne Wochen"],
    ["mit viel zu vielen Wochen", macroPlan(Array.from({ length: 17 }, () => ALL_WEEKS[0]), flat(1000, 60, 20)), "zu viele Wochen (17)"],
    ["mit unendlichen Zahlen", macroPlan(ALL_WEEKS.slice(0, 1), flat(NaN, 60, 20)), "Zahlenwert in einer Woche ungültig"]
  ])("blockt einen Plan %s", (_name, raw, reason) => {
    expect(sanitizeMacroV2(raw as MultiMacroPlanRaw, multiSnapshot(), context()).blocked).toBe(reason);
  });

  it("blockt zu viele Sportarten in einer Woche", () => {
    const raw = macroPlan(ALL_WEEKS.slice(0, 1), flat(1000, 60, 20));
    raw.weeks[0].sports = Array.from({ length: 33 }, () => ({ sport: "swim", amount: 1000, sessions: 2 }));

    expect(sanitizeMacroV2(raw, multiSnapshot(), context()).blocked).toBe("zu viele Sportarten in einer Woche");
  });

  it("ergaenzt fehlende Wochen mit der Vorwoche und entfernt Sportarten ohne Schwerpunkt", () => {
    const raw = macroPlan(ALL_WEEKS.slice(0, 1), () => ({ swim: 3000, bike: 100, run: 30, rowing: 50 }));
    const result = sanitizeMacroV2(raw, multiSnapshot(), context(ALL_WEEKS.slice(0, 3)));

    expect(amounts(result.plan, "swim")).toEqual([3000, 3000, 3000]);
    expect(result.plan.weeks[1].focus).toBe("Grundlage");
    expect(result.adjustments.slice(0, 2)).toEqual(["2 fehlende Wochen mit dem Umfang der Vorwoche ergänzt", "Sportarten ohne Schwerpunkt entfernt: rowing"]);
  });

  it("ergaenzt eine fehlende erste Woche mit dem bisherigen Schnitt", () => {
    const raw = macroPlan(ALL_WEEKS.slice(1, 2), flat(3000, 100, 30));
    const result = sanitizeMacroV2(raw, multiSnapshot(), context(ALL_WEEKS.slice(0, 2)));

    expect(result.plan.weeks[0].sports.map((entry) => entry.amount)).toEqual([3350, 85, 0]);
    expect(result.plan.weeks[0].focus).toBe("Training fortführen");
  });

  describe("gefaehrliche Plaene", () => {
    it("begrenzt die erste Woche und das Wachstum auf 10 % ueber der letzten Woche ohne Entlastung", () => {
      const raw = macroPlan(ALL_WEEKS.slice(0, 4), (index) => ({ swim: 4000 + index * 1000, bike: 200, run: 30 + index * 30 }));
      const result = sanitizeMacroV2(raw, multiSnapshot(), context(ALL_WEEKS.slice(0, 4)));

      // Woche 4 wird nach drei Belastungswochen Entlastung: 70 % der Woche davor.
      expect(amounts(result.plan, "swim")).toEqual([4000, 4400, 4800, 3350]);
      expect(amounts(result.plan, "bike")).toEqual([120, 130, 140, 95]);
      // Laufen ohne Verlauf: Bezug ist mindestens die kleinste Wochengrenze (60 min), plus 10 %.
      expect(amounts(result.plan, "run")).toEqual([30, 60, 65, 45]);
      expect(result.adjustments).toContain("Woche ab 28.09.: Radfahren von 200 min auf 120 min begrenzt (Grenze für die erste Woche)");
    });

    it("setzt spaetestens nach drei Belastungswochen eine Entlastungswoche mit hoechstens 70 %", () => {
      const raw = macroPlan(ALL_WEEKS.slice(0, 6), flat(3500, 100, 40));
      const result = sanitizeMacroV2(raw, multiSnapshot(), context(ALL_WEEKS.slice(0, 6)));

      expect(result.plan.weeks.map((week) => week.deload)).toEqual([false, false, false, true, false, false]);
      expect(amounts(result.plan, "swim")).toEqual([3500, 3500, 3500, 2450, 3500, 3500]);
      expect(result.adjustments).toContain("Woche ab 19.10.: als Entlastungswoche gesetzt (spätestens nach 3 Belastungswochen)");
    });

    it("erlaubt keine Entlastung in der ersten Woche und nimmt eine gewuenschte spaeter an", () => {
      const raw = macroPlan(ALL_WEEKS.slice(0, 3), flat(3500, 100, 40), (index) => index !== 2);
      const result = sanitizeMacroV2(raw, multiSnapshot(), context(ALL_WEEKS.slice(0, 3)));

      expect(result.plan.weeks.map((week) => week.deload)).toEqual([false, true, false]);
      expect(amounts(result.plan, "swim")).toEqual([3500, 2450, 3500]);
    });

    it("kuerzt die Woche auf die Wochenstunden des Ziels", () => {
      const snapshot = multiSnapshot({ goal: { weekly_hours: 2 } });
      const result = sanitizeMacroV2(macroPlan(ALL_WEEKS.slice(0, 1), flat(4000, 120, 60)), snapshot, context(ALL_WEEKS.slice(0, 1)));

      expect(result.plan.weeks[0].total_minutes).toBeLessThanOrEqual(120);
      expect(result.adjustments).toContain("Woche ab 28.09.: Gesamtumfang von 260 min auf höchstens 120 min gekürzt (Wochenstunden des Ziels)");
    });

    it("passt die Zahl der Einheiten an Umfang, Sportart und Trainingstage an", () => {
      const snapshot = multiSnapshot({ goal: { training_days_per_week: 2 } });
      const raw = macroPlan(ALL_WEEKS.slice(0, 1), flat(1000, 60, 20));
      raw.weeks[0].sports = [
        { sport: "swim", amount: 1000, sessions: 9 },
        { sport: "bike", amount: 60, sessions: 0 },
        { sport: "run", amount: 20, sessions: 3 }
      ];
      const result = sanitizeMacroV2(raw, snapshot, context(ALL_WEEKS.slice(0, 1)));

      // Schwimmen: 1000 m reichen fuer 2 Einheiten; zusammen hoechstens 4 Einheiten an 2 Tagen.
      expect(result.plan.weeks[0].sports.map((entry) => entry.sessions)).toEqual([2, 1, 1]);
    });

    it("hebt einen zu kleinen Umfang auf die kleinste Einheit an und laesst negatives weg", () => {
      const result = sanitizeMacroV2(macroPlan(ALL_WEEKS.slice(0, 1), flat(100, -30, 5)), multiSnapshot(), context(ALL_WEEKS.slice(0, 1)));

      expect(result.plan.weeks[0].sports.map((entry) => [entry.amount, entry.sessions])).toEqual([
        [400, 1],
        [0, 0],
        [15, 1]
      ]);
    });
  });

  describe("Phasen bis zum Ziel", () => {
    it("spitzt einen kurzen Wettkampf eine Woche zu und begrenzt die Zielwoche", () => {
      const snapshot = multiSnapshot({ daysUntilGoal: 40 });
      const weeks = macroWeekStarts(TODAY, "2026-11-09");
      const raw = macroPlan(weeks, (index) => (index === weeks.length - 1 ? { swim: 9000, bike: 300, run: 200 } : { swim: 4000, bike: 120, run: 60 }));
      const result = sanitizeMacroV2(raw, snapshot, { today: TODAY, goalDay: "2026-11-09", weeks });

      expect(result.plan.weeks.map((week) => week.phase)).toEqual(["specific", "specific", "specific", "specific", "specific", "taper", "goal_week"]);
      // Hoehepunkt Schwimmen 4000 m: Zuspitzen 60 %, Zielwoche hoechstens 50 % oder 1,2-mal der Wettkampf.
      expect(amounts(result.plan, "swim").slice(-2)).toEqual([2400, 2000]);
      // Laufen: Hoehepunkt 60 min; Zielwoche hoechstens 1,2-mal 60 min (der Wettkampf selbst).
      expect(amounts(result.plan, "run").slice(-2)).toEqual([35, 70]);
    });

    it("spitzt einen langen Wettkampf zwei Wochen zu", () => {
      const snapshot = multiSnapshot({
        daysUntilGoal: 40,
        goal: { weekly_hours: 20, disciplines: [{ sport: "swim", distance_meters: 3800 }, { sport: "bike", distance_meters: 180_000 }, { sport: "run", distance_meters: 42_195 }] }
      });
      const weeks = macroWeekStarts(TODAY, "2026-11-09");
      const raw = macroPlan(weeks, (index) => (index === weeks.length - 1 ? { swim: 9000, bike: 300, run: 200 } : { swim: 4000, bike: 120, run: 60 }));
      const result = sanitizeMacroV2(raw, snapshot, { today: TODAY, goalDay: "2026-11-09", weeks });

      expect(result.plan.weeks.slice(-3).map((week) => week.phase)).toEqual(["taper", "taper", "goal_week"]);
      expect(amounts(result.plan, "swim").slice(-3)).toEqual([3000, 2200, 4550]);
    });

    it("plant nach dem Ziel erhaltend und ohne Pflicht-Entlastung", () => {
      const snapshot = multiSnapshot({ daysUntilGoal: -10 });
      const weeks = ALL_WEEKS.slice(0, 5);
      const result = sanitizeMacroV2(macroPlan(weeks, flat(3500, 100, 40)), snapshot, { today: TODAY, goalDay: "2026-09-20", weeks });

      expect(result.plan.weeks.every((week) => week.phase === "maintain" && !week.deload)).toBe(true);
    });
  });

  describe("Leistungstests", () => {
    it("setzt die Termine selbst: Einstieg ohne bestaetigten Wert, Wiederholung nach dem Intervall", () => {
      const result = sanitizeMacroV2(macroPlan(ALL_WEEKS.slice(0, 8), flat(3500, 100, 40)), multiSnapshot(), context());
      const tests = result.plan.weeks.map((week) => week.tests.map((test) => `${test.sport} ${test.test_id}`));

      // Laufen ist im Wiedereinstieg: der lockere Test (30 min) passt erst in der Woche danach.
      expect(tests[0]).toEqual(["bike threshold_30min"]);
      expect(tests[1]).toEqual(["run entry_easy_25min"]);
      expect(tests[4]).toEqual(["swim css_400_200"]);
      expect(result.plan.weeks[0].tests[0].display_name).toBe("30-Minuten-Test");
    });

    it("plant keine Tests, wenn der Athlet sie abgeschaltet hat", () => {
      const result = sanitizeMacroV2(macroPlan(ALL_WEEKS.slice(0, 8), flat(3500, 100, 40)), multiSnapshot(), context(undefined, { testSettings: { offer: false } }));

      expect(result.plan.weeks.every((week) => week.tests.length === 0)).toBe(true);
    });
  });

  it("nennt hoechstens 12 Korrekturen und haengt einen Hinweis an die Begruendung", () => {
    const raw = macroPlan(ALL_WEEKS.slice(0, 8), (index) => ({ swim: 9000 + index, bike: 400, run: 300 }));
    const result = sanitizeMacroV2(raw, multiSnapshot(), context());

    expect(result.adjustments.at(-1)).toMatch(/^… und \d+ weitere Korrekturen am Umfang$/);
    expect(result.plan.rationale).toMatch(/Hinweis: Zur Sicherheit an \d+ Stellen angepasst, die Wochen zeigen die geprüften Umfänge\.$/);
  });

  it("spricht bei einer einzigen Korrektur von einer Stelle", () => {
    const result = sanitizeMacroV2(macroPlan(ALL_WEEKS.slice(0, 1), flat(5000, 100, 30)), multiSnapshot(), context(ALL_WEEKS.slice(0, 1)));

    expect(result.plan.rationale).toContain("an 1 Stelle angepasst");
  });
});
