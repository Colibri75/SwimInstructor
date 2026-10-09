import Foundation

/// Was Widget und Komplikation zeigen: der Tag, um den es geht (heute oder, nach erledigtem Training, morgen), mit seinen
/// Einheiten. Die App schreibt es in die App-Gruppe, die Erweiterungen lesen es nur.
public struct PlanGlance: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let sport: SportID
        /// "Laufen · 40 min"
        public let title: String
        public let focus: String
        public let symbolName: String
        public let colorRGB: UInt32

        public init(sport: SportID, title: String, focus: String, symbolName: String, colorRGB: UInt32) {
            self.sport = sport
            self.title = title
            self.focus = focus
            self.symbolName = symbolName
            self.colorRGB = colorRGB
        }
    }

    /// Kalendertag, `yyyy-MM-dd`.
    public let date: String
    /// Heute ist alles erledigt; `date` ist dann morgen.
    public let todayDone: Bool
    /// Leer an einem Ruhetag.
    public let items: [Item]
    public let updatedAt: Date

    public init(date: String, todayDone: Bool, items: [Item], updatedAt: Date) {
        self.date = date
        self.todayDone = todayDone
        self.items = items
        self.updatedAt = updatedAt
    }

    /// Aus dem Plan des Tags: die Einheiten in der Reihenfolge des Plans.
    public static func make(date: String, todayDone: Bool, plan: DayPlanV2, now: Date, registry: SportRegistry = .standard) -> PlanGlance {
        PlanGlance(
            date: date,
            todayDone: todayDone,
            items: plan.sessions.map { item(sport: $0.sport, amount: $0.amount, unit: $0.unit, focus: $0.focus, registry: registry) },
            updatedAt: now
        )
    }

    /// Ohne konkreten Plan: die Vorgabe der 14 Tage für den Tag.
    public static func make(day: PlannedDay, todayDone: Bool, now: Date, registry: SportRegistry = .standard) -> PlanGlance {
        PlanGlance(
            date: day.date,
            todayDone: todayDone,
            items: day.isUnavailable ? [] : day.sessions.map { item(sport: $0.sport, amount: $0.amount, unit: $0.unit, focus: $0.focus, registry: registry) },
            updatedAt: now
        )
    }

    private static func item(sport: SportID, amount: Double, unit: PlanUnit, focus: String, registry: SportRegistry) -> Item {
        Item(
            sport: sport,
            title: PlanV2Formatting.sessionTitle(sport: sport, amount: amount, unit: unit, registry: registry),
            focus: focus,
            symbolName: registry.symbolName(for: sport),
            colorRGB: registry.colorRGB(for: sport)
        )
    }

    /// Überschrift im Widget: "Heute", "Morgen" oder, wenn der Stand veraltet ist, `nil` (dann "Öffne die App").
    public func heading(now: Date, calendar: Calendar = .current) -> String? {
        let today = PlanFormatting.isoDay(now, calendar: calendar)
        if date == today { return String(localized: "Heute") }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now).map { PlanFormatting.isoDay($0, calendar: calendar) }
        return date == tomorrow ? String(localized: "Morgen") : nil
    }
}

/// Liest und schreibt den Stand für Widget und Komplikation in einer Datei der App-Gruppe.
public struct PlanGlanceStore: Sendable {
    /// Gemeinsam für App, Watch und ihre Erweiterungen (bei Apple unter App Groups angelegt).
    public static let appGroup = "group.com.kellner.SwimInstructor"

    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// Die Datei in der App-Gruppe; ohne App-Gruppe (Tests, falsche Signatur) liest und schreibt der Speicher nichts.
    public static func shared() -> PlanGlanceStore {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return PlanGlanceStore(fileURL: container?.appendingPathComponent("plan-glance.json"))
    }

    public func load() -> PlanGlance? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(PlanGlance.self, from: data)
    }

    /// `true`, wenn sich der Stand geändert hat (dann lohnt es, die Widgets neu zu laden).
    @discardableResult
    public func save(_ glance: PlanGlance) -> Bool {
        guard let fileURL else { return false }
        if let stored = load(), stored.date == glance.date, stored.todayDone == glance.todayDone, stored.items == glance.items {
            return false
        }
        guard let data = try? Self.encoder.encode(glance) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
