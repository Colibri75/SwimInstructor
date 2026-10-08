import SwiftUI
import SwimInstructorCore

/// Einrichtung beim ersten Start: Ziel, Wochenraster, Startniveau. Erst danach gibt es einen Gesamtplan, damit er
/// nicht mit dem Standardziel entsteht. Jeder Schritt speichert sofort; `onFinish` kommt nach dem letzten.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome, goal, schedule, startingLevel, done
    }

    @EnvironmentObject private var loader: MultiSportTodayLoader

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
        case .done:
            done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Zurück") { move(by: -1) }
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        step = next
    }
}
