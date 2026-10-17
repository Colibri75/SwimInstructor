import SwiftUI
import UIKit

/// Hell oder dunkel, in der Einrichtung und den Einstellungen wählbar: immer dunkel (Nacht), immer hell (Morgennebel)
/// oder wie das iPhone.
enum Appearance: String, CaseIterable, Identifiable {
    case dark, light, system

    /// Schlüssel in den UserDefaults (`@AppStorage`).
    static let storageKey = "appearance"
    /// Ohne eigene Wahl: das dunkle Blau aus dem Logo (Steffens Wunsch 17.10.2026). Eine gespeicherte Wahl bleibt.
    static let standard = Appearance.dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "Wie iPhone"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Setzt den Stil an allen Fenstern, damit auch Sheets und die UIKit-Farben aus `Theme` folgen. Anders als
    /// `preferredColorScheme(nil)` springt "Wie iPhone" so ohne Neustart zurück.
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}
