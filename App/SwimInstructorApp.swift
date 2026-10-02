import SwiftUI
import SwimInstructorCore

@main
@MainActor
struct SwimInstructorApp: App {
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var settings: BackendSettings
    @StateObject private var loader: TodayPlanLoader
    @StateObject private var weekLoader: WeekPlanLoader
    @StateObject private var macroLoader: MacroPlanLoader
    @StateObject private var planSync: PhonePlanSync

    init() {
        let healthKitManager = HealthKitManager()
        let settings = BackendSettings()
        let goalStore = UserDefaultsGoalStore()
        let builder = SnapshotBuilder(
            workoutRepository: HealthKitSwimWorkoutRepository(),
            vitalsRepository: HealthKitDailyVitalsRepository(),
            // Das Gesamtziel aus den Einstellungen, bei jedem Durchlauf neu gelesen.
            goalProvider: { goalStore.goal() }
        )
        let ownedEquipment = UserDefaultsOwnedEquipmentStore()
        let weekLoader = WeekPlanLoader(
            store: FileWeekPlanStore.standard(),
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            }
        )
        // Der Gesamtplan bis zum Zieltag, für das Ziel aus den Einstellungen.
        let macroLoader = MacroPlanLoader(
            store: FileMacroPlanStore.standard(),
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            },
            goal: { goalStore.goal() }
        )
        let wishStore = UserDefaultsDailyWishStore()
        let loader = TodayPlanLoader(
            authorizer: healthKitManager,
            snapshotBuilder: builder,
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            },
            cache: FilePlanCache.standard(),
            history: FilePlanHistory.standard(),
            wishStore: wishStore,
            // Der Tagesplan richtet sich nach der Vorgabe des Wochenplans für heute.
            dayTarget: { [weak weekLoader] in weekLoader?.todayTarget },
            // Nur das Equipment, das der Athlet in den Einstellungen angegeben hat.
            equipment: { ownedEquipment.ownedEquipment() },
            // Beim ersten Öffnen am Tag, nach dem Lesen von Health und vor dem Tagesplan: Gesamtplan
            // sicherstellen und die nächsten sieben Tage neu auf Zustand, Stand und Vorwoche abstimmen.
            prepare: { [weak macroLoader, weak weekLoader] reading in
                guard let macroLoader, let weekLoader else { return }
                await macroLoader.ensureCurrent(snapshot: reading.snapshot)
                let today = PlanFormatting.isoDay(Date())
                await weekLoader.refreshDaily(wishes: wishStore.wish(for: today), stamp: macroLoader.currentGoalKey)
            }
        )
        weekLoader.equipmentProvider = { ownedEquipment.ownedEquipment() }
        // Die nächsten sieben Tage richten sich nach den Wochen des Gesamtplans.
        weekLoader.macroProvider = { [weak macroLoader] dates in macroLoader?.weeks(overlapping: dates) ?? [] }
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
        _macroLoader = StateObject(wrappedValue: macroLoader)
        _planSync = StateObject(wrappedValue: planSync)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthKitManager)
                .environmentObject(settings)
                .environmentObject(loader)
                .environmentObject(weekLoader)
                .environmentObject(macroLoader)
        }
    }
}
