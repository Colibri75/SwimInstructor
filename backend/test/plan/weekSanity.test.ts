import { sanitizeWeek, weekLimits } from "../../src/plan/weekSanity";
import { WeekDay, WeekPlan } from "../../src/plan/week";
import { snapshot } from "./fixtures";
import { ALL_DATES, context, day, goodWeek, rest, TODAY } from "./weekFixtures";

const total = (days: WeekDay[]): number => days.reduce((sum, d) => sum + d.target_distance_meters, 0);
const byDate = (plan: WeekPlan, date: string): WeekDay => plan.days.find((d) => d.date === date)!;

describe("weekLimits", () => {
  it("deckelt den Umfang beim Zuspitzen unter den Wochenschnitt (85 Prozent bei 8 bis 14 Tagen)", () => {
    const taper = weekLimits(snapshot({ goal: { days_until_goal: 12 }, volume: { average_weekly_meters: 5000 } }), context());

    // 85 % von 5000 m = 4250 m statt 1,3 x 5000 m.
    expect(taper.weeklyRemainingMeters).toBe(4250);
  });

  it("laesst in der Zielwoche den Versuch auf die Zieldistanz zu (mindestens 1,2 x Zieldistanz)", () => {
    const peakWeek = weekLimits(snapshot({ goal: { days_until_goal: 5 }, volume: { average_weekly_meters: 4500 } }), context());
    const lowAverage = weekLimits(snapshot({ goal: { days_until_goal: 5 }, volume: { average_weekly_meters: 2000 } }), context());

    // 70 % von 4500 m = 3150 m, die Zieldistanz 3800 m x 1,2 = 4560 m geht vor.
    expect(peakWeek.weeklyRemainingMeters).toBe(4560);
    // 1,3 x 2000 m = 2600 m, unter 4560 m: Das Zuspitzen hebt die normale Grenze nie an.
    expect(lowAverage.weeklyRemainingMeters).toBe(2600);
  });

  it("wendet das Zuspitzen nur auf die laufende Woche an, nicht auf eine kommende", () => {
    const next = weekLimits(snapshot({ goal: { days_until_goal: 12 }, volume: { average_weekly_meters: 5000 } }), context({ today: "2026-09-25", dates: ALL_DATES }));

    expect(next.weeklyRemainingMeters).toBe(6500);
  });

  it("leitet Einheiten- und Wochengrenze aus dem Zustand ab", () => {
    const limits = weekLimits(snapshot(), context());

    // Laengste Einheit 2000 m x 1,25 = 2500 m, Wochenschnitt 3000 m x 1,3 = 3900 m.
    expect(limits.sessionCapMeters).toBe(2500);
    expect(limits.weeklyRemainingMeters).toBe(3900);
    expect(limits.maxSessions).toBe(5);
    expect(limits.maxHardDays).toBe(2);
    expect(limits.today).not.toBeNull();
  });

  it("zieht schon Geschwommenes ab und zaehlt die Trainingstage mit", () => {
    const limits = weekLimits(snapshot(), context({ swumBefore: [{ date: "2026-09-28", meters: 1200 }, { date: "2026-09-29", meters: 800 }] }));

    expect(limits.weeklyRemainingMeters).toBe(1900);
    expect(limits.maxSessions).toBe(3);
  });

  it("senkt den Wochenumfang bei schlechter Erholung, Umfangsspitze und Trainingspause nur fuer die laufende Woche", () => {
    const poor = weekLimits(snapshot({ recovery: { status: "poor" } }), context());
    const spike = weekLimits(snapshot({ flags: ["volume_spike"] }), context());
    const pause = weekLimits(snapshot({ flags: ["training_pause"] }), context());
    const nextWeek = weekLimits(snapshot({ recovery: { status: "poor" } }), context({ today: "2026-09-25", dates: ALL_DATES }));

    expect(poor.weeklyRemainingMeters).toBe(1950);
    expect(spike.weeklyRemainingMeters).toBe(2340);
    expect(pause.sessionCapMeters).toBe(800);
    expect(pause.weeklyRemainingMeters).toBe(2400);
    expect(nextWeek.weeklyRemainingMeters).toBe(3900);
    expect(nextWeek.today).toBeNull();
  });

  it("laesst nie einen negativen Rest zu", () => {
    const limits = weekLimits(snapshot(), context({ swumBefore: [{ date: "2026-09-28", meters: 9000 }] }));

    expect(limits.weeklyRemainingMeters).toBe(0);
    expect(limits.maxSessions).toBe(4);
  });
});

