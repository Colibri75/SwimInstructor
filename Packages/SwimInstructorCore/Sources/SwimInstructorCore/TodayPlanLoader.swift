import Foundation

/// Steuert den Heute-Bildschirm: Health lesen, Snapshot bauen, Plan vom Backend holen, zwischenspeichern.
///
/// Absichtlich ohne SwiftUI, damit der Ablauf per Unit-Test prüfbar ist. Health-Fehler und
/// Server-Fehler werden getrennt geführt: Die Workouts erscheinen auch dann, wenn der Server nicht
/// erreichbar ist, und ein gespeicherter Plan bleibt stehen, wenn der neue nicht kommt.
@MainActor
public final class TodayPlanLoader: ObservableObject {
    @Published public private(set) var response: PlanResponse?
    @Published public private(set) var reading: AthleteStateReading?
    @Published public private(set) var isLoadingHealth = false
    @Published public private(set) var isLoadingPlan = false
    /// Fehler beim Lesen aus Health.
    @Published public private(set) var healthError: String?
    /// Fehler beim Holen des Plans (der zuletzt gespeicherte Plan bleibt sichtbar).
    @Published public private(set) var planError: String?
    /// Kein Token hinterlegt: Die App kann keinen Plan holen, bis es in den Einstellungen steht.
    @Published public private(set) var needsConfiguration = false
    /// Der Wunsch für heute (leer, wenn keiner hinterlegt ist). Geht bei jeder Plananfrage mit.
    @Published public private(set) var wish: String = ""
    /// Gespeicherte Pläne der letzten Wochen für den Verlauf, ältester zuerst.
    @Published public private(set) var planHistory: [PlanResponse] = []

    private let authorizer: HealthDataAuthorizing?
    private let snapshotBuilder: SnapshotBuilding
    private let planProvider: @MainActor () -> PlanProviding?
    private let cache: PlanCaching
    private let history: PlanHistoryStoring?
    private let wishStore: DailyWishStoring?
    private let now: () -> Date
    private let calendar: Calendar

    /// - Parameter planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    public init(
        authorizer: HealthDataAuthorizing?,
        snapshotBuilder: SnapshotBuilding,
        planProvider: @escaping @MainActor () -> PlanProviding?,
        cache: PlanCaching,
        history: PlanHistoryStoring? = nil,
        wishStore: DailyWishStoring? = nil,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.authorizer = authorizer
        self.snapshotBuilder = snapshotBuilder
        self.planProvider = planProvider
        self.cache = cache
        self.history = history
        self.wishStore = wishStore
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

    public var isLoading: Bool { isLoadingHealth || isLoadingPlan }

    /// Ist der angezeigte Plan einer von heute, den Claude (oder der Server-Cache) erzeugt hat?
    public var hasFreshPlanForToday: Bool {
        guard let response else { return false }
        return response.date == PlanFormatting.isoDay(now(), calendar: calendar) && response.source != .fallback
    }

    /// Beim Öffnen der App: Health immer neu lesen (lokal, kostet nichts), den Plan nur holen, wenn
    /// noch keiner von heute da ist. Jeder Serveraufruf mit geändertem Zustand kann einen
    /// Claude-Aufruf auslösen, darum nicht bei jedem Öffnen.
    public func refreshIfNeeded() async {
        await load(fetchPlan: !hasFreshPlanForToday, regenerate: false)
    }

    /// Ziehen zum Aktualisieren: Health lesen und in jedem Fall einen **neuen** Plan von Claude holen,
    /// auch wenn sich der Zustand nicht geändert hat. Das kostet einen Aufruf (rund 4 Cent); der
    /// Server begrenzt die Zahl der Pläne pro Stunde und Tag.
    public func refresh() async {
        await load(fetchPlan: true, regenerate: true)
    }

    /// Speichert den Wunsch für heute. Er wirkt beim nächsten Plan, ändert aber den angezeigten nicht.
    public func setWish(_ text: String) {
        let day = PlanFormatting.isoDay(now(), calendar: calendar)
        wishStore?.setWish(text, for: day)
        wish = wishStore?.wish(for: day) ?? ""
    }

    /// Wunsch speichern und sofort einen neuen Plan dazu holen.
    public func replan(withWish text: String) async {
        setWish(text)
        await refresh()
    }

    private func load(fetchPlan: Bool, regenerate: Bool) async {
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

        guard fetchPlan, let snapshot = reading?.snapshot else { return }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return
        }
        needsConfiguration = false

        // Den Wunsch erst jetzt lesen: Über Mitternacht offen gelassen, gilt der von gestern nicht mehr.
        let day = PlanFormatting.isoDay(now(), calendar: calendar)
        let todaysWish = wishStore?.wish(for: day)
        wish = todaysWish ?? ""

        isLoadingPlan = true
        defer { isLoadingPlan = false }
        do {
            let fresh = try await provider.fetchPlan(
                for: snapshot,
                options: PlanRequestOptions(regenerate: regenerate, wishes: todaysWish)
            )
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
