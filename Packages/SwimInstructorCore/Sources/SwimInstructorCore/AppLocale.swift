import Foundation

/// Sprache der Oberfläche. Die App folgt der iPhone-Sprache (in den iOS-Einstellungen auch pro App umstellbar);
/// welche davon sie kann, steht in `Localization/<Sprache>.lproj`, sonst gilt Englisch.
///
/// Die Texte im Code sind deutsch und zugleich die Schlüssel der Übersetzungen. Core-Texte laufen über
/// `String(localized:)` ohne Bundle, also über die Übersetzungen der App. In `swift test` gibt es keine, dort
/// bleiben Texte und Formate deutsch, damit die Tests weiter gegen die deutschen Texte prüfen.
public enum AppLocale {
    /// Ob das laufende Programm Übersetzungen mitbringt (App, Watch, Widgets; nicht die Tests).
    private static var isLocalized: Bool {
        Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil
    }

    /// Sprachkennung der Oberfläche, z. B. "de", "en", "pt-BR", "zh-Hans". Geht als `Accept-Language` an den Server,
    /// der Coach-Texte und Pläne in dieser Sprache schreibt.
    public static var languageCode: String {
        guard isLocalized, let language = Bundle.main.preferredLocalizations.first else { return "de" }
        return language
    }

    /// Für Datums- und Zahlenformate: Sprache der Oberfläche mit der Region des iPhones (Dezimalzeichen, Wochenbeginn).
    public static var current: Locale {
        guard isLocalized else { return Locale(identifier: "de_DE") }
        var components = Locale.Components(identifier: languageCode)
        components.region = Locale.current.region
        return Locale(components: components)
    }
}