describe("sanitizeWeek: sinnvolle Wochen bleiben unveraendert", () => {
  it("aendert einen guten Plan nicht", () => {
    const result = sanitizeWeek(goodWeek(), snapshot(), context());

    expect(result.blocked).toBeNull();
    expect(result.adjustments).toEqual([]);
    expect(result.plan.days).toEqual(goodWeek().days);
    expect(result.plan.rationale).toBe(goodWeek().rationale);
  });
});

describe("sanitizeWeek: Tage", () => {
  it("ergaenzt fehlende Tage als Ruhetag und verwirft fremde und doppelte Tage", () => {
    const week = goodWeek({
      days: [day("2026-09-30"), day("2026-09-30", { target_distance_meters: 900 }), day("2026-09-20"), day("2026-10-03", { target_distance_meters: 1000 })]
    });

    const result = sanitizeWeek(week, snapshot(), context());

    expect(result.plan.days.map((d) => d.date)).toEqual(["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"]);
    expect(byDate(result.plan, "2026-09-30").target_distance_meters).toBe(1500);
    expect(byDate(result.plan, "2026-10-01").session_type).toBe("rest");
    expect(result.adjustments[0]).toContain("3 fehlende Tage");
  });

  it("macht Tage ohne Zeit zum Ruhetag", () => {
    const result = sanitizeWeek(goodWeek(), snapshot(), context({ unavailable: ["2026-10-02"] }));

    expect(byDate(result.plan, "2026-10-02")).toMatchObject({ session_type: "rest", intensity: "rest", target_distance_meters: 0, focus: "Keine Zeit" });
    expect(result.adjustments.join(" ")).toContain("keine Zeit");
  });

  it("benennt einen Ruhetag ohne Zeit nur um, ohne Hinweis", () => {
    const result = sanitizeWeek(goodWeek(), snapshot(), context({ unavailable: ["2026-10-01"] }));

    expect(byDate(result.plan, "2026-10-01").focus).toBe("Keine Zeit");
    expect(result.adjustments).toEqual([]);
  });

  it("macht aus Einheiten ohne Strecke, mit Intensitaet rest oder unter einer halben Mindest-Einheit einen Ruhetag", () => {
    const week = goodWeek({
      days: [
        day("2026-09-30", { intensity: "rest", target_distance_meters: 1000 }),
        day("2026-10-01", { target_distance_meters: 0 }),
        day("2026-10-02", { target_distance_meters: 100 }),
        day("2026-10-03", { session_type: "rest", target_distance_meters: 1500 }),
        day("2026-10-04", { target_distance_meters: 1000 })
      ]
    });

    const result = sanitizeWeek(week, snapshot(), context());

    expect(result.plan.days.filter((d) => d.session_type === "rest")).toHaveLength(4);
    expect(result.plan.days.every((d) => (d.session_type === "rest") === (d.target_distance_meters === 0))).toBe(true);
    expect(result.adjustments.join(" ")).toContain("unter 400 m");
  });

  it("hebt eine zu kleine Einheit auf 400 m an, statt sie zu streichen, und sagt es", () => {
    const week = goodWeek({ days: [day("2026-09-30", { target_distance_meters: 250 }), rest("2026-10-01"), day("2026-10-02", { target_distance_meters: 150 })] });

    const result = sanitizeWeek(week, snapshot(), context());

    expect(byDate(result.plan, "2026-09-30").target_distance_meters).toBe(400);
    expect(byDate(result.plan, "2026-10-02").session_type).toBe("rest");
    expect(result.adjustments.join(" ")).toContain("von 250 m auf 400 m angehoben");
  });

  it("rundet Strecken auf 50 m und begrenzt Dauer und Schwerpunkt", () => {
    const week = goodWeek({
      days: [day("2026-09-30", { target_distance_meters: 1510, estimated_duration_minutes: 900, focus: "  " + "x".repeat(200) + "  " })]
    });

    const result = sanitizeWeek(week, snapshot(), context());

    const monday = byDate(result.plan, "2026-09-30");
    expect(monday.target_distance_meters).toBe(1500);
    expect(monday.estimated_duration_minutes).toBe(180);
    expect(monday.focus).toHaveLength(80);
  });

  it("gibt einem leeren Schwerpunkt einen Namen", () => {
    const result = sanitizeWeek(goodWeek({ days: [day("2026-09-30", { focus: " " }), rest("2026-10-01")] }), snapshot(), context());

    expect(byDate(result.plan, "2026-09-30").focus).toBe("Training");
  });
});

