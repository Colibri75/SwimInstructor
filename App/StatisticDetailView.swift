import Charts
import SwiftUI
import SwimInstructorCore

/// Eine Kachel groß: Diagramm mit Achsen, ein Tipp auf einen Balken oder Punkt zeigt, was dahinter steckt (die
/// Einheiten, Tageswerte oder Plantage dieses Tags oder dieser Woche). Darunter alle Abschnitte als Liste.
struct StatisticDetailView: View {
    @ObservedObject var dashboard: StatisticDashboard
    let tileID: UUID
    let input: StatisticInput

    /// Start des gewählten Abschnitts; ohne Auswahl der jüngste mit Wert.
    @State private var selectedStart: Date?

    private let calculator = StatisticCalculator()

    var body: some View {
        if let tile = dashboard.tiles.first(where: { $0.id == tileID }) {
            content(calculator.result(for: tile, input: input))
        } else {
            ContentUnavailableView("Kachel entfernt", systemImage: "chart.bar")
        }
    }

    private func content(_ result: StatisticResult) -> some View {
        let selected = selectedPoint(in: result)
        return List {
            Group {
                Section {
                    StatisticDetailHeader(result: result)
                    StatisticDetailChart(result: result, selected: selected) { point in
                        withAnimation(.easeInOut(duration: 0.15)) { selectedStart = point.start }
                    }
                } footer: {
                    Text("Auf einen Balken oder Punkt tippen, um zu sehen, was dahinter steckt.")
                }
                if let selected {
                    StatisticBreakdownSection(
                        result: result,
                        breakdown: calculator.breakdown(of: result, at: selected, input: input),
                        input: input
                    )
                }
                Section("Alle Abschnitte") {
                    ForEach(pastPoints(of: result).reversed()) { point in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedStart = point.start }
                        } label: {
                            HStack {
                                Text(StatisticFormatting.pointTitle(point))
                                Spacer()
                                Text(StatisticFormatting.text(point.value, definition: result.definition))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                                    .opacity(point.start == selected?.start ? 1 : 0)
                                    .accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(point.start == selected?.start ? .isSelected : [])
                    }
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(result.definition.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Abschnitte bis heute; kommende Tage der Woche haben noch nichts dahinter.
    private func pastPoints(of result: StatisticResult) -> [StatisticPoint] {
        result.series.filter { $0.start <= input.now }
    }

    private func selectedPoint(in result: StatisticResult) -> StatisticPoint? {
        if let selectedStart, let point = result.series.first(where: { $0.start == selectedStart }) {
            return point
        }
        let past = pastPoints(of: result)
        return past.last { $0.value != nil && $0.value != 0 } ?? past.last
    }
}

// MARK: - Kopf

/// Sportart, Zeitraum, Wert und Vergleich wie auf der Kachel, nur größer.
private struct StatisticDetailHeader: View {
    let result: StatisticResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "\(StatisticFormatting.sportName(result.tile.sport)) · \(result.tile.period.displayName)",
                systemImage: StatisticFormatting.symbolName(result.tile.sport)
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(StatisticFormatting.value(result.value, format: result.definition.format))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                if result.value != nil && !result.definition.unit.isEmpty {
                    Text(result.definition.unit)
                        .foregroundStyle(.secondary)
                }
            }
            if let comparison = StatisticFormatting.comparison(result) {
                Text(comparison)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let detail = StatisticFormatting.detail(result) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Diagramm

/// Großer Verlauf mit Achsen. Ein Tipp wählt den Abschnitt unter dem Finger; der gewählte ist kräftig, die anderen blass.
private struct StatisticDetailChart: View {
    let result: StatisticResult
    let selected: StatisticPoint?
    let onSelect: (StatisticPoint) -> Void

    private var isTotal: Bool { result.definition.measure.isTotal }
    private var format: StatisticFormat { result.definition.format }

    var body: some View {
        let labels = result.series.map { StatisticFormatting.axisLabel($0) }
        VStack(alignment: .leading, spacing: 8) {
            if let selected {
                HStack(alignment: .firstTextBaseline) {
                    Text(StatisticFormatting.pointTitle(selected))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(StatisticFormatting.text(selected.value, definition: result.definition))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            Chart {
                ForEach(Array(result.series.enumerated()), id: \.offset) { index, point in
                    if let value = point.value {
                        let isSelected = point.start == selected?.start
                        if isTotal {
                            BarMark(x: .value("Abschnitt", labels[index]), y: .value("Wert", value))
                                .foregroundStyle(isSelected ? Theme.accent : Theme.accent.opacity(0.35))
                                .cornerRadius(3)
                        } else {
                            LineMark(x: .value("Abschnitt", labels[index]), y: .value("Wert", value))
                                .foregroundStyle(Theme.accent.opacity(0.6))
                            PointMark(x: .value("Abschnitt", labels[index]), y: .value("Wert", value))
                                .foregroundStyle(Theme.accent)
                                .symbolSize(isSelected ? 160 : 50)
                        }
                    }
                }
            }
            .chartXScale(domain: labels)
            .chartYScale(domain: .automatic(includesZero: isTotal))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(StatisticFormatting.value(number, format: format))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        // Nur Tippen, kein Ziehen: Die Liste bleibt über dem Diagramm scrollbar.
                        .gesture(
                            SpatialTapGesture().onEnded { tap in
                                guard let plotFrame = proxy.plotFrame, !result.series.isEmpty else { return }
                                let frame = geometry[plotFrame]
                                let x = tap.location.x - frame.minX
                                guard frame.width > 0, x >= 0, x <= frame.width else { return }
                                // Gleich breite Abschnitte nebeneinander: die Position sagt den Abschnitt.
                                let index = min(Int(x / frame.width * CGFloat(result.series.count)), result.series.count - 1)
                                onSelect(result.series[index])
                            }
                        )
                }
            }
            .frame(height: 260)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Was dahinter steckt

/// Der gewählte Abschnitt: seine Einheiten (antippen öffnet die Einheit), Tageswerte oder Plantage.
private struct StatisticBreakdownSection: View {
    let result: StatisticResult
    let breakdown: StatisticBreakdown
    let input: StatisticInput

    private let calculator = StatisticCalculator()

    var body: some View {
        Section {
            if breakdown.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            }
            ForEach(breakdown.workouts) { workout in
                NavigationLink {
                    WorkoutDetailView(workout: workout, input: input)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        WorkoutRow(workout: workout)
                        if let value = metricText(for: workout) {
                            Text(value)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .padding(.leading, 40)
                        }
                    }
                }
            }
            ForEach(breakdown.days) { day in
                LabeledContent {
                    Text(StatisticFormatting.text(day.value, definition: result.definition))
                        .monospacedDigit()
                } label: {
                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.defaultDigits).locale(AppLocale.current)))
                }
            }
            ForEach(breakdown.planDays) { entry in
                HistoryRow(entry: entry)
            }
        } header: {
            Text(StatisticFormatting.pointTitle(breakdown.point))
        }
    }

    /// Der Wert der Kennzahl für diese eine Einheit, wenn er nicht schon in der Zeile steht ("Pace pro km: 5:12 /km").
    private func metricText(for workout: Workout) -> String? {
        let definition = result.definition
        guard ![StatisticMetric.duration, .distance, .sessions, .averageHeartRate].contains(definition.metric),
              let value = calculator.value(definition, of: workout, input: input) else { return nil }
        return "\(StatisticFormatting.workoutValueName(definition)): \(StatisticFormatting.text(value, definition: definition))"
    }

    private var emptyText: String {
        let measure = result.definition.measure
        if measure.usesWorkouts { return String(localized: "Keine Einheit an diesen Tagen.") }
        if measure == .planAdherence { return String(localized: "Kein gespeicherter Plan an diesen Tagen.") }
        return String(localized: "Keine Messung an diesen Tagen.")
    }
}
