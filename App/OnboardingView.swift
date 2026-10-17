import SwiftUI
import UIKit
import SwimInstructorCore

/// Einrichtung beim ersten Start: Ziel, Wochenraster, Startniveau, Über mich (freiwillig), Anmeldung. Erst danach gibt
/// es einen Gesamtplan, damit er nicht mit dem Standardziel entsteht. Jeder Schritt speichert sofort. Nach "Plan
/// erstellen" kommt der Ladebildschirm (`OnboardingPlanView`); `onFinish` kommt, wenn alle Pläne fertig sind.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome, goal, schedule, startingLevel, aboutMe, consent, account, done, building
    }

    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var consent: AIDataConsent
    @EnvironmentObject private var settings: BackendSettings

    /// "Plan erstellen" gedrückt (`true`) oder vom Ladebildschirm zurück (`false`), damit ein Neustart dort weitermacht.
    let onPlanRequested: (Bool) -> Void
    let onFinish: () -> Void

    @State private var step: Step
    @State private var goalIsValid = true

    /// - Parameter buildsPlan: gleich mit dem Ladebildschirm anfangen (die App wurde beendet, während die Pläne entstanden).
    init(buildsPlan: Bool = false, onPlanRequested: @escaping (Bool) -> Void = { _ in }, onFinish: @escaping () -> Void) {
        self.onPlanRequested = onPlanRequested
        self.onFinish = onFinish
        _step = State(initialValue: buildsPlan ? .building : .welcome)
    }

    /// Ohne Zustimmung und Anmeldung kann dein Coach keinen Plan erstellen.
    private var canBuildPlan: Bool { consent.isGranted && settings.hasToken }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    if step != .welcome && step != .done && step != .building {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zurück") { move(by: -1) }
                        }
                    }
                    // Bei der Einwilligung geht es nur über "Zustimmen" oder "Nicht jetzt" weiter.
                    if step != .welcome && step != .done && step != .building && step != .consent {
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
        case .aboutMe:
            AthleteProfileView()
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
        case .account:
            account
        case .done:
            done
        case .building:
            OnboardingPlanView(
                onFinish: onFinish,
                onBack: {
                    onPlanRequested(false)
                    step = .done
                }
            )
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkPeak(size: 72, peakColor: .primary)
            Text("Willkommen bei PeakSmith")
                .font(.largeTitle.bold())
            Text("In vier Schritten zu deinem Plan: Ziel festlegen, deine Trainingstage eintragen, angeben, wo du gerade stehst, und ein paar freiwillige Fragen zu dir. Danach rechnet die App den Gesamtplan bis zu deinem Ziel.")
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

    /// Anmelden mit Apple. Überspringen geht ("Weiter"), dann fehlt nur der Plan, bis man sich in den Einstellungen anmeldet.
    private var account: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkPeak(size: 72, peakColor: .primary)
            Text("Anmelden")
                .font(.largeTitle.bold())
            if settings.hasToken {
                if let name = settings.accountName {
                    Label("Angemeldet als \(name)", systemImage: "person.crop.circle.badge.checkmark")
                } else {
                    Label("Mit Server-Token verbunden", systemImage: "key")
                }
            } else {
                Text("Melde dich an, damit dein Coach Pläne erstellen kann.")
                Text("Mit deiner Apple-ID meldest du dich beim Server deines Coaches an. Gespeichert werden dort eine Kennung von Apple und, falls du sie teilst, dein Name und deine E-Mail-Adresse.")
                    .foregroundStyle(.secondary)
                AppleSignInButton {
                    move(by: 1)
                }
            }
            Spacer()
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
            Text("Dein Coach erstellt jetzt deinen Gesamtplan, die nächsten 14 Tage und dein Training für heute. Das dauert meist ein bis zwei Minuten.")
            Text("Ziel, Wochenraster, Startniveau und die Angaben über dich kannst du jederzeit in den Einstellungen ändern.")
                .foregroundStyle(.secondary)
            if !consent.isGranted {
                missingRequirement("Ohne deine Zustimmung zur Datenweitergabe kann dein Coach keinen Plan erstellen.", action: "Zur Zustimmung", target: .consent)
            } else if !settings.hasToken {
                missingRequirement("Ohne Anmeldung kann dein Coach keinen Plan erstellen.", action: "Zur Anmeldung", target: .account)
            }
            Spacer()
            Button {
                onPlanRequested(true)
                step = .building
            } label: {
                Text("Plan erstellen").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ember)
            .disabled(!canBuildPlan)
            if canBuildPlan {
                Button("Zurück") { move(by: -1) }
                    .frame(maxWidth: .infinity)
            } else {
                // Wie bisher: Wer nicht zustimmen oder sich anmelden will, kommt trotzdem in die App, nur ohne Plan.
                Button("Ohne Plan weiter") { onFinish() }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    private func missingRequirement(_ text: LocalizedStringKey, action buttonTitle: LocalizedStringKey, target: Step) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.caution(greenWeak: false))
            Button(buttonTitle) { step = target }
                .fontWeight(.semibold)
        }
    }

    private func move(by offset: Int) {
        // Erst die Tastatur schließen: Eine Zahl im Feld gilt erst, wenn das Feld den Fokus verliert.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard var next = Step(rawValue: step.rawValue + offset) else { return }
        // Wer schon zugestimmt hat, sieht die Einwilligung nicht noch einmal.
        if next == .consent, consent.isGranted, let skipped = Step(rawValue: next.rawValue + offset) {
            next = skipped
        }
        step = next
    }
}
