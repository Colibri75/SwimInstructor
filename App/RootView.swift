import SwiftUI
import SwimInstructorCore

/// Hauptnavigation der iPhone-App: Heute, Plan (Gesamtplan und nächste 14 Tage), Dashboard, Verlauf. Beim ersten
/// Start kommt davor die Einrichtung (Ziel, Wochenraster, Startniveau) mit dem Ladebildschirm, bis die Pläne stehen.
struct RootView: View {
    private enum Tab {
        case today, week, dashboard, history
    }

    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var consent: AIDataConsent
    @EnvironmentObject private var router: NotificationRouter

    private let onboardingStore: OnboardingStoring
    @State private var selection = Tab.today
    @State private var onboardingDone: Bool
    /// Die ganze Nachricht deines Coachs, nach dem Tipp auf ihre Mitteilung.
    @State private var shownMessage: CoachMessage?
    /// "Weg zum Ziel", nach dem Tipp auf die Wochenbilanz.
    @State private var showsCourse = false
    private let messages: CoachMessageStoring = UserDefaultsCoachMessageStore()
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.standard

    init(onboardingStore: OnboardingStoring = UserDefaultsOnboardingStore()) {
        self.onboardingStore = onboardingStore
        _onboardingDone = State(initialValue: onboardingStore.isCompleted)
    }

    var body: some View {
        Group {
            if onboardingDone {
                tabs
            } else {
                OnboardingView(
                    buildsPlan: onboardingStore.isPlanRequested,
                    onPlanRequested: { onboardingStore.setPlanRequested($0) }
                ) {
                    onboardingStore.complete()
                    onboardingStore.setPlanRequested(false)
                    // Die Pläne sind fertig (oder bewusst übersprungen): weiter mit dem Training von heute.
                    selection = .today
                    onboardingDone = true
                    Task { await loader.refreshIfNeeded() }
                }
            }
        }
        // Design aus dem Logo: Glut als Akzent, runde Schrift wie die Linien des Gipfels.
        .tint(Theme.accent)
        .fontDesign(.rounded)
        // Hell oder dunkel aus den Einstellungen.
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { _, value in value.apply() }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            TodayView(onShowWeek: { selection = .week })
                .tabItem { Label("Aktuell", systemImage: "figure.mixed.cardio") }
                .tag(Tab.today)
            WeekView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(Tab.week)
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.xyaxis.line") }
                .tag(Tab.dashboard)
            HistoryView()
                .tabItem { Label("Verlauf", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        // Getippte Mitteilung: das Passende öffnen, auch wenn sie die App erst gestartet hat.
        .onAppear { open(router.pending) }
        .onChange(of: router.pending) { _, route in open(route) }
        .sheet(item: $shownMessage) { message in
            CoachMessageView(message: message) {
                shownMessage = nil
                selection = .week
            }
        }
        .sheet(isPresented: $showsCourse) {
            NavigationStack {
                GoalCourseView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { showsCourse = false }
                        }
                    }
            }
        }
        // Vor der ersten Plananfrage ohne Einwilligung (auch nach dem Update): einmal je Start fragen.
        .sheet(isPresented: $consent.isPromptPresented, onDismiss: {
            if !consent.isGranted { consent.decline() }
        }) {
            AIConsentSheet {
                // Die gesperrte Planung nachholen.
                Task { await loader.refreshIfNeeded() }
            }
        }
    }

    /// "Wie war's?" und der Plan am Morgen führen nach Aktuell (die Bewertung öffnet dort `TodayView`), eine Nachricht
    /// deines Coachs erscheint ganz.
    private func open(_ route: NotificationRoute?) {
        guard let route else { return }
        switch route {
        case .today:
            selection = .today
            router.finish()
        case .feedback:
            // `TodayView` öffnet die Bewertung, sobald Health gelesen ist, und erledigt die Route.
            selection = .today
        case .course:
            router.finish()
            selection = .today
            showsCourse = true
        case let .message(id):
            router.finish()
            if let message = messages.message(id: id) {
                shownMessage = message
            } else {
                // Eine Mitteilung von vor dieser Version: Ihre Nachricht ist nicht gespeichert.
                selection = .week
            }
        }
    }
}
