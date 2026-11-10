import SwiftUI
import SwimInstructorCore

/// Eigener Claude-API-Schlüssel (optional). Standard ist der Schlüssel von PeakSmith auf dem Server: Niemand muss etwas
/// eintragen, und dieser Schlüssel erscheint nirgends in der App. Wer selbst zahlen will, hinterlegt hier seinen eigenen.
/// Er bleibt im Schlüsselbund; angezeigt wird er nie, nur ob einer hinterlegt ist.
struct OwnKeySection: View {
    @EnvironmentObject private var settings: BackendSettings
    @State private var keyText = ""
    @State private var error: String?

    var body: some View {
        Section {
            if settings.hasOwnAPIKey {
                Label("Eigener Schlüssel aktiv", systemImage: "key.fill")
                Button("Eigenen Schlüssel entfernen", role: .destructive) {
                    do {
                        try settings.removeOwnAPIKey()
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            } else {
                SecureField("sk-ant-…", text: $keyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Eigenen Schlüssel verwenden") {
                    do {
                        try settings.saveOwnAPIKey(keyText)
                        keyText = ""
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Claude-Schlüssel")
        } footer: {
            if settings.hasOwnAPIKey {
                Text("Deine Pläne laufen über dein Anthropic-Konto, ohne die Stunden- und Tageslimits. Entfernst du den Schlüssel, plant dein Coach wieder mit dem Schlüssel von PeakSmith.")
            } else {
                Text("Nicht nötig: Dein Coach plant mit dem Schlüssel von PeakSmith. Wer möchte, kann einen eigenen Claude-API-Schlüssel (console.anthropic.com) eintragen; dann laufen die Pläne über das eigene Anthropic-Konto. Er bleibt im Schlüsselbund dieses iPhones und geht nur mit deinen Plananfragen an den Server, der ihn nicht speichert.")
            }
        }
    }
}
