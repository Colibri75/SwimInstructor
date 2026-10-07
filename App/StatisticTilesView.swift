import Charts
import SwiftUI
import SwimInstructorCore

/// Die Kacheln der Statistik, jede eine eigene Zeile der Liste. Tippen: die Kachel groß mit allen Werten
/// (`StatisticDetailView`). Lange drücken: Sportart, Kennzahl und Zeitraum wählen oder die Kachel entfernen. Nach links
/// wischen: entfernen. Mit "Bearbeiten" entfernen und umsortieren. Gespeichert wird auf dem Gerät (`StatisticDashboard`).
struct StatisticTileRows: View {
    @ObservedObject var dashboard: StatisticDashboard
    let input: StatisticInput
    /// Beim Bearbeiten (entfernen, umsortieren) öffnen Tippen und langes Drücken nichts.
    var isEditing = false
    /// Öffnet das Detail einer Kachel. Die Navigation hängt am Dashboard, nicht in dieser Liste.
    let onOpen: (StatisticTile) -> Void

    private let calculator = StatisticCalculator()

    var body: some View {
        ForEach(calculator.results(for: dashboard.tiles, input: input)) { result in
            StatisticTileView(result: result, showsDisclosure: !isEditing)
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
                .onTapGesture {
                    if !isEditing { onOpen(result.tile) }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onOpen(result.tile) }
                .contextMenu {
                    if !isEditing {
                        StatisticTileMenu(dashboard: dashboard, tile: result.tile)
                    }
                }
                .accessibilityAction(named: "Nach vorn") { dashboard.move(result.tile.id, by: -1) }
                .accessibilityAction(named: "Nach hinten") { dashboard.move(result.tile.id, by: 1) }
                .accessibilityAction(named: "Kachel entfernen") { dashboard.remove(result.tile.id) }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .onDelete { offsets in
            withAnimation { dashboard.remove(atOffsets: offsets) }
        }
        .onMove { source, destination in
            dashboard.move(fromOffsets: source, toOffset: destination)
        }
    }
}

// MARK: - Kachel

/// Eine Kachel über die ganze Breite: Sportart und Zeitraum, Kennzahl, Wert, Verlauf, Vergleich mit dem Zeitraum davor.
struct StatisticTileView: View {
    let result: StatisticResult
    /// Pfeil rechts: Antippen öffnet das Detail (nicht in der Vorschau beim Hinzufügen).
    var showsDisclosure = true

