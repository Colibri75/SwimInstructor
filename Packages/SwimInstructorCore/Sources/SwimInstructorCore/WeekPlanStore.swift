import Foundation

/// Hält die Wochenpläne auf dem Gerät. Der Server speichert sie nicht, sie gehören dem Athleten samt
/// seinen Änderungen daran.
public protocol WeekPlanStoring {
    func load() -> [WeekPlan]
    func save(_ plans: [WeekPlan]) throws
}

public struct FileWeekPlanStore: WeekPlanStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/SwimInstructor/week-plans.json` im App-Container.
    public static func standard() -> FileWeekPlanStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileWeekPlanStore(fileURL: base.appendingPathComponent("SwimInstructor/week-plans.json"))
    }

    public func load() -> [WeekPlan] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        // Eine kaputte Datei ist kein Fehler, nur keine gespeicherten Wochen.
        let plans = (try? PlanResponse.jsonDecoder().decode([WeekPlan].self, from: data)) ?? []
        return plans.sorted { $0.weekStart < $1.weekStart }
    }

    public func save(_ plans: [WeekPlan]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PlanResponse.jsonEncoder().encode(plans)
        try data.write(to: fileURL, options: .atomic)
    }
}
