import SwiftUI
import SwimInstructorCore

@main
@MainActor
struct SwimInstructorApp: App {
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var settings: BackendSettings
    @StateObject private var loader: MultiSportTodayLoader
    @StateObject private var weekLoader: MultiSportWeekLoader
    @StateObject private var macroLoader: MultiSportMacroLoader
    @StateObject private var profileLoader: PerformanceProfileLoader
    @StateObject private var planSync: PhonePlanSync
    @StateObject private var testResultInbox: WatchTestResultInbox
    @StateObject private var statisticDashboard: StatisticDashboard
    @StateObject private var screenLayouts: ScreenLayouts
    @StateObject private var reviewRunner: MacroReviewRunner
    @StateObject private var feedbackBook: SessionFeedbackBook
    @StateObject private var raceLoader: RacePlanLoader
    @StateObject private var locationProvider: LocationProvider
    @StateObject private var calendarProvider: CalendarAvailabilityProvider

    init() {
        let healthKitManager = HealthKitManager()
        let settings = BackendSettings()
        let goalStore = UserDefaultsTrainingGoalStore()
        let profileStore = UserDefaultsPerformanceProfileStore()
        let testSettingsStore = UserDefaultsTestSettingsStore()
        let startingLevelStore = UserDefaultsStartingLevelStore()
        let scheduleStore = UserDefaultsWeeklyScheduleStore()
        let builder = SnapshotBuilder(
            repository: HealthKitWorkoutRepository(),
            vitalsRepository: HealthKitDailyVitalsRepository(),
            // Das Gesamtziel aus den Einstellungen, bei jedem Durchlauf neu gelesen (Snapshot v2). Ein vorgemerktes Ziel
            // wird davor übernommen, sobald die Sperre vorbei ist, damit Snapshot und Gesamtplan zum selben Ziel gehören.
            trainingGoalProvider: {
                goalStore.applyPendingIfDue(now: Date())
                return goalStore.goal()
            },
            // Leistungswerte und Zonen: bestätigte aus dem Profil, sonst aus Health geschätzt.
            performanceRepository: HealthKitPerformanceDataRepository(),
            profileProvider: { profileStore.profile() },
            // Selbst angegebenes Startniveau, nur solange es gilt (SnapshotBuilder filtert).
            startingLevelsProvider: { startingLevelStore.levels() },
            // Der Wochenraster, ohne gespeicherten einer aus Trainingstagen und Stunden des Ziels.
            weeklyScheduleProvider: { scheduleStore.schedule(for: goalStore.goal()) }
        )
        let ownedEquipment = UserDefaultsOwnedEquipmentStore()
        let indoorEquipment = UserDefaultsIndoorEquipmentStore()
        // Schwimm-Hilfsmittel und Rolle oder Laufband für drinnen: eine Liste für den Server.
        let equipment: @MainActor () -> [String]? = { ownedEquipment.ownedEquipment() + indoorEquipment.ownedIndoorEquipment() }
        let planningStore = UserDefaultsPlanningPreferencesStore()
        let feedbackBook = SessionFeedbackBook(store: FileSessionFeedbackStore.standard())
        let locationProvider = LocationProvider()
        let calendarProvider = CalendarAvailabilityProvider()
        // Was außer Zustand und Training mitgeht: Kraft und Mobilität, Ort fürs Wetter, freie Zeit laut Kalender.
        let planningExtras: @MainActor ([String]) -> PlanningExtras = { [weak locationProvider, weak calendarProvider] dates in
            let preferences = planningStore.preferences()
            return PlanningExtras(
                supplements: preferences.supplements.isEmpty ? nil : preferences.supplements,
                location: preferences.usesWeather ? locationProvider?.point : nil,
                availability: preferences.usesCalendar
                    ? calendarProvider?.availability(for: dates, startHour: preferences.calendarStartHour, endHour: preferences.calendarEndHour) ?? []
                    : []
            )
        }
        let weekLoader = MultiSportWeekLoader(
            store: FileWeekPlanV2Store.standard(),
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            }
        )
        // Der Gesamtplan bis zum Zieltag, für alle Sportarten des Ziels aus den Einstellungen.
        let macroLoader = MultiSportMacroLoader(
            store: FileMacroPlanV2Store.standard(),
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            },
            goal: { goalStore.goal() },
            // Ein Gesamtplan gehört zu einer Zielversion: Eine Feinjustierung lässt ihn stehen (P3).
            goalVersion: { goalStore.goalVersion }
        )
        // Fortschreibung alle zwei Wochen und nach einer gemeldeten Pause, im Hintergrund (P4).
        let reviewRunner = MacroReviewRunner(macroLoader: macroLoader, pauseStore: UserDefaultsPauseReportStore())
        let wishStore = UserDefaultsDailyWishStore()
        let loader = MultiSportTodayLoader(
            authorizer: healthKitManager,
            snapshotBuilder: builder,
            planProvider: { [weak settings] in
                settings?.configuration.map { PlanAPIClient(configuration: $0) }
            },
            cache: FileDayPlanV2Cache.standard(),
            history: FileDayPlanV2History.standard(),
            wishStore: wishStore,
            // Der Tagesplan richtet sich nach der Vorgabe der sieben Tage für heute.
            dayTarget: { [weak weekLoader] in weekLoader?.todayTarget },
            // Nur das Equipment, das der Athlet in den Einstellungen angegeben hat.
            equipment: equipment,
            // Das Training der letzten sieben Tage und von heute, mit "hart" aus Plan und Puls.
            recentTraining: { [weak weekLoader] reading in
                weekLoader?.recentTrainingForToday(snapshot: reading.snapshot, workouts: reading.allWorkouts) ?? []
            },
            testSettings: { testSettingsStore.settings() },
            extras: { planningExtras([PlanFormatting.isoDay(Date())]) },
            // Beim ersten Öffnen am Tag, nach dem Lesen von Health und vor dem Tagesplan: Gesamtplan sicherstellen und
            // die nächsten sieben Tage neu abstimmen. Nach einer Überarbeitung des Gesamtplans gilt der Tag wieder als
            // offen, damit die Tage zum neuen Gesamtplan passen.
            prepare: { [weak macroLoader, weak weekLoader, weak reviewRunner, weak locationProvider] reading in
                guard let macroLoader, let weekLoader else { return }
                // Den Ort für das Wetter auffrischen; bis er da ist, gilt der gemerkte.
                if planningStore.preferences().usesWeather { locationProvider?.refresh() }
                await macroLoader.ensureCurrent(snapshot: reading.snapshot)
                // Läuft nebenher; danach stimmt `onReviewed` die Tage neu ab.
                reviewRunner?.startIfDue(reading: reading)
                let today = PlanFormatting.isoDay(Date())
                await weekLoader.refreshDaily(
                    wishes: wishStore.wish(for: today),
                    stamp: "\(macroLoader.currentGoalKey)|\(macroLoader.revisionStamp)"
                )
            },
            // Vorschau kommender Tage im Plan-Tab: Vorgabe der sieben Tage und freie Zeit des Tags.
            previewStore: FileDayPlanPreviewStore.standard(),
            targetOn: { [weak weekLoader] date in weekLoader?.day(on: date)?.target },
            extrasOn: { date in planningExtras([date]) },
            // Was der Tagesplan festlegt (auch nach einem Wunsch), steht danach auch im Plan-Tab.
            adoptPlan: { [weak weekLoader] response in weekLoader?.adoptTodayPlan(response) }
        )
        // Eine Änderung an heute im Plan-Tab gilt auch in Heute und auf der Watch (mehrere Tipps hintereinander: eine Anfrage).
        weekLoader.onEdit = { [weak loader] in loader?.scheduleSync() }
        // Steht heute fest (Tagesplan, Vorschau, schon trainiert), bleibt es beim Neu-Abstimmen der sieben Tage.
        weekLoader.todayLockedProvider = { [weak loader] in loader?.isTodayLocked ?? false }
        reviewRunner.onReviewed = { [weak loader] in await loader?.refreshIfNeeded() }
        weekLoader.equipmentProvider = equipment
        weekLoader.extrasProvider = planningExtras
        // Beschwerden und Anstrengung aus den Rückmeldungen: Der Plan reagiert darauf von selbst.
        weekLoader.feedbackProvider = { [weak feedbackBook] in feedbackBook?.entries ?? [] }
        weekLoader.testSettingsProvider = { testSettingsStore.settings() }
        // Die nächsten sieben Tage richten sich nach den Wochen des Gesamtplans.
        weekLoader.macroProvider = { [weak macroLoader] dates in macroLoader?.weeks(overlapping: dates) ?? [] }
        // Im Plan-Tab lässt sich bis zur letzten Woche des Gesamtplans vorblättern.
        weekLoader.lastWeekStartProvider = { [weak macroLoader] in macroLoader?.plan?.weeks.last?.weekStart }
        // Die Tage planen mit dem Zustand und den Einheiten aller Sportarten, die der Heute-Bildschirm gelesen hat.
        weekLoader.contextProvider = { [weak loader] in
            loader?.reading.map { MultiSportWeekLoader.PlanningContext(snapshot: $0.snapshot, workouts: $0.allWorkouts) }
        }
        macroLoader.testSettingsProvider = { testSettingsStore.settings() }
        // Neue Testwerte seit dem letzten Stand nennt die Fortschreibung ausdrücklich.
        macroLoader.performanceChangesProvider = { date in profileStore.profile().changes(since: date) }

        // Das Profil zeigt neben den bestätigten Werten die Schätzungen aus dem zuletzt gelesenen Zustand.
        let profileLoader = PerformanceProfileLoader(store: profileStore)
        profileLoader.estimatesProvider = { [weak loader] in
            loader?.reading?.snapshot.performance?.performanceValues ?? []
        }

        _healthKitManager = StateObject(wrappedValue: healthKitManager)
        _settings = StateObject(wrappedValue: settings)
        // Früh starten: Weckt die Watch die App im Hintergrund, muss die Sitzung schon aktiv sein.
        // Testergebnisse der Watch warten hier, bis der Athlet sie bestätigt oder verwirft.
        let testResultInbox = WatchTestResultInbox(store: FileWatchTestResultStore.standard())
        let planSync = PhonePlanSync(loader: loader, inbox: testResultInbox)
        planSync.start()
        _loader = StateObject(wrappedValue: loader)
        _weekLoader = StateObject(wrappedValue: weekLoader)
        _macroLoader = StateObject(wrappedValue: macroLoader)
        _profileLoader = StateObject(wrappedValue: profileLoader)
        _planSync = StateObject(wrappedValue: planSync)
        _testResultInbox = StateObject(wrappedValue: testResultInbox)
        // Die Kacheln der Statistik, gespeichert auf dem Gerät.
        _reviewRunner = StateObject(wrappedValue: reviewRunner)
        _feedbackBook = StateObject(wrappedValue: feedbackBook)
        _locationProvider = StateObject(wrappedValue: locationProvider)
        _calendarProvider = StateObject(wrappedValue: calendarProvider)
        // Der Plan für den Wettkampftag, auf dem Gerät gespeichert.
        _raceLoader = StateObject(wrappedValue: RacePlanLoader(
            store: FileRacePlanStore.standard(),
            planProvider: { [weak settings] in settings?.configuration.map { PlanAPIClient(configuration: $0) } }
        ))
        _statisticDashboard = StateObject(wrappedValue: StatisticDashboard(store: UserDefaultsStatisticLayoutStore()))
        // Reihenfolge und Auswahl der Bereiche je Tab, auf dem Gerät gespeichert.
        _screenLayouts = StateObject(wrappedValue: ScreenLayouts(store: UserDefaultsScreenLayoutStore()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthKitManager)
                .environmentObject(settings)
                .environmentObject(loader)
                .environmentObject(weekLoader)
                .environmentObject(macroLoader)
                .environmentObject(profileLoader)
                .environmentObject(testResultInbox)
                .environmentObject(statisticDashboard)
                .environmentObject(screenLayouts)
                .environmentObject(reviewRunner)
                .environmentObject(feedbackBook)
                .environmentObject(raceLoader)
                .environmentObject(locationProvider)
                .environmentObject(calendarProvider)
        }
    }
}