    private var definition: StatisticDefinition { result.definition }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: StatisticFormatting.symbolName(result.tile.sport))
                Text(StatisticFormatting.sportName(result.tile.sport))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(result.tile.period.displayName)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(definition.displayName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(StatisticFormatting.value(result.value, format: definition.format))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                if result.value != nil && !definition.unit.isEmpty {
                    Text(definition.unit)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            StatisticSparkline(result: result)
                .frame(height: 64)

            if let comparison = StatisticFormatting.comparison(result) {
                Label {
                    Text(comparison)
                } icon: {
                    Image(systemName: trendSymbol)
                }
                .font(.subheadline)
                .foregroundStyle(trendColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            if let detail = StatisticFormatting.detail(result) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .offset(y: 30)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatisticFormatting.accessibilityLabel(result))
        .accessibilityHint("Öffnet die Details. Lange drücken, um Sportart, Kennzahl und Zeitraum zu ändern.")
    }

    private var trendSymbol: String {
        switch StatisticFormatting.trend(result) {
        case .up?: return "arrow.up.right"
        case .down?: return "arrow.down.right"
        case .flat?: return "arrow.right"
        case nil: return "minus"
        }
    }

    private var trendColor: Color {
        switch StatisticFormatting.assessment(result) {
        case .better: return .green
        case .worse: return .orange
        case .neutral: return .secondary
        }
    }
}

/// Kleiner Verlauf ohne Achsen: Balken für Summen (Umfang, Zeit), Linie für Mittelwerte (Pace, Puls). Tage, die noch
/// kommen, bleiben als Lücke stehen.
private struct StatisticSparkline: View {
    let result: StatisticResult

    private var isTotal: Bool { result.definition.measure.isTotal }

    private var isEmpty: Bool {
        let values = result.series.compactMap(\.value)
        return values.isEmpty || (isTotal && values.allSatisfy { $0 == 0 })
    }

    var body: some View {
        if isEmpty {
            Color.clear
        } else {
            Chart {
                ForEach(Array(result.series.enumerated()), id: \.offset) { index, point in
                    if let value = point.value {
                        if isTotal {
                            BarMark(x: .value("Abschnitt", String(index)), y: .value("Wert", value))
                                .foregroundStyle(Color.accentColor.gradient)
                                .cornerRadius(2)
                        } else {
                            LineMark(x: .value("Abschnitt", String(index)), y: .value("Wert", value))
                                .foregroundStyle(Color.accentColor)
                            PointMark(x: .value("Abschnitt", String(index)), y: .value("Wert", value))
                                .foregroundStyle(Color.accentColor)
                                .symbolSize(14)
                        }
                    }
                }
            }
            .chartXScale(domain: result.series.indices.map { String($0) })
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Auswahl

/// Kontextmenü einer Kachel: Sportart, Kennzahl und Zeitraum, Entfernen.
private struct StatisticTileMenu: View {
    @ObservedObject var dashboard: StatisticDashboard
    let tile: StatisticTile

    var body: some View {
        Menu {
            Picker("Sportart", selection: sport) {
                ForEach(dashboard.sports, id: \.self) { sport in
                    Label(StatisticFormatting.sportName(sport), systemImage: StatisticFormatting.symbolName(sport))
                        .tag(sport?.rawValue ?? "")
                }
            }
        } label: {
            Label("Sportart: \(StatisticFormatting.sportName(tile.sport))", systemImage: StatisticFormatting.symbolName(tile.sport))
        }
        Menu {
            Picker("Kennzahl", selection: metric) {
                ForEach(dashboard.catalog(for: tile.sport)) { definition in
                    Text(definition.displayName).tag(definition.metric)
                }
            }
        } label: {
            Label("Kennzahl: \(currentMetricName)", systemImage: "number")
        }
        Menu {
            Picker("Zeitraum", selection: period) {
                ForEach(StatisticPeriod.allCases, id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
        } label: {
            Label("Zeitraum: \(tile.period.displayName)", systemImage: "calendar")
        }
        Divider()
        Button(role: .destructive) {
            withAnimation { dashboard.remove(tile.id) }
        } label: {
            Label("Kachel entfernen", systemImage: "trash")
        }
    }

    private var currentMetricName: String {
        dashboard.catalog(for: tile.sport).first { $0.metric == tile.metric }?.displayName ?? tile.metric.rawValue
    }

    /// Leerer Text: alle Sportarten.
    private var sport: Binding<String> {
        Binding(
            get: { tile.sport?.rawValue ?? "" },
            set: { dashboard.setSport($0.isEmpty ? nil : SportID(rawValue: $0), for: tile.id) }
        )
    }

    private var metric: Binding<StatisticMetric> {
        Binding(get: { tile.metric }, set: { dashboard.setMetric($0, for: tile.id) })
    }

    private var period: Binding<StatisticPeriod> {
        Binding(get: { tile.period }, set: { dashboard.setPeriod($0, for: tile.id) })
    }
}

/// Neue Kachel: Sportart, Kennzahl und Zeitraum wählen, mit Vorschau aus den echten Daten.
struct AddStatisticTileSheet: View {
    @ObservedObject var dashboard: StatisticDashboard
    let input: StatisticInput

    @Environment(\.dismiss) private var dismiss
    /// Leerer Text: alle Sportarten.
    @State private var sport = ""
    @State private var metric = StatisticMetric.duration
    @State private var period = StatisticPeriod.standard

    private var sportID: SportID? { sport.isEmpty ? nil : SportID(rawValue: sport) }

    private var preview: StatisticResult {
        StatisticCalculator().result(for: StatisticTile(sport: sportID, metric: metric, period: period), input: input)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sportart", selection: $sport) {
                        ForEach(dashboard.sports, id: \.self) { sport in
                            Text(StatisticFormatting.sportName(sport)).tag(sport?.rawValue ?? "")
                        }
                    }
                    Picker("Kennzahl", selection: $metric) {
                        ForEach(dashboard.catalog(for: sportID)) { definition in
                            Text(definition.displayName).tag(definition.metric)
                        }
                    }
                    Picker("Zeitraum", selection: $period) {
                        ForEach(StatisticPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                }
                Section("Vorschau") {
                    StatisticTileView(result: preview, showsDisclosure: false)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            // Die neue Sportart hat die Kennzahl vielleicht nicht: dann ihre erste.
            .onChange(of: sport) { _, _ in
                let catalog = dashboard.catalog(for: sportID)
                if !catalog.contains(where: { $0.metric == metric }), let first = catalog.first {
                    metric = first.metric
                }
            }
            .navigationTitle("Kachel hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        dashboard.add(sport: sportID, metric: metric, period: period)
                        dismiss()
                    }
                }
            }
        }
    }
}
