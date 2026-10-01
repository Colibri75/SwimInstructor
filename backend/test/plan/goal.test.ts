import { assessGoal, goalSection } from "../../src/plan/goal";
import { buildUserMessage, SYSTEM_PROMPT } from "../../src/plan/prompt";
import { buildWeekUserMessage, WEEK_SYSTEM_PROMPT } from "../../src/plan/weekPrompt";
import { snapshot } from "./fixtures";
import { context } from "./weekFixtures";

describe("Gesamtziel: Einordnung", () => {
  it.each([
    [400, "base"],
    [85, "base"],
    [84, "specific"],
    [15, "specific"],
    [14, "taper"],
    [8, "taper"],
    [7, "peak_week"],
    [1, "peak_week"],
    [0, "past"]
  ])("%i Tage bis zum Ziel: Phase %s", (days, phase) => {
    expect(assessGoal(snapshot({ goal: { days_until_goal: days } })).phase).toBe(phase);
  });

  it("rechnet Wochen, Anteil der laengsten Einheit und den Aufbau bis zur Zieldistanz", () => {
    // Laengste Einheit 2000 m, Ziel 3800 m: ln(1,9) / ln(1,1) = 6,7 -> 7 Wochen.
    const a = assessGoal(snapshot({ goal: { days_until_goal: 277 } }));

    expect(a.weeksLeft).toBe(40);
    expect(a.longestPercent).toBe(53);
    expect(a.weeksNeededForDistance).toBe(7);
    expect(a.distanceReachableSafely).toBe(true);
  });

  it("erkennt ein Ziel, das in der Restzeit nicht sicher erreichbar ist", () => {
    // 10 km, laengste Einheit 1000 m, noch 4 Wochen: ln(10) / ln(1,1) = 24,2 -> 25 Wochen.
    const a = assessGoal(snapshot({ goal: { distance_meters: 10_000, days_until_goal: 28 }, volume: { longest_session_meters: 1000 } }));

    expect(a.weeksNeededForDistance).toBe(25);
    expect(a.distanceReachableSafely).toBe(false);
  });

  it("braucht keinen Aufbau, wenn die Zieldistanz schon geschwommen wird, und behandelt 0 m als 100 m", () => {
    expect(assessGoal(snapshot({ volume: { longest_session_meters: 4000 } })).weeksNeededForDistance).toBe(0);
    expect(assessGoal(snapshot({ volume: { longest_session_meters: 0 } })).weeksNeededForDistance).toBeGreaterThan(30);
  });
});

describe("Gesamtziel: Text fuer den Prompt", () => {
  it("nennt Distanz, Zielzeit, Zielpace, Tag, Phase und den Stand", () => {
    const text = goalSection(snapshot({ goal: { distance_meters: 5000, target_duration_seconds: 6000, target_pace_seconds_per_hundred_meters: 120, target_date: "2027-03-14T12:00:00Z", days_until_goal: 165 } }));

    expect(text).toContain("5000 m in 100 min (Zielpace 2:00 pro 100 m), am 2027-03-14");
    expect(text).toContain("Noch 165 Tage (24 Wochen)");
    expect(text).toContain("Längste Einheit der letzten 4 Wochen: 2000 m (40 % der Zieldistanz)");
    expect(text).toContain("Phase: Aufbauphase");
    expect(text).not.toContain("Realismus");
  });

  it("zeigt die Luecke zur Zielpace und sagt, wenn die Zielpace schon erreicht ist", () => {
    expect(goalSection(snapshot({ pace: { gap_to_target_seconds_per_hundred_meters: 25.4 } }))).toContain("25 s pro 100 m langsamer als die Zielpace");
    expect(goalSection(snapshot({ pace: { gap_to_target_seconds_per_hundred_meters: -3 } }))).toContain("schon auf Zielpace oder schneller");
    expect(goalSection(snapshot())).not.toContain("Aktuelle Pace");
  });

  it("formatiert lange Zielzeiten in Stunden", () => {
    expect(goalSection(snapshot({ goal: { distance_meters: 10_000, target_duration_seconds: 10_800 } }))).toContain("10000 m in 3 h 00 min");
  });

  it("warnt ehrlich, wenn das Ziel nicht sicher erreichbar ist, und laesst die Grenzen unberuehrt", () => {
    const text = goalSection(snapshot({ goal: { distance_meters: 10_000, days_until_goal: 28 }, volume: { longest_session_meters: 1000 } }));

    expect(text).toContain("Realismus");
    expect(text).toContain("rund 25 Wochen");
    expect(text).toContain("Die Grenzen hebst du dafür nie auf");
  });

  it("verlangt nach dem Zieltag erhaltendes Training und den Hinweis auf ein neues Ziel", () => {
    const text = goalSection(snapshot({ goal: { days_until_goal: 0 } }));

    expect(text).toContain("Der Zieltag ist heute oder schon vorbei");
    expect(text).toContain("neues Ziel setzen");
    expect(text).not.toContain("Realismus");
  });

  it("nennt Zuspitzen und Zielwoche", () => {
    expect(goalSection(snapshot({ goal: { days_until_goal: 12 } }))).toContain("Zuspitzen");
    expect(goalSection(snapshot({ goal: { days_until_goal: 5 } }))).toContain("Zielwoche");
  });
});

describe("Gesamtziel: Prompts", () => {
  it("steht in der Nutzernachricht des Tages- und des Wochenplans", () => {
    const day = buildUserMessage(snapshot(), "2026-09-30");
    const week = buildWeekUserMessage(snapshot(), context());

    for (const message of [day, week]) {
      expect(message).toContain("Gesamtziel des Athleten");
      expect(message).toContain("3800 m in 60 min");
    }
  });

  it("folgt dem eingestellten Ziel und nicht dem Standard", () => {
    const own = snapshot({ goal: { distance_meters: 1500, target_duration_seconds: 1680, target_pace_seconds_per_hundred_meters: 112 } });

    expect(buildUserMessage(own, "2026-09-30")).toContain("1500 m in 28 min (Zielpace 1:52 pro 100 m)");
    expect(buildWeekUserMessage(own, context())).toContain("1500 m in 28 min");
  });

  it("verlangen im System-Prompt den Bezug zum Ziel und lassen die Grenzen ueber dem Ziel stehen", () => {
    for (const prompt of [SYSTEM_PROMPT, WEEK_SYSTEM_PROMPT]) {
      expect(prompt).toContain('Abschnitt "Gesamtziel"');
      expect(prompt).toMatch(/nie die Grenzen/);
      expect(prompt).toMatch(/Bezug zum Ziel/);
    }
  });

  it("haelt den System-Prompt frei von Zahlen des Ziels (er bleibt fuer alle gleich)", () => {
    expect(SYSTEM_PROMPT).not.toMatch(/3800|60 min|2027/);
    expect(WEEK_SYSTEM_PROMPT).not.toMatch(/3800|60 min|2027/);
  });
});
