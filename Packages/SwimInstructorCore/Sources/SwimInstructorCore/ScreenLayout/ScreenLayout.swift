import Foundation

/// Ein Bildschirm der iPhone-App, dessen Bereiche sich anordnen, ausblenden und wieder hinzufügen lassen.
public enum LayoutScreen: String, CaseIterable, Codable, Sendable {
    case today
    case week
    case macro
    case dashboard
    case history

    public var displayName: String {
        switch self {
        case .today: return String(localized: "Aktuell")
        case .week: return String(localized: "Wochenplan")
        case .macro: return String(localized: "Gesamtplan")
        case .dashboard: return String(localized: "Dashboard")
        case .history: return String(localized: "Verlauf")
        }
    }

    /// Alle Bereiche in der Standard-Reihenfolge.
    public var sections: [LayoutSection] {
        switch self {
        case .today:
            return [
                LayoutSection(id: "watchResult", title: String(localized: "Testergebnis von der Watch"), symbol: "applewatch",
                              summary: String(localized: "Erscheint, wenn ein Test von der Watch auf Bestätigung wartet."), isRequired: true),
                LayoutSection(id: "adaptation", title: String(localized: "Hinweis auf Anpassungen"), symbol: "arrow.triangle.2.circlepath",
                              summary: String(localized: "Warum der Plan außer der Reihe anders aussieht.")),
                LayoutSection(id: "feedback", title: String(localized: "Rückmeldung"), symbol: "text.bubble",
                              summary: String(localized: "Einheiten von gestern und heute ohne \"Wie war's?\".")),
                LayoutSection(id: "done", title: String(localized: "Heute erledigt"), symbol: "checkmark.seal",
                              summary: String(localized: "Umschalter zwischen heute und morgen nach dem Training."), isRequired: true),
                LayoutSection(id: "dayCard", title: String(localized: "Tageskarte"), symbol: "rectangle.portrait",
                              summary: String(localized: "Tag, Stand und Einheiten groß auf einen Blick.")),
                LayoutSection(id: "plan", title: String(localized: "Tagesplan"), symbol: "list.bullet.rectangle",
                              summary: String(localized: "Der Plan mit allen Schritten und Ergänzungen."), isRequired: true),
                LayoutSection(id: "wish", title: String(localized: "Dein Wunsch für heute"), symbol: "text.cursor",
                              summary: String(localized: "Freitext und Plan neu erstellen."))
            ]
        case .week:
            return [
                LayoutSection(id: "summary", title: String(localized: "Geplant und trainiert"), symbol: "sum",
                              summary: String(localized: "Minuten und Umfang je Sportart der Woche.")),
                LayoutSection(id: "macroTarget", title: String(localized: "Vorgabe aus dem Gesamtplan"), symbol: "mountain.2",
                              summary: String(localized: "Phase, Umfang je Sportart, Tests und Schwerpunkt.")),
                LayoutSection(id: "overview", title: String(localized: "Überblick"), symbol: "text.alignleft",
                              summary: String(localized: "Warum die Woche so geplant ist.")),
                LayoutSection(id: "days", title: String(localized: "Tage"), symbol: "calendar",
                              summary: String(localized: "Die Tage der Woche, antippen zum Anpassen."), isRequired: true),
                LayoutSection(id: "planning", title: String(localized: "Planen"), symbol: "wand.and.stars",
                              summary: String(localized: "Wunsch für die nächsten Tage und neu planen."))
            ]
        case .macro:
            return [
                LayoutSection(id: "racePlan", title: String(localized: "Plan für den Zieltag"), symbol: "flag.checkered",
                              summary: String(localized: "Ablauf, Tempo, Wechsel und Packliste.")),
                LayoutSection(id: "overview", title: String(localized: "Gesamtplan bis zum Ziel"), symbol: "mountain.2",
                              summary: String(localized: "Überblick und Gesamtplan erstellen."), isRequired: true),
                LayoutSection(id: "weeks", title: String(localized: "Wochen bis zum Ziel"), symbol: "calendar",
                              summary: String(localized: "Alle Wochen, antippen öffnet sie im Wochenplan.")),
                LayoutSection(id: "profile", title: String(localized: "Leistungsprofil"), symbol: "gauge.with.dots.needle.67percent",
                              summary: String(localized: "Leistungswerte und Tests.")),
                LayoutSection(id: "review", title: String(localized: "Fortschreibung"), symbol: "arrow.forward.circle",
                              summary: String(localized: "Plan gegen Ist der letzten Wochen.")),
                LayoutSection(id: "feedback", title: String(localized: "Feedback zum Gesamtplan"), symbol: "text.bubble",
                              summary: String(localized: "Änderungswünsche an deinen Coach."))
            ]
        case .dashboard:
            return [
                LayoutSection(id: "statistics", title: String(localized: "Statistik"), symbol: "chart.bar",
                              summary: String(localized: "Deine Kacheln mit Kennzahlen.")),
                LayoutSection(id: "week", title: String(localized: "Diese Woche"), symbol: "calendar",
                              summary: String(localized: "Stand der Woche und Erholung.")),
                LayoutSection(id: "goal", title: String(localized: "Dein Ziel"), symbol: "flag",
                              summary: String(localized: "Ziel, Abstand und Pace."))
            ]
        case .history:
            return [
                LayoutSection(id: "workouts", title: String(localized: "Letzte Einheiten"), symbol: "figure.mixed.cardio",
                              summary: String(localized: "Die Einheiten aus Health, antippen öffnet sie.")),
                LayoutSection(id: "summary", title: String(localized: "Die letzten 4 Wochen"), symbol: "sum",
                              summary: String(localized: "Trainierte Einheiten und eingehaltene Ruhetage.")),
                LayoutSection(id: "chart", title: String(localized: "Geplant und trainiert"), symbol: "chart.bar.xaxis",
                              summary: String(localized: "Minuten der letzten 14 Tage.")),
                LayoutSection(id: "days", title: String(localized: "Tage"), symbol: "list.bullet",
                              summary: String(localized: "Jeder Tag mit Plan gegen Training."))
            ]
        }
    }

