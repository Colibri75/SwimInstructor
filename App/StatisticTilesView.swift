import Charts
import SwiftUI
import SwimInstructorCore

/// Die Kacheln der Statistik. Lange drücken: Sportart, Kennzahl und Zeitraum wählen oder die Kachel entfernen. Ziehen
/// auf eine andere Kachel: Reihenfolge ändern. Gespeichert wird auf dem Gerät (`StatisticDashboard`).
struct StatisticTilesGrid: View {
    @ObservedObject var dashboard: StatisticDashboard
    let input: StatisticInput

    private let calculator = StatisticCalculator()
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let results = calculator.results(for: dashboard.tiles, input: input)
        if results.isEmpty {
            Text("Keine Kacheln. Über + kommt eine dazu.")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(results) { result in
                    StatisticTileView(result: result)
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
                        .contextMenu {
                            StatisticTileMenu(dashboard: dashboard, tile: result.tile)
                        }
                        .draggable(result.tile.id.uuidString) {
                            StatisticTileView(result: result)
                                .frame(width: 170)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                            withAnimation { dashboard.move(id, to: result.tile.id) }
                            return true
                        }
                        .accessibilityAction(named: "Nach vorn") { dashboard.move(result.tile.id, by: -1) }
                        .accessibilityAction(named: "Nach hinten") { dashboard.move(result.tile.id, by: 1) }
                        .accessibilityAction(named: "Kachel entfernen") { dashboard.remove(result.tile.id) }
                }
            }
        }
    }
}

// MARK: - Kachel

/// Eine Kachel: Sportart und Zeitraum, Kennzahl, Wert, Verlauf, Vergleich mit dem Zeitraum davor.
struct StatisticTileView: View {
    let result: StatisticResult

    private var definition: StatisticDefinition { result.definition }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: StatisticFormatting.symbolName(result.tile.sport))
                Text(StatisticFormatting.sportName(result.tile.sport))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(result.tile.period.displayName)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(definition.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(StatisticFormatting.value(result.value, format: definition.format))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                if result.value != nil && !definition.unit.isEmpty {
                    Text(definition.unit)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            StatisticSparkline(result: result)
                .frame(height: 34)

            if let comparison = StatisticFormatting.comparison(result) {
                Label {
                    Text(comparison)
                } icon: {
                    Image(systemName: trendSymbol)
                }
                .font(.caption2)
                .foregroundStyle(trendColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            if let detail = StatisticFormatting.detail(result) {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatisticFormatting.accessibilityLabel(result))
        .accessibilityHint("Lange drücken, um Sportart, Kennzahl und Zeitraum zu ändern.")
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
                    StatisticTileView(result: preview)
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
