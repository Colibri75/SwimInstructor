import SwiftUI
import WidgetKit
import SwimInstructorCore

/// Komplikationen auf dem Zifferblatt: die nächste Einheit aus dem Plan der Watch. Tippen öffnet die Watch-App.
@main
struct PeaksmithWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextSessionComplication()
    }
}

struct NextSessionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSession", provider: PlanGlanceProvider()) { entry in
            NextSessionComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Nächste Einheit")
        .description("Was dein Coach für heute plant.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct NextSessionComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlanGlanceEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            PlanGlanceRectangularView(entry: entry)
        case .accessoryInline:
            Text(PlanGlanceText(entry: entry).inline)
        case .accessoryCorner:
            let text = PlanGlanceText(entry: entry)
            Image(systemName: text.first?.symbolName ?? (text.isRestDay ? "moon.zzz" : "figure.mixed.cardio"))
                .font(.title3)
                .widgetAccentable()
                .widgetLabel(text.first?.title ?? (text.isRestDay ? "Ruhetag" : "Peaksmith"))
        default:
            PlanGlanceCircularView(entry: entry)
        }
    }
}
