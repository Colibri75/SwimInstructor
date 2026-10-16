/**
 * Sprache der App (docs/uebersetzungen.md): Die App schickt ihre Sprache im Header `X-App-Language` mit. Claude schreibt
 * alle Texte, die der Athlet liest, in dieser Sprache; die Prompts selbst bleiben deutsch. Ohne Header (ältere Apps)
 * bleibt alles deutsch.
 */
export const LANGUAGES = ["de", "en", "fr", "es", "it", "pt-BR", "zh-Hans", "ja", "ko", "hi"] as const;
export type Language = (typeof LANGUAGES)[number];

export const LANGUAGE_HEADER = "x-app-language";

/** Name der Sprache für den Prompt, deutsch mit Eigenbezeichnung. */
const NAMES: Record<Language, string> = {
  de: "Deutsch",
  en: "Englisch (English)",
  fr: "Französisch (français)",
  es: "Spanisch (español)",
  it: "Italienisch (italiano)",
  "pt-BR": "brasilianischem Portugiesisch (português do Brasil)",
  "zh-Hans": "vereinfachtem Chinesisch (简体中文)",
  ja: "Japanisch (日本語)",
  ko: "Koreanisch (한국어)",
  hi: "Hindi (हिन्दी)"
};

/** Feste Texte, die der Server selbst in einen Plan schreibt. Gleiche Wörter wie in der App (Localization/). */
interface ServerTexts {
  noTime: string;
  restDay: string;
  easyInsteadOfTest: string;
}

const TEXTS: Record<Language, ServerTexts> = {
  de: { noTime: "Keine Zeit", restDay: "Ruhetag", easyInsteadOfTest: "Locker statt Leistungstest" },
  en: { noTime: "No time", restDay: "Rest day", easyInsteadOfTest: "Easy instead of test" },
  fr: { noTime: "Pas le temps", restDay: "Jour de repos", easyInsteadOfTest: "Facile au lieu du test" },
  es: { noTime: "Sin tiempo", restDay: "Día de descanso", easyInsteadOfTest: "Suave en lugar del test" },
  it: { noTime: "Niente tempo", restDay: "Giorno di riposo", easyInsteadOfTest: "Leggero invece del test" },
  "pt-BR": { noTime: "Sem tempo", restDay: "Dia de descanso", easyInsteadOfTest: "Leve em vez do teste" },
  "zh-Hans": { noTime: "没时间", restDay: "休息日", easyInsteadOfTest: "以轻松训练代替测试" },
  ja: { noTime: "時間なし", restDay: "休養日", easyInsteadOfTest: "テストの代わりに軽め" },
  ko: { noTime: "시간 없음", restDay: "휴식일", easyInsteadOfTest: "테스트 대신 가볍게" },
  hi: { noTime: "समय नहीं", restDay: "आराम का दिन", easyInsteadOfTest: "टेस्ट की जगह हल्का" }
};

/** Die Sprache aus dem Header; ohne Header Deutsch, eine unbekannte wie in der App Englisch. */
export function languageFrom(header: string | undefined): Language {
  const value = header?.split(",")[0]?.split(";")[0]?.trim();
  if (value === undefined || value === "") return "de";
  const exact = LANGUAGES.find((language) => language.toLowerCase() === value.toLowerCase());
  if (exact !== undefined) return exact;
  const base = value.split(/[-_]/)[0]!.toLowerCase();
  return LANGUAGES.find((language) => language.split("-")[0]!.toLowerCase() === base) ?? "en";
}

export function serverTexts(language: Language = "de"): ServerTexts {
  return TEXTS[language];
}

/** Der System-Prompt in der Sprache des Athleten: unverändert auf Deutsch, sonst mit Sprachanweisung am Ende. */
export function inLanguage(system: string, language: Language = "de"): string {
  if (language === "de") return system;
  const name = NAMES[language];
  const texts = TEXTS[language];
  return `${system.replaceAll("auf Deutsch", `auf ${name}`)}

Sprache: Der Athlet nutzt die App auf ${name}. Schreibe jeden Text, den er liest (Begründungen, Hinweise, Schwerpunkte, Namen und Beschreibungen von Übungen, Anweisungen und Kurztexte für die Uhr, Bilanz und Änderungen), auf ${name}, auch wo das Ausgabeformat "auf Deutsch" sagt. Die Nutzernachricht ist auf Deutsch; Kennungen und Werte im JSON (sport, session_type, intensity, Zieltypen) bleiben genau wie vorgegeben. Wo die Regeln den Schwerpunkt "Keine Zeit" verlangen, schreibst du "${texts.noTime}".`;
}
