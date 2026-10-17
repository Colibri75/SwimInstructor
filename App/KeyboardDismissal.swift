import SwiftUI
import UIKit

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

/// Ein Eingabefeld, das man auf Anhieb als solches erkennt: eigene Fläche mit Rahmen im Akzent statt Text ohne Rand
/// in der Zeile.
private struct InputFieldStyle: ViewModifier {
    var minWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: minWidth)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
    }
}

extension View {
    /// Fläche und Rahmen für ein Textfeld (Zahlen in Formularen).
    func inputField(minWidth: CGFloat = 70) -> some View {
        modifier(InputFieldStyle(minWidth: minWidth))
    }

    /// "Fertig" über der Tastatur: Die Zahlentastatur hat keine Return-Taste, so kommt man trotzdem aus dem Feld.
    /// Einmal je Bildschirm anwenden (am Formular), sonst steht der Knopf mehrfach da.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}
