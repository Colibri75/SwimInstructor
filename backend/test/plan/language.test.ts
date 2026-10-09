import { inLanguage, languageFrom, serverTexts } from "../../src/plan/language";
import { withNote } from "../../src/plan/multi/weekSanity";

describe("Sprache der App", () => {
  it("liest den Header und bleibt ohne ihn deutsch", () => {
    expect(languageFrom(undefined)).toBe("de");
    expect(languageFrom("")).toBe("de");
    expect(languageFrom("en")).toBe("en");
    expect(languageFrom("pt-BR")).toBe("pt-BR");
    expect(languageFrom("pt")).toBe("pt-BR");
    expect(languageFrom("zh-Hans")).toBe("zh-Hans");
    expect(languageFrom("ja-JP;q=0.9")).toBe("ja");
    expect(languageFrom("ru")).toBe("en");
  });

  it("laesst den deutschen Prompt unveraendert und haengt sonst die Sprachanweisung an", () => {
    const system = "Antworte ausschließlich im vorgegebenen JSON-Format und auf Deutsch.";
    expect(inLanguage(system, "de")).toBe(system);
    const english = inLanguage(system, "en");
    expect(english).toContain("auf Englisch (English).");
    expect(english).not.toContain("auf Deutsch.");
    expect(english).toContain(`"${serverTexts("en").noTime}"`);
  });

  it("nennt die Korrekturen nur auf Deutsch einzeln", () => {
    expect(withNote("Gut.", ["Laufen gekürzt"])).toContain("Laufen gekürzt");
    expect(withNote("Good.", ["Laufen gekürzt"], "en")).toBe(`Good. ${serverTexts("en").safetyNote}`);
    expect(withNote("Good.", [], "en")).toBe("Good.");
  });
});
