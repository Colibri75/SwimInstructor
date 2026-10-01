import Foundation

/// Merkt sich die Pläne der letzten Wochen auf dem Gerät, damit der Verlauf "geplant gegen
/// tatsächlich" auch dann stimmt, wenn der Server nur den Plan von heute kennt.
public protocol PlanHistoryStoring {
    /// Alle gespeicherten Pläne, ältester zuerst, höchstens einer pro Tag.
    func load() -> [PlanResponse]
    func record(_ response: PlanResponse) throws
}

public struct FilePlanHistory: PlanHistoryStoring {
    /// Pläne älter als diese Anzahl Einträge fallen heraus (ein Eintrag pro Tag).
    public static let defaultMaxEntries = 120

    private let fileURL: URL
    private let maxEntries: Int

    public init(fileURL: URL, maxEntries: Int = FilePlanHistory.defaultMaxEntries) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
    }

    /// `Application Support/SwimInstructor/plan-history.json` im App-Container.
    public static func standard() -> FilePlanHistory {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FilePlanHistory(fileURL: base.appendingPathComponent("SwimInstructor/plan-history.json"))
    }

    public func load() -> [PlanResponse] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        // Eine kaputte Datei ist kein Fehler, nur ein leerer Verlauf.
        let decoded = (try? PlanResponse.jsonDecoder().decode([PlanResponse].self, from: data)) ?? []
        return decoded.sorted { $0.date < $1.date }
    }

    /// Pro Tag zählt der **erste** Plan: Das ist der, nach dem du dich richten konntest. Ein
    /// späterer Plan am selben Tag entsteht oft erst nach dem Training und wäre sonst ein
    /// schiefer Vergleichsmaßstab. Fallback-Pläne sind nur Kopien älterer Pläne und werden nicht
    /// aufgenommen.
    public func record(_ response: PlanResponse) throws {
        guard response.source != .fallback else { return }
        var entries = load()
        guard !entries.contains(where: { $0.date == response.date }) else { return }
        entries.append(response)
        entries.sort { $0.date < $1.date }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PlanResponse.jsonEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
