import { checkDayPlanAgainstGoal, checkWeekPlanAgainstGoal, formatChecks } from "../../src/plan/evaluation";
import { plan, set, snapshot } from "./fixtures";
import { day, goodWeek, rest } from "./weekFixtures";

const near = { target_pace_seconds_per_hundred_meters: 100 };
const names = (checks: { name: string }[]) => checks.map((c) => c.name);
const byName = (checks: { name: string; ok: boolean }[], name: string) => checks.find((c) => c.name === name);

describe("Tagesplan gegen das Gesamtziel", () => {
  it("verlangt den Bezug zum Ziel in Begruendung oder Hinweisen", () => {
    const without = checkDayPlanAgainstGoal(snapshot(), plan({ rationale: "Locker schwimmen, 2000 m zuletzt.", coach_notes: [] }));
    const inRationale = checkDayPlanAgainstGoal(snapshot(), plan({ rationale: "Das passt zum Ziel von 3800 m." }));
    const inNote = checkDayPlanAgainstGoal(snapshot(), plan({ rationale: "Locker.", coach_notes: ["Das Ziel im Blick behalten."] }));

    expect(byName(without, "Begründung nennt das Ziel")?.ok).toBe(false);
    expect(byName(inRationale, "Begründung nennt das Ziel")?.ok).toBe(true);
    expect(byName(inNote, "Begründung nennt das Ziel")?.ok).toBe(true);
  });

  it("verlangt Ehrlichkeit, wenn das Ziel in der Restzeit nicht sicher erreichbar ist", () => {
    const unrealistic = snapshot({ goal: { distance_meters: 10_000, days_until_goal: 28 }, volume: { longest_session_meters: 1000 } });

    const silent = checkDayPlanAgainstGoal(unrealistic, plan({ rationale: "Ziel im Blick, 1000 m locker." }));
    const honest = checkDayPlanAgainstGoal(unrealistic, plan({ rationale: "Das Ziel ist in vier Wochen nicht ganz erreichbar, wir bauen trotzdem auf." }));

    expect(byName(silent, "Sagt ehrlich, dass das Ziel nicht sicher erreichbar ist")?.ok).toBe(false);
    expect(byName(honest, "Sagt ehrlich, dass das Ziel nicht sicher erreichbar ist")?.ok).toBe(true);
    expect(names(checkDayPlanAgainstGoal(snapshot(), plan()))).not.toContain("Sagt ehrlich, dass das Ziel nicht sicher erreichbar ist");
  });

  it("verlangt nach dem Zieltag erhaltendes Training und den Hinweis auf ein neues Ziel", () => {
    const over = snapshot({ goal: { days_until_goal: 0 } });

    const bad = checkDayPlanAgainstGoal(over, plan({ intensity: "hard", rationale: "Ziel angreifen." }));
    const good = checkDayPlanAgainstGoal(over, plan({ intensity: "easy", rationale: "Ziel erreicht, setze ein neues Ziel in den Einstellungen." }));

    expect(byName(bad, "Erhaltend statt hart (Zieltag vorbei)")?.ok).toBe(false);
    expect(byName(bad, "Weist auf ein neues Ziel hin (Zieltag vorbei)")?.ok).toBe(false);
    expect(byName(good, "Erhaltend statt hart (Zieltag vorbei)")?.ok).toBe(true);
    expect(byName(good, "Weist auf ein neues Ziel hin (Zieltag vorbei)")?.ok).toBe(true);
  });

  it("haelt die Zielwoche kurz und ohne harte Einheit", () => {
    const peak = snapshot({ goal: { days_until_goal: 5 }, volume: { average_weekly_meters: 4500 } });

    const heavy = checkDayPlanAgainstGoal(peak, plan({ intensity: "hard", total_distance_meters: 3000 }));
    const light = checkDayPlanAgainstGoal(peak, plan({ intensity: "easy", total_distance_meters: 1200 }));

    expect(byName(heavy, "Keine harte Einheit in der Zielwoche")?.ok).toBe(false);
    expect(byName(heavy, "Kurze Einheit beim Zuspitzen")?.ok).toBe(false);
    expect(byName(light, "Keine harte Einheit in der Zielwoche")?.ok).toBe(true);
    expect(byName(light, "Kurze Einheit beim Zuspitzen")?.ok).toBe(true);
  });

  it("verlangt in der zielspezifischen Phase bei fordernden Einheiten Abschnitte nahe der Zielpace", () => {
    const specific = snapshot({ goal: { days_until_goal: 60 } });

    const none = checkDayPlanAgainstGoal(specific, plan({ intensity: "moderate", sets: [set()] }));
    const some = checkDayPlanAgainstGoal(specific, plan({ intensity: "moderate", sets: [set({ ...near })] }));
    const easy = checkDayPlanAgainstGoal(specific, plan({ intensity: "easy", sets: [set()] }));

    expect(byName(none, "Zielpace-nahe Abschnitte in der zielspezifischen Phase")?.ok).toBe(false);
    expect(byName(some, "Zielpace-nahe Abschnitte in der zielspezifischen Phase")?.ok).toBe(true);
    expect(names(easy)).not.toContain("Zielpace-nahe Abschnitte in der zielspezifischen Phase");
  });
});

