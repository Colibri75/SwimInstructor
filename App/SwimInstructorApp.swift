import SwiftUI
import SwimInstructorCore

@main
@MainActor
struct SwimInstructorApp: App {
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var settings: BackendSettings
    @StateObject private var loader: TodayPlanLoader
    @StateObject private var weekLoader: WeekPlanLoader
    @StateObject private var planSync: PhonePlanSync

    init() {
        let healthKitManager = HealthKitManager()
        let settings = BackendSettings()
        let builder = SnapshotBuilder(
            workoutRepository: HealthKitSwimWorkoutRepository(),
            vitalsRepository: HealthKitDailyVitalsRepository()
        )
        let ownedEquipment = UserDefaultsOwnedEquipmentStore()
        let weekLoader = WeekPlanLoader(
            store: FileWeekPlanStore.standard(),
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            }
        )
        let loader = TodayPlanLoader(
            authorizer: healthKitManager,
            snapshotBuilder: builder,
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            },
            cache: FilePlanCache.standard(),
            history: FilePlanHistory.standard(),
            wishStore: UserDefaultsDailyWishStore(),
            // Der Tagesplan richtet sich nach der Vorgabe des Wochenplans für heute.
            dayTarget: { [weak weekLoader] in weekLoader?.todayTarget },
            // Nur das Equipment, das der Athlet in den Einstellungen angegeben hat.
            equipment: { ownedEquipment.ownedEquipment() }
        )
        weekLoader.equipmentProvider = { ownedEquipment.ownedEquipment() }
        // Der Wochenplan plant mit dem Zustand und den Einheiten, die der Heute-Bildschirm gelesen hat.
        weekLoader.contextProvider = { [weak loader] in
            loader?.reading.map { WeekPlanLoader.PlanningContext(snapshot: $0.snapshot, workouts: $0.workouts) }
        }
        _healthKitManager = StateObject(wrappedValue: healthKitManager)
        _settings = StateObject(wrappedValue: settings)
        // Früh starten: Weckt die Watch die App im Hintergrund, muss die Sitzung schon aktiv sein.
        let planSync = PhonePlanSync(loader: loader)
        planSync.start()
        _loader = StateObject(wrappedValue: loader)
        _weekLoader = StateObject(wrappedValue: weekLoader)
        _planSync = StateObject(wrappedValue: planSync)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthKitManager)
                .environmentObject(settings)
                .environmentObject(loader)
                .environmentObject(weekLoader)
        }
    }
}
