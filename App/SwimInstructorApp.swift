import SwiftUI
import SwimInstructorCore

@main
@MainActor
struct SwimInstructorApp: App {
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var settings: BackendSettings
    @StateObject private var loader: TodayPlanLoader
    @StateObject private var planSync: PhonePlanSync
    @StateObject private var reminderSettings: ReminderSettings
    @StateObject private var reminder: DailyReminderCoordinator

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
            cache: FilePlanCache.standard(),
            history: FilePlanHistory.standard()
        )
        _healthKitManager = StateObject(wrappedValue: healthKitManager)
        _settings = StateObject(wrappedValue: settings)
        // Früh starten: Weckt die Watch die App im Hintergrund, muss die Sitzung schon aktiv sein.
        let planSync = PhonePlanSync(loader: loader)
        planSync.start()
        _loader = StateObject(wrappedValue: loader)
        _planSync = StateObject(wrappedValue: planSync)

        let reminderSettings = ReminderSettings()
        let reminder = DailyReminderCoordinator(settings: reminderSettings, loader: loader)
        // Die Hintergrundaufgabe muss registriert sein, bevor die App fertig gestartet ist.
        reminder.start()
        _reminderSettings = StateObject(wrappedValue: reminderSettings)
        _reminder = StateObject(wrappedValue: reminder)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthKitManager)
                .environmentObject(settings)
                .environmentObject(loader)
                .environmentObject(reminderSettings)
                .environmentObject(reminder)
        }
    }
}
