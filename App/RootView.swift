import SwiftUI

/// Hauptnavigation der iPhone-App: Heute, Dashboard, Verlauf.
struct RootView: View {
    @EnvironmentObject private var reminder: DailyReminderCoordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Heute", systemImage: "figure.pool.swim") }
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.xyaxis.line") }
            HistoryView()
                .tabItem { Label("Verlauf", systemImage: "calendar") }
        }
        .task { await reminder.apply() }
        .onChange(of: scenePhase) { _, phase in
            // Beim Öffnen die Erinnerungen der nächsten Tage auffrischen, beim Verlassen den
            // nächsten Hintergrundlauf einplanen.
            switch phase {
            case .active: Task { await reminder.apply() }
            case .background: reminder.scheduleBackgroundRefresh()
            default: break
            }
        }
    }
}
