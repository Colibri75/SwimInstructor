import SwiftUI

/// Ein mehrzeiliges Textfeld (`axis: .vertical`) schreibt bei Return eine neue Zeile, die Tastatur bliebe offen.
/// Hier schließt Return die Tastatur; ein Zeilenumbruch wird zum Leerzeichen.
private struct ReturnClosesKeyboard: ViewModifier {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .submitLabel(.done)
            .onChange(of: text) { _, new in
                guard new.contains(where: \.isNewline) else { return }
                text = new.split(whereSeparator: \.isNewline).joined(separator: " ")
                isFocused = false
            }
    }
}

extension View {
    /// Return schließt die Tastatur, auch in einem mehrzeiligen Textfeld.
    func returnClosesKeyboard(text: Binding<String>) -> some View {
        modifier(ReturnClosesKeyboard(text: text))
    }

    /// Nach unten Wischen schließt die Tastatur, auch die Zahlentastatur ohne Return-Taste.
    func swipeClosesKeyboard() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}
