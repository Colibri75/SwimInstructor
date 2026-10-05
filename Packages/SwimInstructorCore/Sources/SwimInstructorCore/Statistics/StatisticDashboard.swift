import Foundation

/// Die Kacheln des Dashboards: auswählen, hinzufügen, entfernen, umsortieren. Jede Änderung wird sofort auf dem Gerät
/// gespeichert. Beim Start gilt die gespeicherte Anordnung, angepasst an diese App-Version (`StatisticLayout.updated`).
@MainActor
public final class StatisticDashboard: ObservableObject {
    @Published public private(set) var layout: StatisticLayout

    private let store: StatisticLayoutStoring
    private let registry: SportRegistry

    public init(store: StatisticLayoutStoring, registry: SportRegistry = .standard) {
        self.store = store
        self.registry = registry
        self.layout = (store.load() ?? .standard(registry: registry)).updated(for: registry)
    }

    public var tiles: [StatisticTile] { layout.tiles }

    /// Zur Auswahl: alle Sportarten (`nil`), dann die Sportarten der Registry.
    public var sports: [SportID?] {
        [nil] + registry.ids.map { Optional($0) }
    }

    public func catalog(for sport: SportID?) -> [StatisticDefinition] {
        registry.statistics(for: sport)
    }

    /// Wechselt die Sportart. Die Kennzahl bleibt, wenn die neue Sportart sie hat, sonst gilt ihre erste.
    public func setSport(_ sport: SportID?, for id: UUID) {
        change(id) { $0.sport = sport }
    }

    /// Nur Kennzahlen aus dem Katalog der Sportart der Kachel.
    public func setMetric(_ metric: StatisticMetric, for id: UUID) {
        guard let tile = tiles.first(where: { $0.id == id }),
              catalog(for: tile.sport).contains(where: { $0.metric == metric }) else { return }
        change(id) { $0.metric = metric }
    }

    public func setPeriod(_ period: StatisticPeriod, for id: UUID) {
        change(id) { $0.period = period }
    }

    /// Fügt eine Kachel am Ende an.
    public func add(sport: SportID?, metric: StatisticMetric, period: StatisticPeriod) {
        var layout = self.layout
        layout.tiles.append(registry.resolve(StatisticTile(sport: sport, metric: metric, period: period)).tile)
        save(layout)
    }

    public func remove(_ id: UUID) {
        var layout = self.layout
        layout.tiles.removeAll { $0.id == id }
        save(layout)
    }

    /// Entfernt die Kacheln an diesen Stellen (Wischen zum Löschen in der Liste).
    public func remove(atOffsets offsets: IndexSet) {
        var layout = self.layout
        layout.tiles = layout.tiles.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save(layout)
    }

    /// Verschiebt Kacheln wie `List.onMove`: `destination` ist die Stelle vor dem Verschieben, an die sie kommen.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var layout = self.layout
        let moving = source.filter { layout.tiles.indices.contains($0) }
        guard !moving.isEmpty else { return }
        let moved = moving.map { layout.tiles[$0] }
        let remaining = layout.tiles.enumerated().filter { !moving.contains($0.offset) }.map(\.element)
        let index = min(max(destination - moving.filter { $0 < destination }.count, 0), remaining.count)
        layout.tiles = Array(remaining[..<index]) + moved + Array(remaining[index...])
        save(layout)
    }

    /// Zieht eine Kachel auf den Platz einer anderen: Nach vorn gezogen landet sie davor, nach hinten dahinter.
    public func move(_ id: UUID, to target: UUID) {
        guard let from = tiles.firstIndex(where: { $0.id == id }),
              let to = tiles.firstIndex(where: { $0.id == target }), from != to else { return }
        var layout = self.layout
        let tile = layout.tiles.remove(at: from)
        layout.tiles.insert(tile, at: to)
        save(layout)
    }

    /// Eine Position nach vorn (`-1`) oder hinten (`1`), etwa für VoiceOver.
    public func move(_ id: UUID, by offset: Int) {
        guard let from = tiles.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard tiles.indices.contains(to) else { return }
        move(id, to: tiles[to].id)
    }

    /// Zurück zu den Standard-Kacheln.
    public func reset() {
        save(.standard(registry: registry))
    }

    private func change(_ id: UUID, _ update: (inout StatisticTile) -> Void) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        var layout = self.layout
        update(&layout.tiles[index])
        layout.tiles[index] = registry.resolve(layout.tiles[index]).tile
        save(layout)
    }

    private func save(_ layout: StatisticLayout) {
        guard layout != self.layout else { return }
        self.layout = layout
        try? store.save(layout)
    }
}
