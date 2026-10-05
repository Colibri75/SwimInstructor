import SwiftUI
import SwimInstructorCore

/// Einheitliche Toolbar für alle Tabs: links immer das Zahnrad zu den Einstellungen, rechts nur Aktionen des Tabs.
private struct SettingsToolbar: ViewModifier {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    /// Von außen gesteuert, wenn der Tab die Einstellungen auch selbst öffnet (Heute: Hinweis ohne Server).
    let isPresented: Binding<Bool>?
    @State private var showsSettings = false

    private var presented: Binding<Bool> { isPresented ?? $showsSettings }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presented.wrappedValue = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: presented) {
                SettingsView {
                    // Neue Server-Adresse, Ziel oder Ausrüstung: gleich einen passenden Plan holen.
                    Task { await loader.refresh() }
                }
            }
    }
}

extension View {
    /// Zahnrad oben links, das die Einstellungen öffnet. Gehört direkt in den `NavigationStack` eines Tabs.
    /// - Parameter isPresented: nur nötig, wenn der Tab die Einstellungen zusätzlich selbst öffnet.
    func settingsToolbar(isPresented: Binding<Bool>? = nil) -> some View {
        modifier(SettingsToolbar(isPresented: isPresented))
    }
}
