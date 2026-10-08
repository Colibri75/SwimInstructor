import SwiftUI
import WidgetKit
import SwimInstructorCore

/// Widgets auf dem Home- und Sperrbildschirm des iPhones: die nächste Einheit aus dem Plan. Tippen öffnet die App.
@main
struct PeaksmithWidgets: WidgetBundle {
    var body: some Widget {
        NextSessionWidget()
    }
}

struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSession", provider: PlanGlanceProvider()) { entry in
            NextSessionWidgetView(entry: entry)
        }
        .configurationDisplayName("Nächste Einheit")
        .description("Was dein Coach für heute plant, nach erledigtem Training für morgen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct NextSessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlanGlanceEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            PlanGlanceRectangularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        case .accessoryCircular:
            PlanGlanceCircularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text(PlanGlanceText(entry: entry).inline)
                .containerBackground(.clear, for: .widget)
        default:
            HomeScreenView(entry: entry, isWide: family == .systemMedium)
                .containerBackground(Theme.night, for: .widget)
        }
    }
}

/// Auf dem Home-Bildschirm: Nacht-Karte wie in Aktuell, Überschrift in Glut, je Einheit Symbol in Sportfarbe und Umfang.
private struct HomeScreenView: View {
    let entry: PlanGlanceEntry
    let isWide: Bool

    var body: some View {
        let text = PlanGlanceText(entry: entry)
        VStack(alignment: .leading, spacing: 6) {
            Text(text.heading ?? "Peaksmith")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Theme.ember)
            if text.heading == nil {
                Text(PlanGlanceText.openApp)
                    .font(.footnote)
                    .foregroundStyle(Theme.nightSecondary)
            } else if text.isRestDay {
                Label("Ruhetag", systemImage: "moon.zzz")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                ForEach(Array(text.items.prefix(isWide ? 3 : 2).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Image(systemName: item.symbolName)
                            .foregroundStyle(Color(rgb: item.colorRGB))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if isWide, !item.focus.isEmpty {
                                Text(item.focus)
                                    .font(.caption)
                                    .foregroundStyle(Theme.nightSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
