import SwiftUI
import UIKit

/// Hell oder dunkel, in den Einstellungen wählbar: wie das iPhone, immer hell (Morgennebel) oder immer dunkel (Nacht).
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    /// Schlüssel in den UserDefaults (`@AppStorage`).
    static let storageKey = "appearance"

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
