import SwiftUI
import SwimInstructorCore

@main
@MainActor
struct SwimInstructorWatchApp: App {
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var planStore: WatchPlanStore
    @StateObject private var workoutManager: WorkoutManager

    init() {
        // Früh starten, damit ein Plan, den das iPhone inzwischen geschickt hat, gleich ankommt.
        let planStore = WatchPlanStore()
        planStore.start()
        // Eine Instanz für die ganze Uhr: Start-Bildschirm und Aufzeichnung fragen über sie, so erscheint der
        // Health-Dialog nur einmal.
        let healthKitManager = HealthKitManager(shareTypes: HealthKitManager.workoutShareTypes.union(HealthKitManager.effortShareTypes))
        let workoutManager = WorkoutManager(authorizer: healthKitManager)
        // Testergebnisse gehen ans iPhone; dort bestätigt der Athlet sie, erst dann ändern sie das Profil.
        workoutManager.onTestResult = { [weak planStore] result in planStore?.send(result) }
        _healthKitManager = StateObject(wrappedValue: healthKitManager)
        _planStore = StateObject(wrappedValue: planStore)
        _workoutManager = StateObject(wrappedValue: workoutManager)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                // Design aus dem Logo: Glut für Aktionen, Funke für Pausen und Erfolge, runde Schrift.
                .tint(Theme.ember)
                .fontDesign(.rounded)
                .environmentObject(healthKitManager)
                .environmentObject(planStore)
                .environmentObject(workoutManager)
        }
    }
}

/// Plan, laufende Einheit oder Zusammenfassung, je nach Zustand der Aufzeichnung.
struct WatchRootView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager

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
