import Foundation

/// Eine Kachel der Statistik: Sportart (`nil`: über alle Sportarten), Kennzahl und Zeitraum.
public struct StatisticTile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var sport: SportID?
    public var metric: StatisticMetric
    public var period: StatisticPeriod

    public init(id: UUID = UUID(), sport: SportID?, metric: StatisticMetric, period: StatisticPeriod) {
        self.id = id
        self.sport = sport
        self.metric = metric
        self.period = period
    }

    private enum CodingKeys: String, CodingKey {
        case id, sport, metric, period
    }

    /// Nachsichtig, damit eine gespeicherte Anordnung jedes Update übersteht: Ein Zeitraum, den diese Version nicht kennt,
    /// wird zum Standard; die Kennzahl prüft erst `SportRegistry.resolve`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        sport = try? container.decodeIfPresent(SportID.self, forKey: .sport)
        metric = try container.decode(StatisticMetric.self, forKey: .metric)
        period = (try? container.decode(StatisticPeriod.self, forKey: .period)) ?? .standard
    }
}

/// Die Kacheln in ihrer Reihenfolge, wie sie auf dem Gerät gespeichert sind.
public struct StatisticLayout: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public let version: Int
    public var tiles: [StatisticTile]
    /// Die Sportarten, die es beim Speichern gab. Kommt mit einem Update eine dazu, bekommt sie ihre Standard-Kacheln.
    public var knownSports: [SportID]

    public init(tiles: [StatisticTile], knownSports: [SportID]) {
        self.version = Self.formatVersion
        self.tiles = tiles
        self.knownSports = knownSports
    }

    private enum CodingKeys: String, CodingKey {
        case version, tiles, knownSports
    }

    /// Eine Kachel, die sich nicht lesen lässt, fällt weg; die übrigen bleiben.
    private struct LenientTile: Decodable {
        let tile: StatisticTile?

        init(from decoder: Decoder) throws {
            tile = try? StatisticTile(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? Self.formatVersion
        tiles = try container.decode([LenientTile].self, forKey: .tiles).compactMap(\.tile)
        knownSports = (try? container.decode([SportID].self, forKey: .knownSports)) ?? []
    }

    /// Standard: Stunden je Sportart und Plan, je Sportart ihre ersten beiden Kennzahlen, dann Last und Erholung.
    public static func standard(registry: SportRegistry = .standard) -> StatisticLayout {
        var tiles = [
            StatisticTile(sport: nil, metric: .duration, period: .currentWeek),
            StatisticTile(sport: nil, metric: .planAdherence, period: .fourWeeks)
        ]
        for module in registry.modules {
            tiles += standardTiles(for: module)
        }
        tiles += [
            StatisticTile(sport: nil, metric: .trainingLoad, period: .sevenDays),
            StatisticTile(sport: nil, metric: .restingHeartRate, period: .fourWeeks),
            StatisticTile(sport: nil, metric: .heartRateVariability, period: .fourWeeks),
            StatisticTile(sport: nil, metric: .sleep, period: .sevenDays)
        ]
        return StatisticLayout(tiles: tiles, knownSports: registry.ids)
    }

    /// Die ersten beiden Kennzahlen der Sportart über 4 Wochen.
    static func standardTiles(for module: any SportModule) -> [StatisticTile] {
        module.statistics.prefix(2).map { StatisticTile(sport: module.id, metric: $0.metric, period: .fourWeeks) }
    }

    /// Die Anordnung für diese App-Version: jede Kachel aufgelöst (`SportRegistry.resolve`), jede Kennung einmal, und
    /// für jede neue Sportart ihre Standard-Kacheln am Ende.
    public func updated(for registry: SportRegistry) -> StatisticLayout {
        var seen = Set<UUID>()
        var tiles = self.tiles.filter { seen.insert($0.id).inserted }.map { registry.resolve($0).tile }
        for module in registry.modules where !knownSports.contains(module.id) {
            tiles += Self.standardTiles(for: module)
        }
        return StatisticLayout(tiles: tiles, knownSports: registry.ids)
    }
}

public extension SportRegistry {
    /// Die Kennzahlen einer Sportart (`nil`: über alle Sportarten); leer für eine Sportart, die diese Version nicht kennt.
    func statistics(for sport: SportID?) -> [StatisticDefinition] {
        guard let sport else { return StatisticDefinition.overall }
        return module(for: sport)?.statistics ?? []
    }

    /// Die Kachel so, wie diese App-Version sie zeigen kann. Eine Kennzahl, die die Sportart nicht (mehr) hat, wird zu
    /// ihrer ersten; eine unbekannte Sportart zu "alle Sportarten" mit derselben Kennzahl, wenn es sie dort gibt.
    func resolve(_ tile: StatisticTile) -> (tile: StatisticTile, definition: StatisticDefinition) {
        var resolved = tile
        if let sport = tile.sport, module(for: sport) == nil {
            resolved.sport = nil
        }
        var catalog = statistics(for: resolved.sport)
        if catalog.isEmpty {
            resolved.sport = nil
            catalog = StatisticDefinition.overall
        }
        if let definition = catalog.first(where: { $0.metric == resolved.metric }) {
            return (resolved, definition)
        }
        resolved.metric = catalog[0].metric
        return (resolved, catalog[0])
    }
}

/// Wo die Anordnung der Kacheln liegt.
public protocol StatisticLayoutStoring {
    /// `nil`, solange nichts gespeichert ist (oder das Gespeicherte unlesbar ist): Dann gilt der Standard.
    func load() -> StatisticLayout?
    func save(_ layout: StatisticLayout) throws
}

/// Auf dem Gerät, in den Einstellungen der App.
public struct UserDefaultsStatisticLayoutStore: StatisticLayoutStoring {
    static let storageKey = "statistics.layout"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> StatisticLayout? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(StatisticLayout.self, from: data)
    }

    public func save(_ layout: StatisticLayout) throws {
        defaults.set(try JSONEncoder().encode(layout), forKey: Self.storageKey)
    }
}
