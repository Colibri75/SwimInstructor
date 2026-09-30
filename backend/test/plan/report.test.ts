import { estimateCostUsd, formatPlan } from "../../src/plan/report";
import { goodPlan, plan } from "./fixtures";

describe("estimateCostUsd", () => {
  it("rechnet Token mit den Preisen pro Million (Opus 5.5: 4 Dollar ein, 20 Dollar aus)", () => {
    // 1800 * 4 + 2500 * 20 = 7200 + 50000 = 57200 -> 0,0572 Dollar
    expect(estimateCostUsd("claude-opus-5-5", { inputTokens: 1800, outputTokens: 2500 })).toBeCloseTo(0.0572, 6);
  });

  it("Sonnet 5.5 kostet die Haelfte von Opus 5.5", () => {
    const usage = { inputTokens: 1800, outputTokens: 2500 };

    expect(estimateCostUsd("claude-sonnet-5-5", usage)).toBeCloseTo(0.0286, 6);
  });

  it("liefert null bei einem unbekannten Modell", () => {
    expect(estimateCostUsd("claude-unbekannt", { inputTokens: 1, outputTokens: 1 })).toBeNull();
  });
});

describe("formatPlan", () => {
  it("stellt Kopfzeile, Begruendung, Tabelle und Hinweise dar", () => {
    const text = formatPlan(goodPlan);

    expect(text).toContain("**endurance**, moderat, 1600 m, ca. 45 min");
    expect(text).toContain(goodPlan.rationale);
    expect(text).toContain("| Hauptsatz | 6 × 200 m | 140 s/100 m | 30 s |");
    expect(text).toContain("| Einschwimmen | 1 × 200 m | – | 0 s |");
    expect(text).toContain("- Auf lockere Atmung achten.");
  });

  it("laesst bei einem Ruhetag die Tabelle weg", () => {
    const text = formatPlan(plan({ session_type: "rest", intensity: "rest", sets: [], total_distance_meters: 0, coach_notes: [] }));

    expect(text).toContain("Ruhetag");
    expect(text).not.toContain("| Abschnitt |");
  });
});
