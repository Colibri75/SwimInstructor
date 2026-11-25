import SwiftUI
import SwimInstructorCore

/// Eine Nachricht deines Coachs ganz: was passiert ist, jede Änderung und seine Begründung. Öffnet sich nach dem Tipp auf
/// die Mitteilung (die nur den Anfang zeigt) und aus Einstellungen › Mitteilungen.
struct CoachMessageView: View {
    let message: CoachMessage
    /// Zum Plan-Tab, `nil`: kein Knopf dafür (etwa aus den Einstellungen).
    var onShowPlan: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    /// Ohne eigenen `NavigationStack`, für die Liste in den Einstellungen.
    var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.title)
                        .font(.title3.weight(.heavy))
                    Text(message.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocale.current)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            if !message.details.isEmpty {
                Section {
                    ForEach(Array(message.details.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(message.kind == .planChanged ? "Was sich ändert" : "Was sich am Gesamtplan ändert")
                }
            }
            if let rationale = message.rationale, !rationale.isEmpty {
                Section {
                    Text(rationale)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(message.kind == .planChanged ? "Begründung deines Coachs" : "Einschätzung deines Coachs")
                }
            }
            if let onShowPlan {
                Section {
                    Button(message.kind == .planChanged ? "Plan ansehen" : "Gesamtplan ansehen") { onShowPlan() }
                }
            }
        }
        .themedList()
        .navigationTitle("Nachricht deines Coachs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Die letzten Nachrichten deines Coachs, neueste zuerst (Einstellungen › Mitteilungen).
struct CoachMessagesView: View {
    private let store: CoachMessageStoring = UserDefaultsCoachMessageStore()
    @State private var messages: [CoachMessage] = []

    var body: some View {
        List {
            if messages.isEmpty {
                Text("Noch keine Nachrichten. Hier stehen die Anpassungen deines Plans und die Fortschreibungen des Gesamtplans, sobald dein Coach etwas meldet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(messages) { message in
                NavigationLink {
                    CoachMessageView(message: message).content
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title)
                        Text(message.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(message.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocale.current)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Nachrichten deines Coachs")
        .onAppear { messages = store.messages() }
    }
}
