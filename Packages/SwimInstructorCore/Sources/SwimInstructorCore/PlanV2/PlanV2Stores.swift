import Foundation

// Plan v2 speichert in eigenen Dateien neben denen von v1: Die alten Dateien bleiben lesbar (`contracts/app-storage/`),
// und ein Wechsel zurück auf eine ältere App-Version findet seine Pläne unverändert vor.

enum PlanV2Files {
    /// `Application Support/SwimInstructor/<name>` im App-Container.
    static func url(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SwimInstructor/\(name)")
    }

    static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PlanCoding.jsonEncoder().encode(value).write(to: url, options: .atomic)
    }

    /// Eine fehlende, kaputte oder veraltete Datei ist kein Fehler, nur kein gespeicherter Wert.
    static func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PlanCoding.jsonDecoder().decode(type, from: data)
    }
}

// MARK: - Tagesplan

/// Der zuletzt empfangene Tagesplan v2, damit "Heute" auch ohne Netz etwas zeigt.
public protocol DayPlanV2Caching {
    func load() -> DayPlanV2Response?
    func save(_ response: DayPlanV2Response) throws
}

public struct FileDayPlanV2Cache: DayPlanV2Caching {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `last-plan-v2.json`.
    public static func standard() -> FileDayPlanV2Cache {
        FileDayPlanV2Cache(fileURL: PlanV2Files.url("last-plan-v2.json"))
    }

    public func load() -> DayPlanV2Response? {
        PlanV2Files.read(DayPlanV2Response.self, from: fileURL)
    }

    public func save(_ response: DayPlanV2Response) throws {
        try PlanV2Files.write(response, to: fileURL)
    }
}

/// Die Tagespläne der letzten Wochen für "Plan gegen Ist".
public protocol DayPlanV2HistoryStoring {
    /// Alle gespeicherten Pläne, ältester zuerst, höchstens einer pro Tag.
    func load() -> [DayPlanV2Response]
    func record(_ response: DayPlanV2Response) throws
}

public struct FileDayPlanV2History: DayPlanV2HistoryStoring {
    public static let defaultMaxEntries = 120

    private let fileURL: URL
    private let maxEntries: Int

    public init(fileURL: URL, maxEntries: Int = FileDayPlanV2History.defaultMaxEntries) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
    }

    /// `plan-history-v2.json`.
    public static func standard() -> FileDayPlanV2History {
        FileDayPlanV2History(fileURL: PlanV2Files.url("plan-history-v2.json"))
    }

    public func load() -> [DayPlanV2Response] {
        stored()
    }

    /// Pro Tag zählt der erste Plan (nach ihm konnte der Athlet sich richten); Fallback-Pläne sind nur Kopien älterer
    /// und kommen nicht hinein.
    public func record(_ response: DayPlanV2Response) throws {
        guard response.source != .fallback else { return }
        var entries = stored()
        guard !entries.contains(where: { $0.date == response.date }) else { return }
        entries.append(response)
        entries.sort { $0.date < $1.date }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        try PlanV2Files.write(entries, to: fileURL)
    }

    private func stored() -> [DayPlanV2Response] {
        PlanV2Files.read([DayPlanV2Response].self, from: fileURL) ?? []
    }
}

// MARK: - Sieben Tage

public protocol WeekPlanV2Storing {
    func load() -> [WeekPlanV2]
    func save(_ plans: [WeekPlanV2]) throws
}

public struct FileWeekPlanV2Store: WeekPlanV2Storing {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `week-plans-v2.json`.
    public static func standard() -> FileWeekPlanV2Store {
        FileWeekPlanV2Store(fileURL: PlanV2Files.url("week-plans-v2.json"))
    }

    public func load() -> [WeekPlanV2] {
        (PlanV2Files.read([WeekPlanV2].self, from: fileURL) ?? []).sorted { $0.weekStart < $1.weekStart }
    }

    public func save(_ plans: [WeekPlanV2]) throws {
        try PlanV2Files.write(plans, to: fileURL)
    }
}

// MARK: - Gesamtplan

public protocol MacroPlanV2Storing {
    func load() -> MacroPlanV2?
    func save(_ plan: MacroPlanV2) throws
}

public struct FileMacroPlanV2Store: MacroPlanV2Storing {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `macro-plan-v2.json`.
    public static func standard() -> FileMacroPlanV2Store {
        FileMacroPlanV2Store(fileURL: PlanV2Files.url("macro-plan-v2.json"))
    }

    public func load() -> MacroPlanV2? {
        PlanV2Files.read(MacroPlanV2.self, from: fileURL)
    }

    public func save(_ plan: MacroPlanV2) throws {
        try PlanV2Files.write(plan, to: fileURL)
    }
}
