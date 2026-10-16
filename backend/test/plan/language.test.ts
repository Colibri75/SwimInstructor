import { inLanguage, languageFrom, serverTexts } from "../../src/plan/language";
import { withNote } from "../../src/plan/multi/weekSanity";
import { say, sportText } from "../../src/plan/multi/texts";

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

  it("nennt die Korrekturen in der Sprache der App", () => {
    const note = say("dropped", sportText("run"), say("todayCap"));
    expect(withNote("Gut.", [note])).toBe("Gut. Hinweis: Zur Sicherheit angepasst (Laufen gestrichen (Grenze für heute)).");
    expect(withNote("Good.", [note], "en")).toBe("Good. Note: adjusted for safety (Running removed (today's limit)).");
    expect(withNote("Good.", [], "en")).toBe("Good.");
  });
});
