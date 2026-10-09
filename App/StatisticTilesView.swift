import Charts
import SwiftUI
import SwimInstructorCore

/// Die Kacheln der Statistik, jede eine eigene Zeile der Liste. Tippen: die Kachel groß mit allen Werten
/// (`StatisticDetailView`). Hinzufügen, ändern, entfernen und umsortieren nur über "Bereiche anpassen"
/// (`ArrangeSectionsSheet`). Gespeichert wird auf dem Gerät (`StatisticDashboard`).
struct StatisticTileRows: View {
    @ObservedObject var dashboard: StatisticDashboard
    let input: StatisticInput
    /// Öffnet das Detail einer Kachel. Die Navigation hängt am Dashboard, nicht in dieser Liste.
    let onOpen: (StatisticTile) -> Void

    private let calculator = StatisticCalculator()

    var body: some View {
        ForEach(calculator.results(for: dashboard.tiles, input: input)) { result in
            StatisticTileView(result: result)
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture { onOpen(result.tile) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onOpen(result.tile) }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

// MARK: - Kachel

/// Eine Kachel über die ganze Breite: Sportart und Zeitraum, Kennzahl, Wert, Verlauf, Vergleich mit dem Zeitraum davor.
struct StatisticTileView: View {
    @AppStorage(Theme.greenWeakKey) private var greenWeak = false
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatisticFormatting.accessibilityLabel(result))
        .accessibilityHint("Öffnet die Details.")
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
        case .better: return Theme.done(greenWeak: greenWeak)
        case .worse: return Theme.caution(greenWeak: greenWeak)
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
                                .foregroundStyle(Theme.accent.gradient)
                                .cornerRadius(2)
                        } else {
                            LineMark(x: .value("Abschnitt", String(index)), y: .value("Wert", value))
                                .foregroundStyle(Theme.accent)
                            PointMark(x: .value("Abschnitt", String(index)), y: .value("Wert", value))
                                .foregroundStyle(Theme.accent)
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

/// Neue Kachel oder eine bestehende ändern: Sportart, Kennzahl und Zeitraum wählen, mit Vorschau aus den echten Daten.
struct AddStatisticTileSheet: View {
    @ObservedObject var dashboard: StatisticDashboard
    let input: StatisticInput
    /// Die Kachel, die geändert wird; `nil` für eine neue.
    let editedTile: StatisticTile?

    @Environment(\.dismiss) private var dismiss
    /// Leerer Text: alle Sportarten.
    @State private var sport: String
    @State private var metric: StatisticMetric
    @State private var period: StatisticPeriod

    init(dashboard: StatisticDashboard, input: StatisticInput, editing tile: StatisticTile? = nil) {
        self.dashboard = dashboard
        self.input = input
        self.editedTile = tile
        _sport = State(initialValue: tile?.sport?.rawValue ?? "")
        _metric = State(initialValue: tile?.metric ?? .duration)
        _period = State(initialValue: tile?.period ?? .standard)
    }

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
                .cardRows()
                Section("Vorschau") {
                    StatisticTileView(result: preview, showsDisclosure: false)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .themedList()
            // Die neue Sportart hat die Kennzahl vielleicht nicht: dann ihre erste.
            .onChange(of: sport) { _, _ in
                let catalog = dashboard.catalog(for: sportID)
                if !catalog.contains(where: { $0.metric == metric }), let first = catalog.first {
                    metric = first.metric
                }
            }
            .navigationTitle(editedTile == nil ? "Kachel hinzufügen" : "Kachel ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editedTile == nil ? "Hinzufügen" : "Sichern") {
                        if let editedTile {
                            dashboard.setSport(sportID, for: editedTile.id)
                            dashboard.setMetric(metric, for: editedTile.id)
                            dashboard.setPeriod(period, for: editedTile.id)
                        } else {
                            dashboard.add(sport: sportID, metric: metric, period: period)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