describe("sanitizeWeek: Grenzen fuer heute", () => {
  it("erzwingt einen Ruhetag heute bei Uebertrainingsrisiko", () => {
    const result = sanitizeWeek(goodWeek(), snapshot({ flags: ["overreaching_risk"] }), context());

    expect(byDate(result.plan, TODAY).session_type).toBe("rest");
    expect(result.adjustments.join(" ")).toContain("Ruhetag erzwungen");
  });

  it("senkt die Intensitaet heute nach einer harten Einheit gestern", () => {
    const week = goodWeek({ days: [day(TODAY, { session_type: "intervals", intensity: "hard" }), rest("2026-10-01")] });

    const result = sanitizeWeek(week, snapshot({ load: { days_since_last_hard_session: 1 } }), context());

    expect(byDate(result.plan, TODAY)).toMatchObject({ intensity: "moderate", session_type: "endurance" });
  });

  it("kuerzt heute auf die Tagesgrenze und verwandelt einen Rest unter der Mindest-Einheit in Ruhe", () => {
    const capped = sanitizeWeek(goodWeek({ days: [day(TODAY, { target_distance_meters: 2500, estimated_duration_minutes: 60 })] }), snapshot({ volume: { last_seven_days_meters: 2800 } }), context());
    const exhausted = sanitizeWeek(goodWeek({ days: [day(TODAY)] }), snapshot({ volume: { last_seven_days_meters: 3850 } }), context());

    // Wochengrenze 3900 - 2800 = 1100 m heute.
    expect(byDate(capped.plan, TODAY).target_distance_meters).toBe(1100);
    expect(byDate(capped.plan, TODAY).estimated_duration_minutes).toBeLessThan(60);
    expect(byDate(exhausted.plan, TODAY).session_type).toBe("rest");
  });

  it("wendet die Grenzen fuer heute nicht auf andere Tage an", () => {
    const week = goodWeek({ days: [rest(TODAY), day("2026-10-01", { session_type: "intervals", intensity: "hard" })] });

    const result = sanitizeWeek(week, snapshot({ load: { days_since_last_hard_session: 1 } }), context());

    expect(byDate(result.plan, "2026-10-01").intensity).toBe("hard");
  });

  it("wendet sie nicht an, wenn heute nicht zu den geplanten Tagen gehoert (kommende Woche)", () => {
    const week = goodWeek({ days: ALL_DATES.map((date, index) => (index === 0 ? day(date, { intensity: "hard", session_type: "intervals" }) : rest(date))) });

    const result = sanitizeWeek(week, snapshot({ flags: ["overreaching_risk"] }), context({ today: "2026-09-25", dates: ALL_DATES }));

    expect(byDate(result.plan, "2026-09-28").intensity).toBe("hard");
  });
});

