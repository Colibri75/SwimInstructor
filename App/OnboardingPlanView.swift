import SwiftUI
import UIKit
import SwimInstructorCore

/// Ladebildschirm am Ende der Einrichtung: Die Schmiede arbeitet, darunter wechselnde Texte, was dein Coach gerade tut,
/// und die Schritte mit Haken. In die App geht es erst, wenn Gesamtplan, die nächsten 14 Tage und (an einem
/// Trainingstag) der Plan für heute fertig sind. Scheitert etwas, steht der Fehler da, mit "Nochmal versuchen".
struct OnboardingPlanView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var macroLoader: MultiSportMacroLoader

    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var builder: OnboardingPlanBuilder?

    var body: some View {
        Group {
            if let builder {
                OnboardingPlanProgress(builder: builder, onFinish: onFinish, onBack: onBack)
            } else {
                Theme.background.ignoresSafeArea()
            }
        }
        .onAppear {
            guard builder == nil else { return }
            let created = makeBuilder()
            builder = created
            Task { await created.run() }
        }
        // Das dauert ein, zwei Minuten: Der Bildschirm soll in der Zeit nicht ausgehen, sonst bricht die Anfrage ab.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func makeBuilder() -> OnboardingPlanBuilder {
        let loader = loader
        let weekLoader = weekLoader
        let macroLoader = macroLoader
        return OnboardingPlanBuilder(
            health: {
                await Self.waitWhile { loader.isLoading }
                if loader.reading == nil { await loader.readHealth() }
                guard loader.reading != nil else {
                    return loader.healthError ?? String(localized: "Apple Health ließ sich nicht lesen.")
                }
                return nil
            },
            macro: {
                await Self.waitWhile { macroLoader.isLoading || macroLoader.isRevising || macroLoader.isReviewing }
                if macroLoader.isCurrent { return nil }
                guard let reading = loader.reading else { return String(localized: "Apple Health ließ sich nicht lesen.") }
                // Direkt, nicht über `ensureCurrent`: Das versucht es nur einmal am Tag, ein zweiter Versuch hier
                // bliebe sonst ohne Plan.
                if await macroLoader.regenerate(snapshot: reading.snapshot) { return nil }
                if macroLoader.needsConfiguration { return String(localized: "Ohne Anmeldung kann dein Coach keinen Plan erstellen.") }
                return macroLoader.error ?? String(localized: "Der Gesamtplan ist nicht entstanden.")
            },
            days: {
                // Der normale Ablauf beim Öffnen: Health, die 14 Tage zum neuen Gesamtplan und der Plan für heute.
                await Self.waitWhile { loader.isLoading || weekLoader.isLoading }
                await loader.refreshIfNeeded()
                guard weekLoader.todayEntry != nil else {
                    if weekLoader.needsConfiguration { return String(localized: "Ohne Anmeldung kann dein Coach keinen Plan erstellen.") }
                    return weekLoader.error ?? String(localized: "Die nächsten 14 Tage sind nicht entstanden.")
                }
                return nil
            },
            today: {
                guard let target = weekLoader.todayTarget, !target.sessions.isEmpty else { return nil }
                if loader.hasFreshPlanForToday && loader.matchesTodayTarget { return nil }
                await Self.waitWhile { loader.isLoading }
                await loader.refreshIfNeeded()
                if loader.hasFreshPlanForToday && loader.matchesTodayTarget { return nil }
                return loader.planError ?? String(localized: "Der Plan für heute ist nicht entstanden.")
            }
        )
    }

    /// Wartet, bis ein Ablauf, der schon läuft (etwa im Hintergrund), fertig ist.
    @MainActor
    private static func waitWhile(_ busy: () -> Bool) async {
        while busy() {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}

private struct OnboardingPlanProgress: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @ObservedObject var builder: OnboardingPlanBuilder
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var hintIndex = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            if builder.failure == nil {
                ForgeAnimation(size: 140)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let failure = builder.failure {
                Text(failure)
                    .multilineTextAlignment(.center)
            } else {
                Text(hint)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 66, alignment: .top)
                    .id(hint)
                    .transition(.opacity)
            }
            checklist
            Spacer()
            if builder.failure != nil {
                Button {
                    Task { await builder.run() }
                } label: {
                    Text("Nochmal versuchen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ember)
                Button("Zurück zur Einrichtung") { onBack() }
                    .frame(maxWidth: .infinity)
            } else {
                Text("Lass die App dabei geöffnet. Das dauert meist ein bis zwei Minuten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onChange(of: builder.isFinished) { _, finished in
            if finished { onFinish() }
        }
        .onChange(of: displayedStep) { _, _ in hintIndex = 0 }
        // Alle paar Sekunden ein neuer Satz, damit man sieht, dass sich etwas tut.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                withAnimation(.easeInOut(duration: 0.4)) { hintIndex += 1 }
            }
        }
    }

    /// Der Plan für heute entsteht im selben Ablauf wie die 14 Tage: Sobald er dran ist, sagt der Text das auch.
    private var displayedStep: OnboardingPlanBuilder.Step {
        let step = builder.step ?? .health
        return step == .days && loader.isLoadingPlan ? .today : step
    }

    private var title: LocalizedStringKey {
        if builder.failure != nil {
            switch builder.step ?? .health {
            case .health: return "Apple Health ließ sich nicht lesen"
            case .macro: return "Der Gesamtplan hat nicht geklappt"
            case .days: return "Die nächsten 14 Tage haben nicht geklappt"
            case .today: return "Der Plan für heute hat nicht geklappt"
            }
        }
        switch displayedStep {
        case .health: return "Dein Coach liest dein bisheriges Training …"
        case .macro: return "Dein Coach plant den Weg zu deinem Ziel …"
        case .days: return "Dein Coach legt die nächsten 14 Tage fest …"
        case .today: return "Dein Coach schreibt dein Training für heute …"
        }
    }

    private var hint: String {
        let hints = Self.hints(for: displayedStep)
        return hints[hintIndex % hints.count]
    }

    private static func hints(for step: OnboardingPlanBuilder.Step) -> [String] {
        switch step {
        case .health:
            return [
                String(localized: "Aus Apple Health kommen deine Einheiten der letzten Wochen, damit der Plan dort anfängt, wo du stehst.")
            ]
        case .macro:
            return [
                String(localized: "Er teilt die Zeit bis zu deinem Ziel in Phasen ein: Grundlage, Aufbau, Spezifisch und Taper."),
                String(localized: "Er rechnet aus, wie viel Training pro Woche du gut verkraftest."),
                String(localized: "Er plant Erholungswochen ein, damit du stärker wirst statt müde."),
                String(localized: "Er verteilt die Sportarten nach deinen Schwerpunkten."),
                String(localized: "Er legt fest, wann Tests sinnvoll sind, um deine Trainingsbereiche zu prüfen."),
                String(localized: "Der Gesamtplan dauert am längsten. Gleich hast du es geschafft.")
            ]
        case .days:
            return [
                String(localized: "Er hält sich an deine Trainingstage und die Zeit, die du pro Tag hast."),
                String(localized: "Harte und lockere Tage wechseln sich ab, damit du dich erholen kannst.")
            ]
        case .today:
            return [
                String(localized: "Gleich siehst du dein erstes Training mit allen Abschnitten.")
            ]
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(OnboardingPlanBuilder.Step.allCases, id: \.self) { step in
                Label {
                    Text(Self.stepName(step))
                        .foregroundStyle(builder.isDone(step) ? .primary : .secondary)
                } icon: {
                    Image(systemName: icon(for: step))
                        .foregroundStyle(builder.isDone(step) ? Theme.accent : .secondary)
                }
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func icon(for step: OnboardingPlanBuilder.Step) -> String {
        if builder.isDone(step) { return "checkmark.circle.fill" }
        if builder.step == step && builder.failure != nil { return "exclamationmark.circle" }
        if builder.step == step { return "hammer" }
        return "circle"
    }

    private static func stepName(_ step: OnboardingPlanBuilder.Step) -> LocalizedStringKey {
        switch step {
        case .health: return "Training aus Apple Health"
        case .macro: return "Gesamtplan bis zum Ziel"
        case .days: return "Die nächsten 14 Tage"
        case .today: return "Training für heute"
        }
    }
}
