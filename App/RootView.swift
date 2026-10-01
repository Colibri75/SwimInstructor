import SwiftUI

/// Hauptnavigation der iPhone-App: Heute, Dashboard, Verlauf.
struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Heute", systemImage: "figure.pool.swim") }
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.xyaxis.line") }
            HistoryView()
                .tabItem { Label("Verlauf", systemImage: "calendar") }
        }
    }
}
