import { macroLimits, sanitizeMacro } from "../../src/plan/macroSanity";
import { snapshot } from "./fixtures";
import { goodMacro, macroContext, macroWeek, MACRO_WEEKS } from "./macroFixtures";

const targets = (result: ReturnType<typeof sanitizeMacro>) => result.plan.weeks.map((w) => w.target_meters);

describe("Sicherheitsschicht fuer den Gesamtplan", () => {
  it("laesst einen sinnvollen Plan unveraendert und setzt die Phasen selbst", () => {
    const result = sanitizeMacro(goodMacro(), snapshot(), macroContext());

    expect(result.blocked).toBeNull();
    expect(result.adjustments).toEqual([]);
    expect(targets(result)).toEqual([3500, 3800, 4100, 4400, 3700, 3000, 2200]);
    expect(result.plan.weeks.map((w) => w.phase)).toEqual(["specific", "specific", "specific", "specific", "taper", "taper", "goal_week"]);
    expect(result.plan.rationale).toContain("Sechs Wochen");
  });

  it("nennt die Grenzen der ersten Woche aus dem Zustand", () => {
    expect(macroLimits(snapshot(), macroContext()).firstWeekCapMeters).toBe(3900);
    // Schlechte Erholung halbiert die Grenze (wie beim Wochenplan).
    expect(macroLimits(snapshot({ flags: ["recovery_poor"] }), macroContext()).firstWeekCapMeters).toBe(1950);
  });

  it("begrenzt die erste Woche", () => {
    const plan = goodMacro();
    plan.weeks[0] = macroWeek(MACRO_WEEKS[0], { target_meters: 6000 });

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    expect(result.plan.weeks[0].target_meters).toBe(3900);
    expect(result.adjustments[0]).toContain("Woche ab 28.09.: Umfang von 6000 m auf 3900 m begrenzt (Grenze für die erste Woche)");
  });

  it("begrenzt das Wachstum auf etwa 10 Prozent der Woche davor", () => {
    const plan = goodMacro();
    plan.weeks[1] = macroWeek(MACRO_WEEKS[1], { target_meters: 6000 });

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    // 3500 * 1,1 = 3850
    expect(result.plan.weeks[1].target_meters).toBe(3850);
    expect(result.adjustments.join("\n")).toContain("höchstens etwa 10 % mehr als die Woche davor");
  });

  it("haelt eine Entlastungswoche deutlich darunter und waechst danach von der letzten normalen Woche aus", () => {
    const plan = goodMacro();
    plan.weeks[1] = macroWeek(MACRO_WEEKS[1], { target_meters: 3800, deload: true });
    plan.weeks[2] = macroWeek(MACRO_WEEKS[2], { target_meters: 4300 });

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    // Entlastung: hoechstens 85 % von 3500 = 2975, abgerundet 2950. Danach hoechstens 3500 * 1,1 = 3850.
    expect(result.plan.weeks[1]).toMatchObject({ target_meters: 2950, deload: true });
    expect(result.plan.weeks[2].target_meters).toBe(3850);
  });

  it("kennt keine Entlastung in der ersten Woche, beim Zuspitzen und in der Zielwoche", () => {
    const plan = goodMacro();
    for (const index of [0, 4, 5, 6]) plan.weeks[index] = { ...plan.weeks[index], deload: true };

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    expect(result.plan.weeks.map((w) => w.deload)).toEqual([false, false, false, false, false, false, false]);
  });

  it("laesst den Umfang beim Zuspitzen sinken (85 und 70 Prozent des Hoehepunkts)", () => {
    const plan = goodMacro();
    plan.weeks[4] = macroWeek(MACRO_WEEKS[4], { target_meters: 4400 });
    plan.weeks[5] = macroWeek(MACRO_WEEKS[5], { target_meters: 4400 });

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    // Hoehepunkt 4400: 85 % = 3740, abgerundet 3700; 70 % = 3080, abgerundet 3050.
    expect(result.plan.weeks[4].target_meters).toBe(3700);
    expect(result.plan.weeks[5].target_meters).toBe(3050);
    expect(result.adjustments.join("\n")).toContain("Zuspitzen");
  });

  it("haelt die Zielwoche kurz, laesst aber die Zieldistanz zu", () => {
    const plan = goodMacro();
    plan.weeks[5] = macroWeek(MACRO_WEEKS[5], { target_meters: 3000 });
    plan.weeks[6] = macroWeek(MACRO_WEEKS[6], { target_meters: 9000 });

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    // Ohne Zieldistanz waeren 50 % des Hoehepunkts 2200; die Zieldistanz 3800 m (mal 1,2 = 4560) geht vor,
    // darueber greift aber das Wachstum (Woche davor 3000 m, mal 1,1 = 3300).
    expect(result.plan.weeks[6].target_meters).toBeLessThanOrEqual(4550);
    expect(result.plan.weeks[6].target_meters).toBe(3300);
  });

  it("ergaenzt fehlende Wochen mit dem Umfang der Vorwoche und ignoriert unbekannte und doppelte", () => {
    const plan = goodMacro();
    plan.weeks.splice(2, 1);
    plan.weeks.push(macroWeek("2030-01-07", { target_meters: 9999 }), macroWeek(MACRO_WEEKS[0], { target_meters: 100 }));

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    expect(result.plan.weeks.map((w) => w.week_start)).toEqual(MACRO_WEEKS);
    expect(result.plan.weeks[2].target_meters).toBe(3800);
    expect(result.plan.weeks[0].target_meters).toBe(3500);
    expect(result.adjustments[0]).toBe("1 fehlende Wochen mit dem Umfang der Vorwoche ergänzt");
  });

  it("begrenzt die Zahl der Einheiten und die Laenge des Schwerpunkts", () => {
    const plan = goodMacro();
    plan.weeks[0] = macroWeek(MACRO_WEEKS[0], { sessions: 9, focus: `  ${"x".repeat(200)}` });
    plan.weeks[1] = macroWeek(MACRO_WEEKS[1], { sessions: 0 });

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    expect(result.plan.weeks[0].sessions).toBe(5);
    expect(result.plan.weeks[0].focus).toHaveLength(80);
    expect(result.plan.weeks[1].sessions).toBe(2);
  });

  it("plant nicht mehr Einheiten als 200 m je Einheit hergeben", () => {
    const plan = goodMacro();
    plan.weeks[0] = macroWeek(MACRO_WEEKS[0], { target_meters: 450, sessions: 5 });

    const result = sanitizeMacro(plan, snapshot(), macroContext());

    expect(result.plan.weeks[0]).toMatchObject({ target_meters: 450, sessions: 2 });
  });

  it("nennt nach dem Zieltag nur noch Erhalten", () => {
    const result = sanitizeMacro(
      { rationale: "Das Ziel ist erreicht, erhaltendes Training.", weeks: [macroWeek("2026-09-28", { target_meters: 2000 })] },
      snapshot({ goal: { days_until_goal: 0 } }),
      macroContext({ goalDay: "2026-08-01", weeks: ["2026-09-28"] })
    );

    expect(result.blocked).toBeNull();
    expect(result.plan.weeks[0].phase).toBe("maintain");
  });

  it("blockt einen unbrauchbaren Plan", () => {
    expect(sanitizeMacro(goodMacro({ rationale: "  " }), snapshot(), macroContext()).blocked).toBe("Begründung fehlt");
    expect(sanitizeMacro(goodMacro({ weeks: [] }), snapshot(), macroContext()).blocked).toBe("Gesamtplan ohne Wochen");
    const many = goodMacro({ weeks: Array.from({ length: 20 }, () => macroWeek(MACRO_WEEKS[0])) });
    expect(sanitizeMacro(many, snapshot(), macroContext()).blocked).toContain("zu viele Wochen");
    const nan = goodMacro();
    nan.weeks[0] = macroWeek(MACRO_WEEKS[0], { target_meters: Number.NaN });
    expect(sanitizeMacro(nan, snapshot(), macroContext()).blocked).toBe("Zahlenwert in einer Woche ungültig");
  });

  it("fasst viele Korrekturen zusammen", () => {
    const wild = goodMacro({ weeks: MACRO_WEEKS.map((week) => macroWeek(week, { target_meters: 19_000 })) });
    const long = { ...macroContext(), weeks: MACRO_WEEKS };

    const result = sanitizeMacro(wild, snapshot(), long);

    expect(result.adjustments.length).toBeLessThanOrEqual(11);
    const t = targets(result);
    expect(t[0]).toBe(3900);
    // Keine Woche ueber 10 % mehr als die davor (plus eine Rundungsstufe).
    t.slice(1).forEach((value, index) => expect(value).toBeLessThanOrEqual(t[index] * 1.1 + 50));
  });
});
