import SwiftUI
import SwimInstructorCore

@main
@MainActor
struct SwimInstructorWatchApp: App {
    @StateObject private var healthKitManager = HealthKitManager(shareTypes: HealthKitManager.workoutShareTypes)
    @StateObject private var planStore: WatchPlanStore
    @StateObject private var workoutManager = SwimWorkoutManager()

    init() {
        // Früh starten, damit ein Plan, den das iPhone inzwischen geschickt hat, gleich ankommt.
        let planStore = WatchPlanStore()
        planStore.start()
        _planStore = StateObject(wrappedValue: planStore)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(healthKitManager)
                .environmentObject(planStore)
                .environmentObject(workoutManager)
        }
    }
}

/// Plan, laufende Einheit oder Zusammenfassung, je nach Zustand der Aufzeichnung.
struct WatchRootView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager

    var body: some View {
        switch workoutManager.phase {
        case .idle:
            WatchTodayView()
        case .countdown:
            WatchCountdownView()
        case .starting, .running, .paused, .saving:
            WatchWorkoutView()
        case let .finished(saved):
            WatchSummaryView(saved: saved)
        }
    }
}
