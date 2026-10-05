import { estimateCostUsd, SESSION_TYPE_LABEL } from "../../src/plan/report";
import { formatChecks } from "../../src/plan/evaluation";
import { SESSION_TYPES } from "../../src/plan/vocabulary";

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

describe("SESSION_TYPE_LABEL", () => {
  it("nennt jeden Einheitentyp auf Deutsch, nie den Schluessel des Schemas", () => {
    for (const type of SESSION_TYPES) expect(SESSION_TYPE_LABEL[type]).not.toBe(type);
    expect(SESSION_TYPE_LABEL.technique).toBe("Technik");
    expect(SESSION_TYPE_LABEL.intervals).toBe("Intervalle");
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
