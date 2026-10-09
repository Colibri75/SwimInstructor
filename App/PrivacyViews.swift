import SwiftUI
import SwimInstructorCore

/// Bitte um Einwilligung in die Weitergabe der Trainings- und Gesundheitsdaten an den Server und an Anthropic (Apple
/// 5.1.2(i), DSGVO Art. 9). Kommt in der Einrichtung, als Blatt vor der ersten Plananfrage und aus den Einstellungen.
struct AIConsentContent: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Deine Daten und dein Coach")
                    .font(.largeTitle.bold())
                Text("Dein Coach erstellt Pläne mit Claude von Anthropic. Dafür gehen deine Trainings- und Gesundheitsdaten an unseren Server und an Anthropic (USA): Umfang und Dauer deiner Einheiten, Abweichungen von Ruhepuls und HRV, Schlaf, Leistungswerte, Beschwerden, dein Ziel und deine Wünsche.")
                Text("Einzelne Messwerte aus Health und Kalendertermine bleiben auf dem iPhone, und Anthropic erfährt weder deinen Namen noch deine E-Mail-Adresse. Die Daten dienen nur deinem Plan, nie der Werbung, und werden nicht verkauft.")
                    .foregroundStyle(.secondary)
                Text("Du kannst deine Zustimmung jederzeit in den Einstellungen unter Datenschutz widerrufen. Ohne Zustimmung erstellt dein Coach keine neuen Pläne.")
                    .foregroundStyle(.secondary)
                Link("Datenschutzerklärung", destination: PrivacyPolicy.url())
                    .font(.body.weight(.semibold))
                Button {
                    onAgree()
                } label: {
                    Text("Zustimmen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ember)
                .padding(.top, 8)
                Button("Nicht jetzt") { onDecline() }
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.background)
    }
}

/// Das Blatt vor der ersten Plananfrage für alle, die noch nicht zugestimmt haben (auch nach dem Update).
struct AIConsentSheet: View {
    @EnvironmentObject private var consent: AIDataConsent
    /// Nach der Zustimmung: die gesperrte Planung nachholen.
    let onAgree: () -> Void

    var body: some View {
        AIConsentContent(
            onAgree: {
                consent.grant()
                onAgree()
            },
            onDecline: { consent.decline() }
        )
        .presentationDragIndicator(.visible)
    }
}

/// Der Bereich "Datenschutz" der Einstellungen: Link zur Erklärung, Stand der Einwilligung, Widerruf.
struct PrivacySettingsSection: View {
    @EnvironmentObject private var consent: AIDataConsent
    @State private var showsConsent = false

    var body: some View {
        Section {
            Link(destination: PrivacyPolicy.url()) {
                Label("Datenschutzerklärung", systemImage: "doc.text")
            }
            if let record = consent.record, consent.isGranted {
                LabeledContent("Zugestimmt am", value: record.grantedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLocale.current)))
                Button("Zustimmung widerrufen", role: .destructive) {
                    consent.withdraw()
                }
            } else {
                Text("Ohne deine Zustimmung zur Datenweitergabe erstellt dein Coach keine neuen Pläne. Gespeicherte Pläne bleiben.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Zustimmen …") { showsConsent = true }
            }
        } header: {
            Text("Datenschutz")
        } footer: {
            Text("Dein Coach erstellt Pläne mit Claude von Anthropic. Dafür gehen deine Trainings- und Gesundheitsdaten an unseren Server und an Anthropic. Kein Tracking, keine Werbung.")
        }
        .sheet(isPresented: $showsConsent) {
            AIConsentContent(
                onAgree: {
                    consent.grant()
                    showsConsent = false
                },
                onDecline: { showsConsent = false }
            )
        }
    }
}
