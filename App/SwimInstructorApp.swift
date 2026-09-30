import SwiftUI
import SwimInstructorCore

@main
@MainActor
struct SwimInstructorApp: App {
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var settings: BackendSettings
    @StateObject private var loader: TodayPlanLoader

    init() {
        let healthKitManager = HealthKitManager()
        let settings = BackendSettings()
        let builder = SnapshotBuilder(
            workoutRepository: HealthKitSwimWorkoutRepository(),
            vitalsRepository: HealthKitDailyVitalsRepository()
        )
        let loader = TodayPlanLoader(
            authorizer: healthKitManager,
            snapshotBuilder: builder,
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            },
            cache: FilePlanCache.standard()
        )
        _healthKitManager = StateObject(wrappedValue: healthKitManager)
        _settings = StateObject(wrappedValue: settings)
        _loader = StateObject(wrappedValue: loader)
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environmentObject(healthKitManager)
                .environmentObject(settings)
                .environmentObject(loader)
        }
    }
}
