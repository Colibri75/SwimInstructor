import SwiftUI

/// Hauptnavigation der iPhone-App: Heute, Plan (Gesamtplan und nächste sieben Tage), Dashboard, Verlauf.
struct RootView: View {
    private enum Tab {
        case today, week, dashboard, history
    }

    @State private var selection = Tab.today

    var body: some View {
        TabView(selection: $selection) {
            TodayView(onShowWeek: { selection = .week })
                .tabItem { Label("Heute", systemImage: "figure.mixed.cardio") }
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