describe("Wochenplan gegen das Gesamtziel", () => {
  it("verlangt den Bezug zum Ziel in der Begruendung", () => {
    expect(byName(checkWeekPlanAgainstGoal(snapshot(), goodWeek({ rationale: "Solide Woche." })), "Begründung nennt das Ziel")?.ok).toBe(false);
    expect(byName(checkWeekPlanAgainstGoal(snapshot(), goodWeek({ rationale: "Aufbau Richtung Ziel." })), "Begründung nennt das Ziel")?.ok).toBe(true);
  });

  it("verlangt beim Zuspitzen einen Umfang unter dem Wochenschnitt und in der Zielwoche keine harte Einheit", () => {
    const peak = snapshot({ goal: { days_until_goal: 5 }, volume: { average_weekly_meters: 3000 } });

    // goodWeek: 3600 m und ein harter Tag.
    const heavy = checkWeekPlanAgainstGoal(peak, goodWeek());
    const light = checkWeekPlanAgainstGoal(
      peak,
      goodWeek({ days: [day("2026-09-30", { intensity: "easy", target_distance_meters: 1000 }), rest("2026-10-01"), day("2026-10-02", { intensity: "easy", target_distance_meters: 800 }), rest("2026-10-03"), rest("2026-10-04")] })
    );

    expect(byName(heavy, "Umfang sinkt beim Zuspitzen")?.ok).toBe(false);
    expect(byName(heavy, "Keine harte Einheit in der Zielwoche")?.ok).toBe(false);
    expect(byName(light, "Umfang sinkt beim Zuspitzen")?.ok).toBe(true);
    expect(byName(light, "Keine harte Einheit in der Zielwoche")?.ok).toBe(true);
  });

  it("verlangt in der zielspezifischen Phase mindestens einen zielspezifischen Tag", () => {
    const specific = snapshot({ goal: { days_until_goal: 60 } });
    const onlyEasy = goodWeek({ days: [day("2026-09-30", { session_type: "endurance", intensity: "easy", focus: "Ausdauer" }), rest("2026-10-01"), rest("2026-10-02"), rest("2026-10-03"), rest("2026-10-04")] });

    expect(byName(checkWeekPlanAgainstGoal(specific, onlyEasy), "Mindestens ein zielspezifischer Tag in der zielspezifischen Phase")?.ok).toBe(false);
    expect(byName(checkWeekPlanAgainstGoal(specific, goodWeek()), "Mindestens ein zielspezifischer Tag in der zielspezifischen Phase")?.ok).toBe(true);
  });
});

describe("formatChecks", () => {
  it("setzt ein Haekchen je bestandener Pruefung", () => {
    const text = formatChecks([
      { name: "A", ok: true, detail: "ja" },
      { name: "B", ok: false, detail: "nein" }
    ]);

    expect(text).toBe("- [x] A: ja\n- [ ] B: nein");
    expect(formatChecks([])).toContain("Keine automatischen Prüfungen");
  });
});
