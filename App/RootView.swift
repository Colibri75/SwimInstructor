import SwiftUI
import SwimInstructorCore

/// Hauptnavigation der iPhone-App: Heute, Plan (Gesamtplan und nächste sieben Tage), Dashboard, Verlauf. Beim ersten
/// Start kommt davor die Einrichtung (Ziel, Wochenraster, Startniveau); danach geht es zum Plan, der dann entsteht.
struct RootView: View {
    private enum Tab {
        case today, week, dashboard, history
    }

    @EnvironmentObject private var loader: MultiSportTodayLoader

    private let onboardingStore: OnboardingStoring
    @State private var selection = Tab.today
    @State private var onboardingDone: Bool

    init(onboardingStore: OnboardingStoring = UserDefaultsOnboardingStore()) {
        self.onboardingStore = onboardingStore
        _onboardingDone = State(initialValue: onboardingStore.isCompleted)
    }

    var body: some View {
        if onboardingDone {
            tabs
        } else {
            OnboardingView {
                onboardingStore.complete()
                selection = .week
                onboardingDone = true
                // Gesamtplan und sieben Tage zum neuen Ziel; der Plan-Tab liest Health nur, wenn noch nichts gelesen ist.
                Task { await loader.refreshIfNeeded() }
            }
        }
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
    }
}
