import Foundation

/// Steuert "Heute" mit Plan v2: Health lesen, Snapshot bauen, Tagesplan für alle Sportarten holen, zwischenspeichern.
///
/// Wie `TodayPlanLoader`, nur mit Plan v2: Die Vorgabe kommt aus den sieben Tagen (`DayTargetV2`), dazu gehen das
/// bisherige Training und die Testeinstellungen mit. Absichtlich ohne SwiftUI, damit der Ablauf per Unit-Test prüfbar ist.
@MainActor
public final class MultiSportTodayLoader: ObservableObject {
    @Published public private(set) var response: DayPlanV2Response?
    @Published public private(set) var reading: AthleteStateReading?
    @Published public private(set) var isLoadingHealth = false
    @Published public private(set) var isLoadingPlan = false
    /// Läuft gerade die Vorbereitung nach dem Lesen von Health (Gesamtplan, sieben Tage)?
    @Published public private(set) var isPreparing = false
    /// Fehler beim Lesen aus Health.
    @Published public private(set) var healthError: String?
    /// Fehler beim Holen des Plans (der zuletzt gespeicherte Plan bleibt sichtbar).
    @Published public private(set) var planError: String?
    /// Kein Token hinterlegt.
    @Published public private(set) var needsConfiguration = false
    /// Der Wunsch für heute (leer, wenn keiner hinterlegt ist).
    @Published public private(set) var wish: String = ""
    /// Gespeicherte Tagespläne der letzten Wochen für "Plan gegen Ist", ältester zuerst.
    @Published public private(set) var planHistory: [DayPlanV2Response] = []

    private let authorizer: HealthDataAuthorizing?
    private let snapshotBuilder: SnapshotBuilding
    private let planProvider: @MainActor () -> DayPlanV2Providing?
    private let cache: DayPlanV2Caching
    private let history: DayPlanV2HistoryStoring?
    private let wishStore: DailyWishStoring?
    private let dayTarget: @MainActor () -> DayTargetV2?
    private let equipment: @MainActor () -> [String]?
    private let recentTraining: @MainActor (AthleteStateReading) -> [RecentTrainingEntry]
    private let testSettings: @MainActor () -> TestSettings?
    private let prepare: @MainActor (AthleteStateReading) async -> Void
    private let now: () -> Date
    private let calendar: Calendar

    /// - Parameters:
    ///   - planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    ///   - dayTarget: die Vorgabe der sieben Tage für heute, `nil` ohne Plan.
    ///   - recentTraining: die Einheiten der letzten Tage samt heute, aus dem frisch gelesenen Zustand.
    ///   - prepare: läuft nach dem Lesen von Health und vor dem Tagesplan (Gesamtplan, sieben Tage).
    public init(
        authorizer: HealthDataAuthorizing?,
        snapshotBuilder: SnapshotBuilding,
        planProvider: @escaping @MainActor () -> DayPlanV2Providing?,
        cache: DayPlanV2Caching,
        history: DayPlanV2HistoryStoring? = nil,
        wishStore: DailyWishStoring? = nil,
        dayTarget: @escaping @MainActor () -> DayTargetV2? = { nil },
        equipment: @escaping @MainActor () -> [String]? = { nil },
        recentTraining: @escaping @MainActor (AthleteStateReading) -> [RecentTrainingEntry] = { _ in [] },
        testSettings: @escaping @MainActor () -> TestSettings? = { nil },
        prepare: @escaping @MainActor (AthleteStateReading) async -> Void = { _ in },
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.authorizer = authorizer
        self.snapshotBuilder = snapshotBuilder
        self.planProvider = planProvider
        self.cache = cache
        self.history = history
        self.wishStore = wishStore
        self.dayTarget = dayTarget
        self.equipment = equipment
        self.recentTraining = recentTraining
        self.testSettings = testSettings
        self.prepare = prepare
        self.now = now
        self.calendar = calendar
        self.response = cache.load()
        // Ein Plan aus dem Cache gehört auch in den Verlauf, falls er vor dem Verlauf entstand.
        if let cached = response {
            try? history?.record(cached)
        }
        self.planHistory = history?.load() ?? []
        self.wish = wishStore?.wish(for: PlanFormatting.isoDay(now(), calendar: calendar)) ?? ""
    }

