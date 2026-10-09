import SwiftUI

extension View {
    /// Liste auf dem Grund aus dem Logo: Nacht im Dunkeln, gedämpftes Blaugrau im Hellen (statt Systemgrau).
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    /// Zeilen als Karten: Nacht im Dunkeln, fast Weiß im Hellen. Auf Abschnitte oder eine Gruppe von Abschnitten anwenden.
    func cardRows() -> some View {
        listRowBackground(Theme.card)
    }
}

/// Hauptaktion: Glut-Fläche mit Navy-Schrift (in beiden Modi lesbar), rund wie die Linien im Logo.
struct EmberButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.heavy))
            .foregroundStyle(Theme.onBright)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.ember.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4), in: Capsule())
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == EmberButtonStyle {
    static var ember: EmberButtonStyle { EmberButtonStyle() }
}
