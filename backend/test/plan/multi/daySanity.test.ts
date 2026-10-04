import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { asRawDayPlan } from "../../../src/plan/multi/store";
import { SPORTS } from "../../../src/sports/registry";
import { dayPlan, multiSnapshot, RUNNER, session, step, swimStep, TODAY } from "./fixtures";

// Kein harter Tag zuletzt, in den letzten 7 Tagen wenig geschwommen und geradelt: heute ist viel Platz.
const rested = { load: { days_since_last_hard_session: 5 }, sports: { swim: { meters_last_seven_days: 1000 }, bike: { minutes_last_seven_days: 30 } } };
const swimSession = (meters: number[], patch: Parameters<typeof session>[1] = {}) => session("swim", { steps: meters.map((m) => swimStep(m)), ...patch });

describe("sanitizeDayV2", () => {
  it("laesst einen Plan in den Grenzen unveraendert", () => {
    const raw = dayPlan([swimSession([400, 800, 200]), session("bike", { steps: [step({ duration_seconds: 1800, target_type: "heart_rate_zone", target_value: 2 })] })]);
    const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY });

    expect(result.blocked).toBeNull();
    expect(result.adjustments).toEqual([]);
    expect(result.plan.rationale).toBe(raw.rationale);
    expect(result.plan.sessions.map((item) => [item.sport, item.amount, item.unit])).toEqual([
      ["swim", 1400, "meters"],
      ["bike", 30, "minutes"]
    ]);
    expect(result.plan.sessions[1]).toMatchObject({ distance_meters: Math.round((1800 * (39_000 / (85 * 60))) / 50) * 50, duration_minutes: 30, test: null });
  });

  it.each([
    ["ohne Begruendung", dayPlan([], " "), "Begründung fehlt"],
    ["mit zu vielen Einheiten", dayPlan(Array.from({ length: 7 }, () => swimSession([400]))), "zu viele Einheiten (7)"],
    ["mit zu vielen Schritten", dayPlan([swimSession(Array.from({ length: 61 }, () => 100))]), "zu viele Schritte (61)"],
    ["mit unendlichen Zahlen", dayPlan([session("run", { steps: [step({ duration_seconds: Infinity })] })]), "Zahlenwert in einem Schritt ungültig"],
    ["mit negativen Werten", dayPlan([session("run", { steps: [step({ rest_seconds: -5 })] })]), "Schritt mit unmöglichen Werten"]
  ])("blockt einen Plan %s", (_name, raw, reason) => {
    expect(sanitizeDayV2(raw, multiSnapshot(), { date: TODAY }).blocked).toBe(reason);
  });

  it("erzwingt bei Uebertrainingsrisiko einen Ruhetag", () => {
    const result = sanitizeDayV2(dayPlan([swimSession([400])]), multiSnapshot({ flags: ["overreaching_risk"] }), { date: TODAY });

    expect(result.plan.sessions).toEqual([]);
    expect(result.plan.rationale).toContain("Heute ist Ruhe angesagt");
    expect(result.adjustments[0]).toContain("Ruhetag erzwungen");
  });

  it("entfernt Sportarten ohne Schwerpunkt, Ruhe-Einheiten und Einheiten ohne Schritte", () => {
    const snapshot = multiSnapshot({ ...rested, goal: { disciplines: [{ sport: "swim", distance_meters: 1500 }], emphasis: [{ sport: "swim", percent: 100 }] } });
    const raw = dayPlan([session("run"), session("kayak"), swimSession([400], { session_type: "rest" }), swimSession([], {}), swimSession([400, 400])]);
    const result = sanitizeDayV2(raw, snapshot, { date: TODAY });

    expect(result.plan.sessions.map((item) => item.sport)).toEqual(["swim"]);
    expect(result.adjustments).toEqual(["Schwimmen: Einheit ohne Schritte entfernt", "Einheiten von Sportarten ohne Schwerpunkt entfernt (Laufen, kayak)"]);
  });

  it("nimmt eine Einheit mit Ruhe-Intensitaet als Ruhe und setzt einen fehlenden Schwerpunkt", () => {
    const result = sanitizeDayV2(dayPlan([swimSession([400], { intensity: "rest" }), swimSession([400], { focus: " " })]), multiSnapshot(rested), { date: TODAY });

    expect(result.plan.sessions).toHaveLength(1);
    expect(result.plan.sessions[0]).toMatchObject({ intensity: "easy", focus: "Schwimmen" });
  });

  it("kuerzt auf zwei Einheiten, die laengsten bleiben", () => {
    const raw = dayPlan([swimSession([400]), session("bike", { steps: [step({ duration_seconds: 2400 })] }), swimSession([1000])]);
    const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY });

    expect(result.plan.sessions.map((item) => [item.sport, item.amount])).toEqual([
      ["bike", 40],
      ["swim", 1000]
    ]);
    expect(result.adjustments).toContain("Auf 2 Einheiten gekürzt");
  });

  it("kuerzt Schritte auf 20 und entfernt Hilfsmittel, die der Athlet nicht hat", () => {
    const raw = dayPlan([swimSession(Array.from({ length: 25 }, () => 50), {}), swimSession([200], { steps: [swimStep(200, { equipment: ["paddles"] })] })]);
    const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY, equipment: ["fins"] });

    expect(result.plan.sessions[0].steps).toHaveLength(20);
    expect(result.plan.sessions[1].steps[0].equipment).toEqual([]);
    expect(result.adjustments).toEqual(expect.arrayContaining(["Schwimmen: auf 20 Schritte gekürzt", "Hilfsmittel entfernt, die du nicht hast: Paddles"]));
  });

  describe("gefaehrliche Plaene", () => {
    it("kuerzt zu viel Laufumfang fuer einen Laeufer auf 10 % ueber der laengsten Einheit", () => {
      const raw = dayPlan([session("run", { steps: [step({ duration_seconds: 600 }), step({ duration_seconds: 7200 }), step({ duration_seconds: 300 })] })]);
      const result = sanitizeDayV2(raw, multiSnapshot({ ...rested, sports: { run: { ...RUNNER, minutes_last_seven_days: 60 } } }), { date: TODAY });

      // Laengste Einheit 60 min: hoechstens 65 min (Raster 5 min).
      expect(result.plan.sessions[0].amount).toBe(65);
      expect(result.adjustments[0]).toBe("Laufen: Umfang von 135 min auf 65 min gekürzt (Grenze für heute: 65 min)");
    });

    it("laesst einen Laufanfaenger nur kurz und locker laufen", () => {
      const raw = dayPlan([session("run", { intensity: "hard", session_type: "intervals", steps: [step({ duration_seconds: 2400, target_type: "pace_per_km", target_value: 240 })] })]);
      const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY });

      expect(result.plan.sessions[0]).toMatchObject({ intensity: "easy", session_type: "endurance", amount: 20 });
      // Schwellentempo 4:50: nicht schneller als 85 % davon.
      expect(result.plan.sessions[0].steps[0].target_value).toBe(247);
    });

    it("erlaubt nach einem harten Tag auch in einer anderen Sportart keine harte Einheit", () => {
      const raw = dayPlan([session("bike", { intensity: "hard", session_type: "intervals", steps: [step({ duration_seconds: 2400, target_type: "heart_rate_zone", target_value: 5 })] })]);
      const recent = [{ date: "2026-09-29", sport: "run", minutes: 45, meters: 9000, hard: true }];
      const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY, recent });

      expect(result.plan.sessions[0]).toMatchObject({ intensity: "moderate", session_type: "endurance" });
      expect(result.plan.sessions[0].steps[0].target_value).toBe(3);
      expect(result.adjustments[0]).toContain("gestern oder heute schon eine harte Einheit");
    });

    it("erlaubt hoechstens eine harte Einheit am Tag", () => {
      const raw = dayPlan([
        swimSession([400, 1000], { intensity: "hard", session_type: "intervals" }),
        session("bike", { intensity: "hard", session_type: "threshold", steps: [step({ duration_seconds: 2400 })] })
      ]);
      const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY });

      expect(result.plan.sessions.map((item) => item.intensity)).toEqual(["hard", "moderate"]);
      expect(result.adjustments).toContain('Nur eine harte Einheit am Tag, die andere auf "moderate" gesenkt');
    });

    it("halbiert bei schlechter Erholung die Grenze und erlaubt nur locker", () => {
      const raw = dayPlan([swimSession([400, 1600, 200], { intensity: "moderate" })]);
      const result = sanitizeDayV2(raw, multiSnapshot({ ...rested, recovery: { status: "poor" } }), { date: TODAY });

      // Grenze sonst 2500 m pro Einheit, jetzt 1250 m.
      expect(result.plan.sessions[0]).toMatchObject({ intensity: "easy", amount: 1250 });
    });

    it("kuerzt einen zu langen Tag ueber alle Sportarten auf die Haelfte der Wochenstunden", () => {
      const snapshot = multiSnapshot({ ...rested, goal: { weekly_hours: 2 }, sports: { ...rested.sports, bike: { longest_session_minutes: 200, average_weekly_minutes: 300, minutes_last_seven_days: 30 } } });
      const raw = dayPlan([session("bike", { steps: [step({ duration_seconds: 2 * 3600 })] }), swimSession([1000])]);
      const result = sanitizeDayV2(raw, snapshot, { date: TODAY });
      const minutes = result.plan.sessions.reduce((sum, item) => sum + item.duration_minutes, 0);

      expect(minutes).toBeLessThanOrEqual(60);
      expect(result.adjustments).toContain("Tagesumfang von 140 min auf höchstens 60 min gekürzt");
    });

    it("streicht eine Sportart, deren Wochenumfang ausgeschoepft ist", () => {
      const result = sanitizeDayV2(dayPlan([swimSession([400])]), multiSnapshot({ ...rested, sports: { swim: { meters_last_seven_days: 4300 } } }), { date: TODAY });

      expect(result.plan.sessions).toEqual([]);
      expect(result.adjustments).toEqual(["Schwimmen gestrichen (Wochenumfang ausgeschöpft)"]);
      expect(result.plan.rationale).toContain("passen heute nicht in die Grenzen");
    });

    it("streicht eine Einheit, von der nach dem Kuerzen zu wenig bleibt", () => {
      // Heute noch 450 m: von 4 x 300 m bleibt 1 x 300 m, die kleinste Einheit sind 400 m.
      const raw = dayPlan([swimSession([], { steps: [swimStep(300, { repetitions: 4 })] })]);
      const result = sanitizeDayV2(raw, multiSnapshot({ ...rested, sports: { swim: { meters_last_seven_days: 3900 } } }), { date: TODAY });

      expect(result.plan.sessions).toEqual([]);
      expect(result.adjustments).toEqual(["Schwimmen gestrichen (zu wenig sicherer Restumfang)"]);
    });
  });

  describe("Leistungstests", () => {
    const fresh = multiSnapshot({ ...rested, sports: { ...rested.sports, run: RUNNER } });
    const testSession = (sport: string, testId: string | null) => session(sport, { session_type: "test", intensity: "hard", test_id: testId, steps: [] });

    it("setzt die Schritte des Moduls ein", () => {
      const result = sanitizeDayV2(dayPlan([testSession("bike", "threshold_30min")]), fresh, { date: TODAY });

      expect(result.plan.sessions[0]).toMatchObject({ session_type: "test", intensity: "hard", focus: "30-Minuten-Test", amount: 58 });
      expect(result.plan.sessions[0].test).toMatchObject({ id: "threshold_30min", maximal_effort: true });
      expect(result.plan.sessions[0].steps).toEqual(SPORTS.get("bike")?.planning.testSessions.threshold_30min);
      expect(result.adjustments).toEqual([]);
    });

    it("nimmt den bevorzugten Test, wenn Claude keinen nennt, und den lockeren, wenn hart nicht geht", () => {
      const preferred = sanitizeDayV2(dayPlan([testSession("swim", null)]), fresh, { date: TODAY, testSettings: { preferred: [{ sport: "swim", test_id: "time_trial_1000m" }] } });
      const easy = sanitizeDayV2(dayPlan([testSession("run", "threshold_30min")]), multiSnapshot({ ...rested, recovery: { status: "moderate" }, sports: { ...rested.sports, run: RUNNER } }), { date: TODAY });

      expect(preferred.plan.sessions[0].test?.id).toBe("time_trial_1000m");
      expect(easy.plan.sessions[0]).toMatchObject({ intensity: "easy", test: { id: "entry_easy_25min", maximal_effort: false } });
    });

    it.each([
      ["abgeschaltet", { testSettings: { offer: false } }, rested, "Leistungstests sind abgeschaltet"],
      ["kurz vor dem Ziel", {}, { ...rested, daysUntilGoal: 10 }, "kein Test in den letzten 14 Tagen vor dem Ziel"],
      ["nach einem harten Tag", {}, {}, 'keine Vollbelastung (gestern oder heute schon eine harte Einheit)']
    ])("macht aus einem Test eine lockere Einheit: %s", (_name, options, patch, reason) => {
      const raw = dayPlan([session("bike", { session_type: "test", intensity: "hard", test_id: "threshold_30min", steps: [step({ duration_seconds: 3000 })] })]);
      const result = sanitizeDayV2(raw, multiSnapshot(patch), { date: TODAY, ...options });

      expect(result.plan.sessions[0]).toMatchObject({ session_type: "endurance", intensity: "easy", test: null, focus: "Locker statt Leistungstest" });
      expect(result.adjustments[0]).toContain(reason);
    });

    it("plant einen Laufanfaenger ohne Grundlage nicht in einen Test mit Vollbelastung", () => {
      const result = sanitizeDayV2(dayPlan([testSession("run", "threshold_30min")]), multiSnapshot(rested), { date: TODAY });

      // Wiedereinstieg: hoechstens 20 min, der lockere Test hat 30 min.
      expect(result.plan.sessions).toEqual([]);
      expect(result.adjustments[0]).toBe("Kein Leistungstest Laufen heute (30-Minuten-Test: keine Vollbelastung (Wiedereinstieg nach Pause)), lockere Einheit statt dessen");
    });

    it("erlaubt hoechstens einen Test am Tag und laesst ihm die harte Einheit", () => {
      const raw = dayPlan([session("bike", { intensity: "hard", session_type: "intervals", steps: [step({ duration_seconds: 2400 })] }), testSession("swim", "css_400_200"), testSession("run", null)]);
      const result = sanitizeDayV2(raw, fresh, { date: TODAY });
      const tests = result.plan.sessions.filter((item) => item.test !== null);

      expect(tests).toHaveLength(1);
      expect(result.plan.sessions.filter((item) => item.intensity === "hard")).toEqual(tests);
    });

    it("prueft einen gespeicherten Plan mit Test erneut, ohne den Test zu verlieren", () => {
      const first = sanitizeDayV2(dayPlan([testSession("bike", "threshold_30min")]), fresh, { date: TODAY });
      const again = sanitizeDayV2(asRawDayPlan(first.plan), fresh, { date: TODAY });

      expect(again.plan.sessions).toEqual(first.plan.sessions);
    });
  });

  it("passt Zielwerte an und nennt das nur in den Korrekturen, nicht in der Begruendung", () => {
    const raw = dayPlan([swimSession([400], { steps: [swimStep(400, { target_type: "pace_per_100m", target_value: 50 })] })]);
    const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY });

    expect(result.adjustments).toEqual(["Zielwerte an die Grenzen für dich und die Intensität angepasst"]);
    expect(result.plan.rationale).toBe(raw.rationale);
  });

  it("kuerzt Hinweise und Begruendung", () => {
    const raw = { ...dayPlan([swimSession([400])], "x".repeat(2000)), coach_notes: ["a", " ", "b".repeat(400), "c", "d", "e", "f"] };
    const result = sanitizeDayV2(raw, multiSnapshot(rested), { date: TODAY });

    expect(result.plan.coach_notes).toEqual(["a", "b".repeat(300), "c", "d", "e"]);
    expect(result.plan.rationale.length).toBeLessThanOrEqual(1200);
  });
});
