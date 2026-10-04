import Foundation

/// Ein Testergebnis der Watch auf dem Weg zum iPhone. Die Watch ändert das Profil nie selbst: Das iPhone legt das Ergebnis
/// zur Bestätigung vor (`PerformanceProfileLoader.propose`), mit Vergleich zum bisherigen Wert.
public struct WatchTestResult: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sport: SportID
    /// Kennung des Tests in der Sportart (`PerformanceTest.id`).
    public let testID: String
    /// Die Eingaben wie beim Eintragen von Hand (`RecordedTestResult.entries`).
    public let entries: [String: Double]
    public let measuredAt: Date

    public init(id: UUID = UUID(), sport: SportID, testID: String, entries: [String: Double], measuredAt: Date) {
        self.id = id
        self.sport = sport
        self.testID = testID
        self.entries = entries
        self.measuredAt = measuredAt
    }
}

/// Format, in dem die Watch ein Testergebnis per `transferUserInfo` ans iPhone schickt. Die Übertragung wartet, bis das
/// iPhone erreichbar ist; die Verbindungslogik liegt in den App-Targets.
public enum TestResultSyncCodec {
    static let resultKey = "test_result"
    static let versionKey = "version"
    static let formatVersion = 1

    /// Nur Property-List-Typen, wie WatchConnectivity sie verlangt.
    public static func userInfo(for result: WatchTestResult) throws -> [String: Any] {
        [resultKey: try PlanResponse.jsonEncoder().encode(result), versionKey: formatVersion]
    }

    /// `nil` bei leerem, fremdem oder kaputtem Inhalt (etwa einer anderen Übertragung).
    public static func result(from userInfo: [String: Any]) -> WatchTestResult? {
        guard userInfo[versionKey] as? Int == formatVersion, let data = userInfo[resultKey] as? Data else { return nil }
        return try? PlanResponse.jsonDecoder().decode(WatchTestResult.self, from: data)
    }
}

/// Die Testergebnisse der Watch, die auf dem iPhone noch auf Bestätigung warten.
public protocol WatchTestResultStoring {
    func load() -> [WatchTestResult]
    func save(_ results: [WatchTestResult]) throws
}

public struct FileWatchTestResultStore: WatchTestResultStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `watch-test-results.json`.
    public static func standard() -> FileWatchTestResultStore {
        FileWatchTestResultStore(fileURL: PlanV2Files.url("watch-test-results.json"))
    }

    public func load() -> [WatchTestResult] {
        PlanV2Files.read([WatchTestResult].self, from: fileURL) ?? []
    }

    public func save(_ results: [WatchTestResult]) throws {
        try PlanV2Files.write(results, to: fileURL)
    }
}

/// Eingang der Testergebnisse von der Watch. Ein Ergebnis bleibt, bis der Athlet es übernommen oder verworfen hat, auch
/// wenn die App dazwischen beendet wird. Dasselbe Ergebnis zweimal (erneute Übertragung) zählt einmal.
@MainActor
public final class WatchTestResultInbox: ObservableObject {
    /// So viele Ergebnisse hebt der Eingang höchstens auf, die neuesten.
    nonisolated public static let limit = 10

    @Published public private(set) var results: [WatchTestResult]

    private let store: WatchTestResultStoring
    private let registry: SportRegistry

    public init(store: WatchTestResultStoring, registry: SportRegistry = .standard) {
        self.store = store
        self.registry = registry
        self.results = store.load()
    }

    /// Das älteste offene Ergebnis.
    public var next: WatchTestResult? { results.first }

    /// Nimmt ein Ergebnis an. Unbekannte Sportarten oder Tests fallen weg: Diese App-Version könnte sie nicht auswerten.
    public func receive(_ result: WatchTestResult) {
        guard let module = registry.module(for: result.sport),
              module.performanceTests.contains(where: { $0.id == result.testID }),
              !results.contains(where: { $0.id == result.id }) else { return }
        results = Array((results + [result]).sorted { $0.measuredAt < $1.measuredAt }.suffix(Self.limit))
        try? store.save(results)
    }

    /// Erledigt: übernommen oder verworfen.
    public func remove(_ id: UUID) {
        guard results.contains(where: { $0.id == id }) else { return }
        results.removeAll { $0.id == id }
        try? store.save(results)
    }
}