    public func section(_ id: String) -> LayoutSection? {
        sections.first { $0.id == id }
    }
}

/// Ein Bereich eines Bildschirms. Pflichtbereiche (`isRequired`) lassen sich verschieben, aber nicht ausblenden.
public struct LayoutSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let summary: String
    public let isRequired: Bool

    public init(id: String, title: String, symbol: String, summary: String, isRequired: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self.isRequired = isRequired
    }
}

/// Die gespeicherte Anordnung eines Bildschirms: angezeigte Bereiche in ihrer Reihenfolge, ausgeblendete daneben.
public struct ScreenLayout: Codable, Equatable, Sendable {
    public var visible: [String]
    public var hidden: [String]

    public init(visible: [String], hidden: [String] = []) {
        self.visible = visible
        self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey {
        case visible, hidden
    }

    /// Nachsichtig, damit eine gespeicherte Anordnung jedes Update übersteht.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visible = (try? container.decode([String].self, forKey: .visible)) ?? []
        hidden = (try? container.decode([String].self, forKey: .hidden)) ?? []
    }

    /// Standard: alle Bereiche in ihrer Reihenfolge, keiner ausgeblendet.
    public static func standard(for screen: LayoutScreen) -> ScreenLayout {
        ScreenLayout(visible: screen.sections.map(\.id))
    }

    /// Die Anordnung für diese App-Version: unbekannte Bereiche fallen weg, jeder Bereich steht genau einmal da,
    /// Pflichtbereiche sind sichtbar. Ein Bereich, den es beim Speichern noch nicht gab, erscheint hinter seinem Vorgänger
    /// aus der Standard-Reihenfolge (oder am Anfang).
    public func updated(for screen: LayoutScreen) -> ScreenLayout {
        let catalog = screen.sections
        let ids = Set(catalog.map(\.id))
        var seen = Set<String>()
        var visible = self.visible.filter { ids.contains($0) && seen.insert($0).inserted }
        var hidden: [String] = []
        for id in self.hidden where ids.contains(id) && seen.insert(id).inserted {
            if screen.section(id)?.isRequired == true {
                visible.append(id)
            } else {
                hidden.append(id)
            }
        }
        for (index, section) in catalog.enumerated() where !seen.contains(section.id) {
            let predecessor = catalog[..<index].reversed().first { visible.contains($0.id) }
            let position = predecessor.flatMap { visible.firstIndex(of: $0.id) }.map { $0 + 1 } ?? 0
            visible.insert(section.id, at: position)
        }
        return ScreenLayout(visible: visible, hidden: hidden)
    }
}

/// Wo die Anordnungen liegen.
public protocol ScreenLayoutStoring {
    /// `nil`, solange nichts gespeichert ist (oder das Gespeicherte unlesbar ist): Dann gilt der Standard.
    func load(_ screen: LayoutScreen) -> ScreenLayout?
    func save(_ layout: ScreenLayout, for screen: LayoutScreen) throws
    func remove(_ screen: LayoutScreen)
}

/// Auf dem Gerät, in den Einstellungen der App, je Bildschirm ein Eintrag.
public struct UserDefaultsScreenLayoutStore: ScreenLayoutStoring {
    static func storageKey(_ screen: LayoutScreen) -> String { "layout.\(screen.rawValue)" }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(_ screen: LayoutScreen) -> ScreenLayout? {
        guard let data = defaults.data(forKey: Self.storageKey(screen)) else { return nil }
        return try? JSONDecoder().decode(ScreenLayout.self, from: data)
    }

