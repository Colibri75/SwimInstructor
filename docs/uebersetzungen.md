# Übersetzungen

Peaksmith gibt es auf Deutsch, Englisch, Französisch, Spanisch, Italienisch, Portugiesisch (Brasilien),
Chinesisch (vereinfacht), Japanisch, Koreanisch und Hindi. Die App folgt der Sprache des iPhones; in den
iOS-Einstellungen lässt sie sich auch nur für Peaksmith umstellen (Einstellungen › Peaksmith › Sprache). Spricht
das iPhone keine dieser Sprachen, zeigt die App Englisch.

## Wie es funktioniert

- **Die Texte im Code bleiben deutsch.** Der deutsche Text ist zugleich der Schlüssel der Übersetzung.
- Die Übersetzungen liegen in `Localization/<Sprache>.lproj/Localizable.strings` (`de`, `en`, `fr`, `es`, `it`,
  `pt-BR`, `zh-Hans`, `ja`, `ko`, `hi`), eine Zeile je Text: `"Deutscher Text" = "Übersetzung";`. Der Ordner gehört
  zu App, Watch-App und beiden Widgets.
- Die Hinweise der Berechtigungsabfragen (Health, Ort, Kalender) stehen in `App/<Sprache>.lproj/InfoPlist.strings`
  und `WatchApp/<Sprache>.lproj/InfoPlist.strings`.
- Coach-Texte und Pläne schreibt der Server in der Sprache der App: Die App schickt sie bei jeder Anfrage als
  `Accept-Language` mit (`AppLocale.languageCode`).
- Datums- und Zahlenformate nehmen `AppLocale.current` (Sprache der App, Region des iPhones), nie ein festes
  `Locale(identifier: "de_DE")`.

## Regeln für neuen Code

- In SwiftUI werden Literale in `Text("…")`, `Button("…")`, `Label("…", systemImage:)`, `Section("…")`,
  `Toggle("…", …)`, `Picker("…", …)`, `.navigationTitle("…")`, `.accessibilityLabel("…")` usw. automatisch übersetzt.
- **Nicht** übersetzt wird, was als `String`-Variable hineingeht: `Text(titel)`, `Label(titel, systemImage:)`,
  `.navigationTitle(titel)`. Solche Texte entstehen deshalb schon übersetzt, mit `String(localized: "…")`.
- Im Core-Paket stehen alle Texte, die jemand liest, in `String(localized: "…")` (ohne `bundle:`, also mit den
  Übersetzungen der App). In `swift test` gibt es keine Übersetzungen, dort kommt der deutsche Text zurück; Tests
  prüfen deshalb weiter gegen Deutsch.
- Ganze Sätze sind ein Schlüssel, mit Interpolation: `String(localized: "Noch \(tage) Tage bis \(ziel)")`. Keine
  Satzteile aneinanderhängen, die Wortstellung ist in jeder Sprache anders.
- In `String(localized:)` nur `String` und `Int` einsetzen. Kommazahlen vorher formatieren und als `String`
  einsetzen (ein `Double` würde mit sechs Nachkommastellen erscheinen).
- Nicht übersetzen: gespeicherte Werte und `rawValue`s, Codable-Felder, Schlüssel für UserDefaults oder Health,
  alles, was an den Server geht, Vergleichswerte, Log-Ausgaben, SF-Symbol-Namen. Wird ein `rawValue` angezeigt, bekommt
  der Typ eine eigene Anzeige-Eigenschaft mit `String(localized:)`.
- Neue Texte brauchen eine Übersetzung in **jeder** Sprachdatei, sonst wird die iOS-CI rot:
  `scripts/check_localizations.py` vergleicht nach dem Build alle Texte des Codes mit den Sprachdateien und prüft,
  ob die Platzhalter (`%@`, `%lld`) zusammenpassen. In der Übersetzung dürfen Platzhalter umgestellt werden, dann
  mit Position: `%2$@ … %1$lld`.
- Für die deutsche Datei ist die Übersetzung der Schlüssel selbst.

## Schlüssel mit Platzhaltern

Der Compiler macht aus Einsetzungen Platzhalter: `String` und andere Texte werden `%@`, `Int` wird `%lld`.
`Text("Woche \(nummer)")` mit `nummer: Int` hat also den Schlüssel `"Woche %lld"`. Ein `%` im Text wird im
Schlüssel zu `%%`.