describe("sanitizeWeek: Einheiten und Wochenumfang", () => {
  it("kuerzt eine Einheit ueber dem Einheiten-Limit", () => {
    const week = goodWeek({ days: [day(TODAY, { target_distance_meters: 4000 }), rest("2026-10-01")] });

    const result = sanitizeWeek(week, snapshot({ volume: { last_seven_days_meters: 0 } }), context());

    expect(byDate(result.plan, TODAY).target_distance_meters).toBe(2500);
    expect(result.adjustments.join(" ")).toContain("Grenze pro Einheit");
  });

  it("kuerzt alle Einheiten anteilig, wenn die Woche zu gross ist", () => {
    const week = goodWeek({
      days: [
        day("2026-09-30", { target_distance_meters: 2000 }),
        day("2026-10-02", { target_distance_meters: 2000 }),
        day("2026-10-04", { target_distance_meters: 2000 }),
        rest("2026-10-01"),
        rest("2026-10-03")
      ]
    });

    const result = sanitizeWeek(week, snapshot({ volume: { last_seven_days_meters: 0 } }), context());

    expect(total(result.plan.days)).toBeLessThanOrEqual(3900);
    expect(total(result.plan.days)).toBeGreaterThan(3000);
    expect(result.adjustments.join(" ")).toContain("Wochenumfang von 6000 m");
    expect(result.plan.days.every((d) => d.target_distance_meters % 25 === 0)).toBe(true);
  });

  it("macht kleine Reste zu Ruhetagen, wenn kaum Wochenumfang uebrig ist", () => {
    const result = sanitizeWeek(goodWeek(), snapshot({ volume: { last_seven_days_meters: 0 } }), context({ swumBefore: [{ date: "2026-09-28", meters: 3800 }] }));

    expect(total(result.plan.days)).toBe(0);
    expect(result.plan.days.every((d) => d.session_type === "rest")).toBe(true);
  });

  it("zaehlt schon geschwommene Tage zu den hoechstens fuenf Einheiten", () => {
    const week = goodWeek({
      days: [day("2026-09-30", { target_distance_meters: 400 }), day("2026-10-01", { target_distance_meters: 600 }), day("2026-10-02", { target_distance_meters: 800 }), rest("2026-10-03"), rest("2026-10-04")]
    });

    const result = sanitizeWeek(
      week,
      snapshot({ volume: { last_seven_days_meters: 0 } }),
      context({ swumBefore: [{ date: "2026-09-28", meters: 300 }, { date: "2026-09-29", meters: 300 }, { date: "2026-09-27", meters: 0 }] })
    );

    // 2 Tage schon geschwommen: Es bleiben 3 Einheiten, alle drei Tage sind erlaubt.
    expect(result.plan.days.filter((d) => d.session_type !== "rest")).toHaveLength(3);

    const crowded = sanitizeWeek(
      week,
      snapshot({ volume: { last_seven_days_meters: 0 } }),
      context({ swumBefore: [{ date: "2026-09-28", meters: 300 }, { date: "2026-09-29", meters: 300 }, { date: "2026-09-27", meters: 300 }] })
    );
    // 3 Tage geschwommen: Es bleiben 2, die kuerzeste Einheit wird zum Ruhetag.
    expect(crowded.plan.days.filter((d) => d.session_type !== "rest")).toHaveLength(2);
    expect(byDate(crowded.plan, "2026-09-30").session_type).toBe("rest");
    expect(crowded.adjustments.join(" ")).toContain("höchstens 5 Einheiten");
  });
});

