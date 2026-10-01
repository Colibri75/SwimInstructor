import SwiftUI

/// Hauptnavigation der iPhone-App: Heute, Woche, Dashboard, Verlauf.
struct RootView: View {
    private enum Tab {
        case today, week, dashboard, history
    }

    @State private var selection = Tab.today

    var body: some View {
        TabView(selection: $selection) {
            TodayView(onShowWeek: { selection = .week })
                .tabItem { Label("Heute", systemImage: "figure.pool.swim") }
                .tag(Tab.today)
            WeekView()
                .tabItem { Label("Woche", systemImage: "calendar") }
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