    public var todayKey: String { PlanFormatting.isoDay(now(), calendar: calendar) }

    public var isLoading: Bool { isLoadingHealth || isPreparing || isLoadingPlan }

    /// Ist der angezeigte Plan einer von heute, den Claude (oder der Server-Cache) erzeugt hat?
    public var hasFreshPlanForToday: Bool {
        guard let response else { return false }
        return response.date == todayKey && response.source != .fallback
    }

    /// Passt der angezeigte Plan zur Vorgabe der sieben Tage für heute? Nach einer Änderung am heutigen Tag im Plan-Tab
    /// (Umfang, Sportart, Ruhetag) oder einer neuen Planung der sieben Tage nicht mehr.
    public var matchesTodayTarget: Bool {
        response?.requestedTarget == dayTarget()
    }

    /// Beim Öffnen: Health immer neu lesen (kostet nichts), den Plan nur holen, wenn keiner von heute da ist oder sich die
    /// Vorgabe für heute geändert hat.
    public func refreshIfNeeded() async {
        await load(force: false, regenerate: false)
    }

    /// Ziehen zum Aktualisieren: Health lesen und in jedem Fall einen neuen Plan von Claude holen.
    public func refresh() async {
        await load(force: true, regenerate: true)
    }

    /// Speichert den Wunsch für heute. Er wirkt beim nächsten Plan, ändert aber den angezeigten nicht.
    public func setWish(_ text: String) {
        wishStore?.setWish(text, for: todayKey)
        wish = wishStore?.wish(for: todayKey) ?? ""
    }

    /// Wunsch speichern und sofort einen neuen Plan dazu holen.
    public func replan(withWish text: String) async {
        setWish(text)
        await refresh()
    }

    private func load(force: Bool, regenerate: Bool) async {
        guard !isLoading else { return }

        isLoadingHealth = true
        do {
            try await authorizer?.requestAuthorization()
            reading = try await snapshotBuilder.build(now: now())
            healthError = nil
        } catch {
            healthError = error.localizedDescription
        }
        isLoadingHealth = false

        // Erst Gesamtplan und sieben Tage auf den frischen Zustand abstimmen: Der Tagesplan richtet sich danach.
        if let reading {
            isPreparing = true
            await prepare(reading)
            isPreparing = false
        }

        // Erst nach der Vorbereitung entscheiden: Sie kann die Vorgabe für heute geändert haben.
        guard force || !hasFreshPlanForToday || !matchesTodayTarget, let reading else { return }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return
        }
        needsConfiguration = false

        // Den Wunsch erst jetzt lesen: Über Mitternacht offen gelassen, gilt der von gestern nicht mehr.
        let todaysWish = wishStore?.wish(for: todayKey)
        wish = todaysWish ?? ""

        let target = dayTarget()
        isLoadingPlan = true
        defer { isLoadingPlan = false }
        do {
            var fresh = try await provider.fetchDayPlanV2(DayPlanV2Request(
                snapshot: reading.snapshot,
                regenerate: regenerate,
                wishes: todaysWish,
                dayPlan: target,
                equipment: equipment(),
                recentTraining: recentTraining(reading),
                testSettings: testSettings()
            ))
            fresh.requestedTarget = target
            response = fresh
            planError = nil
            // Speichern ist Komfort; scheitert es, ist der Plan trotzdem da.
            try? cache.save(fresh)
            if let history {
                try? history.record(fresh)
                planHistory = history.load()
            }
        } catch {
            planError = error.localizedDescription
        }
    }
}
