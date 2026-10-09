import SwiftUI
import SwimInstructorCore

/// Einrichtung beim ersten Start: Ziel, Wochenraster, Startniveau. Erst danach gibt es einen Gesamtplan, damit er
/// nicht mit dem Standardziel entsteht. Jeder Schritt speichert sofort; `onFinish` kommt nach dem letzten.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome, goal, schedule, startingLevel, consent, done
    }

    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var consent: AIDataConsent

    let onFinish: () -> Void

    @State private var step = Step.welcome
    @State private var goalIsValid = true

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    if step != .welcome && step != .done {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zurück") { move(by: -1) }
                        }
                    }
                    // Bei der Einwilligung geht es nur über "Zustimmen" oder "Nicht jetzt" weiter.
                    if step != .welcome && step != .done && step != .consent {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Weiter") { move(by: 1) }
                                .disabled(step == .goal && !goalIsValid)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcome
        case .goal:
            GoalAssistantView(mode: .onboarding, isValid: $goalIsValid)
        case .schedule:
            WeeklyScheduleView()
        case .startingLevel:
            StartingLevelView()
        case .consent:
            AIConsentContent(
                onAgree: {
                    consent.grant()
                    move(by: 1)
                },
                onDecline: {
                    consent.decline()
                    move(by: 1)
                }
            )
        case .done:
            done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkPeak(size: 72, peakColor: .primary)
            Text("Willkommen bei Peaksmith")
                .font(.largeTitle.bold())
            Text("In drei Schritten zu deinem Plan: Ziel festlegen, deine Trainingstage eintragen und angeben, wo du gerade stehst. Danach rechnet die App den Gesamtplan bis zu deinem Ziel.")
            Text("Zuerst fragt die App nach Apple Health. Daraus liest sie dein bisheriges Training, damit der Plan dort anfängt, wo du stehst.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await loader.readHealth() }
                move(by: 1)
            } label: {
                Text("Los geht's").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ember)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkPeak(size: 72, peakColor: .primary)
            Text("Fertig eingerichtet")
                .font(.largeTitle.bold())
            Text("Die App rechnet jetzt deinen Gesamtplan und die nächsten 14 Tage. Das dauert ein paar Minuten.")
            Text("Ziel, Wochenraster und Startniveau kannst du jederzeit in den Einstellungen ändern.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onFinish()
            } label: {
                Text("Plan erstellen").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ember)
            Button("Zurück") { move(by: -1) }
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    private func move(by offset: Int) {
        guard var next = Step(rawValue: step.rawValue + offset) else { return }
        // Wer schon zugestimmt hat, sieht die Einwilligung nicht noch einmal.
        if next == .consent, consent.isGranted, let skipped = Step(rawValue: next.rawValue + offset) {
            next = skipped
        }
        step = next
    }
}
