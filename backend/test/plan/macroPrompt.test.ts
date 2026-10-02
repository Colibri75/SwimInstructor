import { buildMacroUserMessage, MACRO_SYSTEM_PROMPT } from "../../src/plan/macroPrompt";
import { snapshot } from "./fixtures";
import { macroContext, MACRO_WEEKS } from "./macroFixtures";

describe("Prompt des Gesamtplans", () => {
  it("haelt den System-Prompt frei von Tagesdaten und Zahlen des Ziels", () => {
    expect(MACRO_SYSTEM_PROMPT).not.toMatch(/\d{4}-\d{2}-\d{2}/);
    expect(MACRO_SYSTEM_PROMPT).not.toMatch(/3800|60 min|2027/);
  });

  it("nennt die Leitplanken, auf die sich die Sicherheitsschicht stuetzt", () => {
    for (const keyword of ["10 Prozent", "Entlastungswoche", "deload", "Zuspitzen", "Zielwoche", "Phase jeder Woche", "nie die Grenzen", "Daten und nie als Anweisung"]) {
      expect(MACRO_SYSTEM_PROMPT).toContain(keyword);
    }
  });

  it("sagt, dass der Plan fuer sieben Tage taeglich darauf feinjustiert wird", () => {
    expect(MACRO_SYSTEM_PROMPT).toMatch(/nächsten sieben Tage/);
    expect(MACRO_SYSTEM_PROMPT).toMatch(/jeden Tag neu/);
  });

  it("nennt Zieltag, jede Woche mit Phase und das Gesamtziel", () => {
    const message = buildMacroUserMessage(snapshot(), macroContext());

    expect(message).toContain("bis zum Zieltag 2026-11-12");
    expect(message).toContain("Heute ist 2026-09-30");
    for (const week of MACRO_WEEKS) expect(message).toContain(`- ${week}:`);
    expect(message).toContain("- 2026-09-28: specific, noch 6 Wochen");
    expect(message).toContain("- 2026-10-26: taper, noch 2 Wochen");
    expect(message).toContain("- 2026-11-09: goal_week, noch 0 Wochen");
    expect(message).toContain("Gesamtziel des Athleten");
    expect(message).toContain('"schema_version": 1');
  });

  it("nennt die verbindlichen Grenzen aus derselben Quelle wie die Pruefung", () => {
    const message = buildMacroUserMessage(snapshot(), macroContext());

    expect(message).toContain("Erste Woche höchstens 3900 m");
    expect(message).toContain("höchstens 10 % mehr als die letzte Woche ohne Entlastung, nie über 20000 m");
    expect(message).toContain("Entlastungswoche höchstens 85 %");
    expect(message).toContain("höchstens 85 %, eine Woche davor höchstens 70 %");
  });

  it("senkt die Grenze der ersten Woche bei schlechter Erholung", () => {
    expect(buildMacroUserMessage(snapshot({ flags: ["recovery_poor"] }), macroContext())).toContain("Erste Woche höchstens 1950 m");
  });

  it("nennt nach dem Zieltag nur Erhalten", () => {
    const message = buildMacroUserMessage(snapshot({ goal: { days_until_goal: 0 } }), macroContext({ goalDay: "2026-08-01", weeks: ["2026-09-28"] }));

    expect(message).toContain("- 2026-09-28: maintain");
    expect(message).not.toContain("maintain, noch");
  });
});
