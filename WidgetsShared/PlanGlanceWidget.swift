import SwiftUI
import WidgetKit
import SwimInstructorCore

/// Ein Stand für Widget und Komplikation: was die App zuletzt in die App-Gruppe geschrieben hat.
struct PlanGlanceEntry: TimelineEntry {
    let date: Date
    let glance: PlanGlance?
}

/// Liest den Stand der App; um Mitternacht kommt ein zweiter Eintrag, damit "Morgen" zu "Heute" wird.
struct PlanGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanGlanceEntry {
        PlanGlanceEntry(date: Date(), glance: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanGlanceEntry) -> Void) {
        let glance = PlanGlanceStore.shared().load()
        completion(PlanGlanceEntry(date: Date(), glance: context.isPreview ? (glance ?? Self.sample) : glance))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanGlanceEntry>) -> Void) {
        let now = Date()
        let glance = PlanGlanceStore.shared().load()
        var entries = [PlanGlanceEntry(date: now, glance: glance)]
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            entries.append(PlanGlanceEntry(date: midnight, glance: glance))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Für die Vorschau in der Widget-Galerie: die erste Sportart der App mit einer Stunde.
    static var sample: PlanGlance {
        let registry = SportRegistry.standard
        let sport = registry.ids.first ?? SportID(rawValue: "")
        return PlanGlance(
            date: PlanFormatting.isoDay(Date()),
            todayDone: false,
            items: [
                PlanGlance.Item(
                    sport: sport,
                    title: PlanV2Formatting.sessionTitle(sport: sport, amount: 45, unit: .minutes, registry: registry),
                    focus: String(localized: "Locker"),
                    symbolName: registry.symbolName(for: sport),
                    colorRGB: registry.colorRGB(for: sport)
                )
            ],
            updatedAt: Date()
        )
    }
}

/// Die Texte eines Stands: Überschrift, Zeilen, Hinweis ohne Plan.
struct PlanGlanceText {
    let entry: PlanGlanceEntry

    var heading: String? { entry.glance?.heading(now: entry.date) }
    /// Die Einheiten, solange der Stand von heute oder für morgen ist.
    var items: [PlanGlance.Item] { heading == nil ? [] : entry.glance?.items ?? [] }
    var isRestDay: Bool { heading != nil && items.isEmpty }
    var first: PlanGlance.Item? { items.first }

    /// Ohne aktuellen Stand.
    static var openApp: String { String(localized: "Öffne Peaksmith für deinen Plan") }

    /// Eine Zeile: "Heute: Laufen · 45 min", "Morgen: Ruhetag".
    var inline: String {
        guard let heading else { return Self.openApp }
        if isRestDay { return String(localized: "\(heading): Ruhetag") }
        let more = items.count > 1 ? " +\(items.count - 1)" : ""
        return "\(heading): \(first?.title ?? "")\(more)"
    }
}

/// Rechteckig (Sperrbildschirm, Zifferblatt): Überschrift, Einheiten mit Symbol, bei einer Einheit ihr Schwerpunkt.
struct PlanGlanceRectangularView: View {
    let entry: PlanGlanceEntry

    var body: some View {
        let text = PlanGlanceText(entry: entry)
        VStack(alignment: .leading, spacing: 1) {
            if let heading = text.heading {
                Text(heading)
                    .font(.headline)
                    .widgetAccentable()
                if text.isRestDay {
                    Text("Ruhetag")
                } else {
                    ForEach(Array(text.items.prefix(2).enumerated()), id: \.offset) { _, item in
                        Label(item.title, systemImage: item.symbolName)
                            .lineLimit(1)
                    }
                    if text.items.count == 1, let focus = text.first?.focus, !focus.isEmpty {
                        Text(focus)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(PlanGlanceText.openApp)
                    .lineLimit(2)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Rund: das Symbol der ersten Einheit (Ruhetag: Mond).
struct PlanGlanceCircularView: View {
    let entry: PlanGlanceEntry

    var body: some View {
        let text = PlanGlanceText(entry: entry)
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: text.first?.symbolName ?? (text.isRestDay ? "moon.zzz" : "figure.mixed.cardio"))
                .font(.title3)
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.inline)
    }
}