    public func save(_ layout: ScreenLayout, for screen: LayoutScreen) throws {
        defaults.set(try JSONEncoder().encode(layout), forKey: Self.storageKey(screen))
    }

    public func remove(_ screen: LayoutScreen) {
        defaults.removeObject(forKey: Self.storageKey(screen))
    }
}

/// Die Bereiche aller Bildschirme: umsortieren, ausblenden, wieder hinzufügen, zurücksetzen. Jede Änderung wird sofort
/// auf dem Gerät gespeichert.
@MainActor
public final class ScreenLayouts: ObservableObject {
    @Published public private(set) var layouts: [LayoutScreen: ScreenLayout]

    private let store: ScreenLayoutStoring

    public init(store: ScreenLayoutStoring) {
        self.store = store
        var layouts: [LayoutScreen: ScreenLayout] = [:]
        for screen in LayoutScreen.allCases {
            layouts[screen] = (store.load(screen) ?? .standard(for: screen)).updated(for: screen)
        }
        self.layouts = layouts
    }

    public func layout(_ screen: LayoutScreen) -> ScreenLayout {
        layouts[screen] ?? .standard(for: screen)
    }

    /// Die angezeigten Bereiche in ihrer Reihenfolge.
    public func visible(_ screen: LayoutScreen) -> [LayoutSection] {
        layout(screen).visible.compactMap { screen.section($0) }
    }

    /// Die ausgeblendeten Bereiche, die sich wieder hinzufügen lassen.
    public func hidden(_ screen: LayoutScreen) -> [LayoutSection] {
        layout(screen).hidden.compactMap { screen.section($0) }
    }

    public func isStandard(_ screen: LayoutScreen) -> Bool {
        layout(screen) == .standard(for: screen)
    }

    /// Verschiebt angezeigte Bereiche wie `List.onMove`: `destination` ist die Stelle vor dem Verschieben.
    public func move(_ screen: LayoutScreen, fromOffsets source: IndexSet, toOffset destination: Int) {
        var layout = self.layout(screen)
        let moving = source.filter { layout.visible.indices.contains($0) }
        guard !moving.isEmpty else { return }
        let moved = moving.map { layout.visible[$0] }
        let remaining = layout.visible.enumerated().filter { !moving.contains($0.offset) }.map(\.element)
        let index = min(max(destination - moving.filter { $0 < destination }.count, 0), remaining.count)
        layout.visible = Array(remaining[..<index]) + moved + Array(remaining[index...])
        save(layout, for: screen)
    }

    /// Eine Position nach oben (`-1`) oder unten (`1`), etwa für VoiceOver.
    public func move(_ screen: LayoutScreen, section id: String, by offset: Int) {
        var layout = self.layout(screen)
        guard let from = layout.visible.firstIndex(of: id) else { return }
        let to = from + offset
        guard layout.visible.indices.contains(to) else { return }
        layout.visible.swapAt(from, to)
        save(layout, for: screen)
    }

    /// Blendet einen Bereich aus. Pflichtbereiche bleiben.
    public func hide(_ screen: LayoutScreen, section id: String) {
        guard screen.section(id)?.isRequired == false else { return }
        var layout = self.layout(screen)
        guard let index = layout.visible.firstIndex(of: id) else { return }
        layout.visible.remove(at: index)
        layout.hidden.append(id)
        save(layout, for: screen)
    }

    /// Blendet die angezeigten Bereiche an diesen Stellen aus (Wischen zum Löschen); Pflichtbereiche bleiben.
    public func hide(_ screen: LayoutScreen, atOffsets offsets: IndexSet) {
        let visible = layout(screen).visible
        let ids = offsets.filter { visible.indices.contains($0) }.map { visible[$0] }
        for id in ids {
            hide(screen, section: id)
        }
    }

    /// Fügt einen ausgeblendeten Bereich wieder hinzu, am Ende.
    public func show(_ screen: LayoutScreen, section id: String) {
        var layout = self.layout(screen)
        guard let index = layout.hidden.firstIndex(of: id) else { return }
        layout.hidden.remove(at: index)
        layout.visible.append(id)
        save(layout, for: screen)
    }

    /// Zurück zur Standard-Anordnung des Bildschirms.
    public func reset(_ screen: LayoutScreen) {
        layouts[screen] = .standard(for: screen)
        store.remove(screen)
    }

    private func save(_ layout: ScreenLayout, for screen: LayoutScreen) {
        guard layout != self.layout(screen) else { return }
        layouts[screen] = layout
        try? store.save(layout, for: screen)
    }
}