describe("sanitizeWeek: harte Tage und Ruhetage", () => {
  const hard = (date: string, meters = 1500): WeekDay => day(date, { session_type: "intervals", intensity: "hard", target_distance_meters: meters });

  it("senkt eine harte Einheit direkt nach einer harten", () => {
    const week = goodWeek({ days: [hard("2026-10-01"), hard("2026-10-02"), rest("2026-10-03")] });

    const result = sanitizeWeek(week, snapshot({ volume: { last_seven_days_meters: 0 } }), context());

    expect(byDate(result.plan, "2026-10-01").intensity).toBe("hard");
    expect(byDate(result.plan, "2026-10-02")).toMatchObject({ intensity: "moderate", session_type: "endurance" });
    expect(result.adjustments.join(" ")).toContain("nicht an zwei Tagen nacheinander");
  });

  it("erlaubt hoechstens zwei harte Tage", () => {
    const week = goodWeek({ days: [hard("2026-09-30", 1000), hard("2026-10-02", 1000), hard("2026-10-04", 1000), rest("2026-10-01")] });

    const result = sanitizeWeek(week, snapshot({ volume: { last_seven_days_meters: 0 } }), context());

    expect(result.plan.days.filter((d) => d.intensity === "hard")).toHaveLength(2);
    expect(byDate(result.plan, "2026-10-04").intensity).toBe("moderate");
    expect(result.adjustments.join(" ")).toContain("höchstens zwei harte Tage");
  });

  it("laesst nach einer gesenkten harten Einheit die naechste harte zu", () => {
    const week = goodWeek({ days: [hard("2026-10-01", 1000), hard("2026-10-02", 1000), hard("2026-10-03", 1000), rest("2026-10-04")] });

    const result = sanitizeWeek(week, snapshot({ volume: { last_seven_days_meters: 0 } }), context());

    // Do hart, Fr gesenkt, Sa wieder hart: Das sind zwei harte Tage, nicht nacheinander.
    expect(result.plan.days.filter((d) => d.intensity === "hard").map((d) => d.date)).toEqual(["2026-10-01", "2026-10-03"]);
  });

  it("verlangt in einer vollen Woche mindestens einen Ruhetag", () => {
    const full = goodWeek({ days: ALL_DATES.map((date, index) => day(date, { target_distance_meters: 500 + index * 100, intensity: "easy" })) });

    const result = sanitizeWeek(full, snapshot({ volume: { last_seven_days_meters: 0 }, load: {} }), context({ today: "2026-09-25", dates: ALL_DATES }));

    expect(result.plan.days.filter((d) => d.session_type === "rest").length).toBeGreaterThanOrEqual(1);
    expect(result.adjustments.join(" ")).toMatch(/Ruhetag/);
  });

  it("verlangt in einer Rest-Woche keinen Ruhetag", () => {
    const short = goodWeek({ days: [day("2026-10-03", { target_distance_meters: 800 }), day("2026-10-04", { target_distance_meters: 800 })] });

    const result = sanitizeWeek(short, snapshot({ volume: { last_seven_days_meters: 0 } }), context({ dates: ["2026-10-03", "2026-10-04"], today: "2026-10-03" }));

    expect(result.plan.days.every((d) => d.session_type !== "rest")).toBe(true);
  });
});

describe("sanitizeWeek: Begruendung und unbrauchbare Plaene", () => {
  it("haengt die Korrekturen an die Begruendung", () => {
    const result = sanitizeWeek(goodWeek(), snapshot({ flags: ["overreaching_risk"] }), context());

    expect(result.plan.rationale).toContain(goodWeek().rationale);
    expect(result.plan.rationale).toContain("Hinweis: Zur Sicherheit angepasst");
    expect(result.plan.rationale.length).toBeLessThanOrEqual(1200);
  });

  it("kuerzt eine zu lange Begruendung samt Hinweis auf die Maximallaenge", () => {
    const result = sanitizeWeek(goodWeek({ rationale: "x".repeat(5000) }), snapshot({ flags: ["overreaching_risk"] }), context());

    expect(result.plan.rationale.length).toBeLessThanOrEqual(1200);
    expect(result.plan.rationale).toContain("Hinweis: Zur Sicherheit angepasst");
  });

  it.each([
    ["ohne Begruendung", goodWeek({ rationale: "  " })],
    ["ohne Tage", goodWeek({ days: [] })],
    ["mit Unsinnszahl", goodWeek({ days: [day(TODAY, { target_distance_meters: Number.NaN })] })],
    ["mit negativem Umfang", goodWeek({ days: [day(TODAY, { target_distance_meters: -5 })] })],
    ["mit absurdem Umfang", goodWeek({ days: [day(TODAY, { target_distance_meters: 99_000 })] })],
    ["mit zu vielen Tagen", goodWeek({ days: Array.from({ length: 15 }, () => day(TODAY)) })]
  ])("blockt einen Plan %s", (_name, plan) => {
    expect(sanitizeWeek(plan, snapshot(), context()).blocked).not.toBeNull();
  });
});
