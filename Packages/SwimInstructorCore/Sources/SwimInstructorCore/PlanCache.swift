import Foundation

/// Hält den zuletzt empfangenen Plan auf dem Gerät, damit der Heute-Bildschirm auch ohne Netz
/// (z. B. im Schwimmbad-Keller) etwas zeigt.
public protocol PlanCaching {
    func load() -> PlanResponse?
    func save(_ response: PlanResponse) throws
}

public struct FilePlanCache: PlanCaching {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/SwimInstructor/last-plan.json` im App-Container.
    public static func standard() -> FilePlanCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FilePlanCache(fileURL: base.appendingPathComponent("SwimInstructor/last-plan.json"))
    }

    public func load() -> PlanResponse? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // Ein kaputter oder veralteter Cache ist kein Fehler, nur kein Plan.
        return try? PlanResponse.jsonDecoder().decode(PlanResponse.self, from: data)
    }

    public func save(_ response: PlanResponse) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PlanResponse.jsonEncoder().encode(response)
        try data.write(to: fileURL, options: .atomic)
    }
}
