import { Language } from "../../language";
import { SPORTS } from "../../../sports/registry";
import { SafetyCatalog } from "./catalog";
import { de } from "./de";
import { en } from "./en";
import { fr } from "./fr";
import { es } from "./es";
import { it } from "./it";
import { ptBR } from "./pt-BR";
import { zhHans } from "./zh-Hans";
import { ja } from "./ja";
import { ko } from "./ko";
import { hi } from "./hi";

export type { SafetyCatalog } from "./catalog";
export { intlDate, intlList } from "./catalog";

/**
 * Die Texte der Sicherheitsschicht (die Liste "Zur Sicherheit angepasst" unter einem Plan und die Gruende darin) in
 * jeder Sprache der App. Die Schicht rechnet mit `Text` statt mit fertigen Saetzen; erst das Ergebnis wird in der
 * Sprache der App geschrieben. `toString()` liefert Deutsch: So bleiben Prompts, Logs und Auswertungen deutsch.
 */
export class Text {
  constructor(private readonly render: (language: Language) => string) {}

  in(language: Language = "de"): string {
    return this.render(language);
  }

  toString(): string {
    return this.render("de");
  }

  toJSON(): string {
    return this.toString();
  }
}

export const CATALOGS: Record<Language, SafetyCatalog> = {
  de,
  en,
  fr,
  es,
  it,
  "pt-BR": ptBR,
  "zh-Hans": zhHans,
  ja,
  ko,
  hi
};

type Message = { [K in keyof SafetyCatalog]: SafetyCatalog[K] extends (...args: never[]) => string ? K : never }[keyof SafetyCatalog];
type Arg<T> = T extends string ? string | Text : T;
type Args<F> = F extends (...args: infer P) => string ? { [I in keyof P]: Arg<P[I]> } : never;

/** Ein Satz aus dem Katalog; eingesetzte `Text`e werden in derselben Sprache geschrieben. */
export function say<K extends Message>(key: K, ...args: Args<SafetyCatalog[K]>): Text {
  return new Text((language) => {
    const values = (args as unknown[]).map((arg) => (arg instanceof Text ? arg.in(language) : arg));
    return (CATALOGS[language][key] as (...values: unknown[]) => string)(...values);
  });
}

/** Ein fester Text, der in jeder Sprache gleich ist (Zahlen mit Einheit, unbekannte Kennungen). */
export function literal(value: string): Text {
  return new Text(() => value);
}

/** Die Sportart, wie die App sie nennt; unbekannte mit dem Namen aus der Registry oder der Kennung. */
export function sportText(id: string): Text {
  return new Text((language) => CATALOGS[language].sports[id] ?? SPORTS.get(id)?.displayName ?? id);
}

export function extraText(kind: string): Text {
  return new Text((language) => CATALOGS[language].extras[kind] ?? kind);
}

export function equipmentText(id: string): Text {
  return new Text((language) => CATALOGS[language].equipment[id] ?? CATALOGS[language].venues[id] ?? id);
}

/** Leistungstest; ohne Uebersetzung mit dem Namen aus dem Modul. */
export function testText(id: string, displayName: string): Text {
  return new Text((language) => CATALOGS[language].tests[id] ?? displayName);
}

export function intensityText(intensity: string): Text {
  return new Text((language) => CATALOGS[language].intensities[intensity] ?? intensity);
}

/** Ein Tag im Plan, deutsch "Montag, 06.10.". */
export function dayText(iso: string): Text {
  return new Text((language) => CATALOGS[language].day(iso));
}

/** Tag und Monat, deutsch "06.10.". */
export function dateText(iso: string): Text {
  return new Text((language) => CATALOGS[language].date(iso));
}

/** Eine Woche im Gesamtplan, deutsch "Woche ab 06.10.". */
export function weekText(iso: string): Text {
  return new Text((language) => CATALOGS[language].week(iso));
}

/** Eine Aufzaehlung: `or` "A oder B", `and` "A und B", `plain` "A, B". */
export function listText(items: readonly Text[], kind: "or" | "and" | "plain"): Text {
  return new Text((language) => CATALOGS[language].list(items.map((item) => item.in(language)), kind));
}

/** Mehrere Gruende hintereinander, deutsch mit Komma. */
export function reasonsText(items: readonly Text[]): Text {
  return listText(items, "plain");
}

/** Saetze vor einem Tag ("Montag, 06.10.: ..."). */
export function onDay(iso: string, text: Text): Text {
  return new Text((language) => CATALOGS[language].onDay(CATALOGS[language].day(iso), text.in(language)));
}

/** Satz vor einer Woche des Gesamtplans ("Woche ab 06.10.: ..."). */
export function inWeek(iso: string, text: Text): Text {
  return new Text((language) => CATALOGS[language].onDay(CATALOGS[language].week(iso), text.in(language)));
}

/** Die Korrekturen als Zeilen in der Sprache der App. */
export function render(texts: readonly Text[], language: Language = "de"): string[] {
  return texts.map((text) => text.in(language));
}
