import Foundation

/// Steuert "Heute": Health lesen, Snapshot bauen, Tagesplan für alle Sportarten holen, zwischenspeichern. Die Vorgabe kommt aus den sieben Tagen (`DayTargetV2`), dazu gehen das
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
    /// Vorschauen kommender Tage (Plan-Tab), je Tag die letzte.
    @Published public private(set) var previews: [String: DayPlanV2Response] = [:]
    /// Der Tag, dessen Vorschau gerade entsteht.
    @Published public private(set) var loadingPreviewDate: String?
    /// Fehler bei der letzten Vorschau, mit ihrem Tag.
    @Published public private(set) var previewError: (date: String, message: String)?

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
    private let extras: @MainActor () -> PlanningExtras
    private let prepare: @MainActor (AthleteStateReading) async -> Void
    private let previewStore: DayPlanPreviewStoring?
    private let targetOn: @MainActor (String) -> DayTargetV2?
    private let extrasOn: @MainActor (String) -> PlanningExtras
    private let now: () -> Date
    private let calendar: Calendar

    /// - Parameters:
    ///   - planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    ///   - dayTarget: die Vorgabe der sieben Tage für heute, `nil` ohne Plan.
    ///   - recentTraining: die Einheiten der letzten Tage samt heute, aus dem frisch gelesenen Zustand.
    ///   - prepare: läuft nach dem Lesen von Health und vor dem Tagesplan (Gesamtplan, sieben Tage).
    ///   - previewStore, targetOn, extrasOn: für die Vorschau kommender Tage im Plan-Tab: wo sie liegen, die Vorgabe
    ///     der sieben Tage und Kraft, Ort und freie Zeit für einen Tag.
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
        extras: @escaping @MainActor () -> PlanningExtras = { .none },
        prepare: @escaping @MainActor (AthleteStateReading) async -> Void = { _ in },
        previewStore: DayPlanPreviewStoring? = nil,
        targetOn: @escaping @MainActor (String) -> DayTargetV2? = { _ in nil },
        extrasOn: @escaping @MainActor (String) -> PlanningExtras = { _ in .none },
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
        self.extras = extras
        self.prepare = prepare
        self.previewStore = previewStore
        self.targetOn = targetOn
        self.extrasOn = extrasOn
        self.now = now
        self.calendar = calendar
        self.response = cache.load()
        // Ein Plan aus dem Cache gehört auch in den Verlauf, falls er vor dem Verlauf entstand.
        if let cached = response {
            try? history?.record(cached)
        }
        self.planHistory = history?.load() ?? []
        self.wish = wishStore?.wish(for: PlanFormatting.isoDay(now(), calendar: calendar)) ?? ""
        let today = PlanFormatting.isoDay(now(), calendar: calendar)
        self.previews = Dictionary((previewStore?.load() ?? []).filter { $0.date > today }.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
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

    /// Nur Health lesen (mit Erlaubnis), ohne Gesamtplan, sieben Tage und Tagesplan: für die Einrichtung, die beim
    /// Startniveau zeigt, was Health weiß, bevor es ein Ziel und einen Plan gibt.
    public func readHealth() async {
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
    }

    /// Speichert den Wunsch für heute. Er wirkt beim nächsten Plan, ändert aber den angezeigten nicht.
    public func setWish(_ text: String) {
        wishStore?.setWish(text, for: todayKey)
        wish = wishStore?.wish(for: todayKey) ?? ""
    }

    // MARK: - Ein Tag im Plan-Tab

    /// Der konkrete Plan eines Tags: heute der Tagesplan, vorher der erste aus dem Verlauf, später die Vorschau, solange
    /// sie zur Vorgabe der sieben Tage passt (nach einer Änderung im Plan-Tab nicht mehr).
    public func dayPlan(on date: String) -> DayPlanV2Response? {
        let today = todayKey
        if date == today {
            return response?.date == today ? response : planHistory.last { $0.date == date }
        }
        if date < today { return planHistory.last { $0.date == date } }
        guard let preview = previews[date], preview.requestedTarget == targetOn(date) else { return nil }
        return preview
    }

    /// Ob sich für den Tag eine Vorschau holen lässt: ein kommender Tag mit Einheiten, so weit der Server vorausplant.
    public func canPreview(_ date: String) -> Bool {
        guard date > todayKey, let target = targetOn(date), !target.sessions.isEmpty else { return false }
        guard let today = calendar.date(from: Self.components(todayKey)), let day = calendar.date(from: Self.components(date)) else { return false }
        let ahead = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        return ahead >= 1 && ahead <= Self.previewDays
    }

    /// So weit voraus plant der Server eine Vorschau (`PREVIEW_DAYS`).
    public static let previewDays = 13

    /// Holt den konkreten Plan für einen kommenden Tag (ein Claude-Aufruf). Am Tag selbst entsteht der Plan neu.
    public func loadPreview(for date: String) async {
        guard loadingPreviewDate == nil, canPreview(date), let reading else { return }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return
        }
        let target = targetOn(date)
        loadingPreviewDate = date
        defer { loadingPreviewDate = nil }
        do {
            var fresh = try await provider.fetchDayPlanV2(DayPlanV2Request(
                snapshot: reading.snapshot,
                date: date,
                dayPlan: target,
                equipment: equipment(),
                recentTraining: recentTraining(reading),
                testSettings: testSettings(),
                extras: extrasOn(date)
            ))
            fresh.requestedTarget = target
            let today = todayKey
            previews = previews.filter { $0.key > today }
            previews[date] = fresh
            previewError = nil
            try? previewStore?.save(previews.values.sorted { $0.date < $1.date })
        } catch {
            previewError = (date, error.localizedDescription)
        }
    }

    private static func components(_ isoDay: String) -> DateComponents {
        let parts = isoDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return DateComponents() }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
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
                testSettings: testSettings(),
                extras: extras()
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
