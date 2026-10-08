import Charts
import SwiftUI
import SwimInstructorCore

/// Eine Einheit im Detail: wann, alle Werte, die ihre Sportart kennt (aus dem Katalog des Moduls), und der Pulsverlauf.
/// Darunter Sets und Bahnen (Schwimmen) oder Runden und Kilometer (Laufen, Rad), wie Fitness sie zeigt. Ein Tipp ins
/// Pulsdiagramm zeigt den Puls zu dieser Minute.
struct WorkoutDetailView: View {
    let workout: Workout
    /// Für die Trainingslast mit Ruhe- und Maximalpuls wie in der Statistik.
    let input: StatisticInput
    var heartRates: HeartRateRepository = HealthKitHeartRateRepository()
    var splits: WorkoutSplitRepository = HealthKitWorkoutSplitRepository()

    @State private var curve: HeartRateCurve?
    @State private var heartRateError: String?
    @State private var report: WorkoutSplitReport?
    @State private var splitError: String?

    private let calculator = StatisticCalculator()
    private let registry = SportRegistry.standard

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: registry.symbolName(for: workout.sport))
                        .font(.largeTitle)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(registry.displayName(for: workout.sport))
                            .font(.title2.weight(.semibold))
                        Text(StatisticFormatting.workoutTime(workout))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section("Werte") {
                ForEach(calculator.values(of: workout, input: input)) { item in
                    LabeledContent(StatisticFormatting.workoutValueName(item.definition)) {
                        Text(StatisticFormatting.text(item.value, definition: item.definition))
                            .monospacedDigit()
                    }
                }
                if let energy = workout.activeEnergyKilocalories, energy > 0 {
                    LabeledContent("Aktive Energie") {
                        Text("\(Int(energy.rounded())) kcal")
                            .monospacedDigit()
                    }
                }
            }
            .font(.body)

            if let report, !report.isEmpty {
                WorkoutSplitSections(report: report, field: field)
            } else if let splitError {
                Section("Runden") {
                    Text(splitError)
                        .foregroundStyle(.red)
                }
            }

            Section("Puls") {
                if let curve, !curve.points.isEmpty {
                    HeartRateChart(curve: curve, averageHeartRate: workout.averageHeartRate)
                } else if curve != nil {
                    Text("Keine Pulswerte für diese Einheit in Health.")
                        .foregroundStyle(.secondary)
                } else if let heartRateError {
                    Text("Puls: \(heartRateError)")
                        .foregroundStyle(.red)
                } else {
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Lese Pulswerte …").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(registry.displayName(for: workout.sport))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workout.id) {
            let samples = await loadHeartRate()
            await loadSplits(heartRates: samples)
        }
    }

    /// Hauptfeld der Sportart: entscheidet über Pace pro 100 m, pro km oder km/h und die Länge der Teilstrecken.
    private var field: LiveField {
        registry.module(for: workout.sport)?.recording.primaryField ?? .pacePerKilometer
    }

    private func loadHeartRate() async -> [HeartRateSample] {
        do {
            let samples = try await heartRates.heartRates(from: workout.startDate, to: workout.endDate)
            curve = HeartRateCurve(samples: samples, start: workout.startDate, end: workout.endDate)
            return samples
        } catch {
            heartRateError = error.localizedDescription
            return []
        }
    }

    private func loadSplits(heartRates samples: [HeartRateSample]) async {
        do {
            let data = try await splits.splitData(for: workout)
            report = WorkoutSplitBuilder.report(
                data: data,
                heartRates: samples,
                workoutStart: workout.startDate,
                workoutEnd: workout.endDate,
                splitLengthMeters: WorkoutSplitBuilder.splitLength(for: field)
            )
        } catch {
            splitError = error.localizedDescription
        }
    }
}

/// Sets mit ihren Bahnen (aufklappbar), Bahnen oder Runden außerhalb von Sets und gleich lange Teilstrecken. Je Zeile
/// groß die Zeit, darunter Strecke, Pace, Stil, Züge und Puls.
private struct WorkoutSplitSections: View {
    let report: WorkoutSplitReport
    let field: LiveField

    var body: some View {
        if !report.sets.isEmpty {
            Section(WorkoutSplitFormatting.setsTitle(field: field)) {
                ForEach(report.sets) { set in
                    if let rest = set.restBefore, rest >= 1 {
                        Label(WorkoutSplitFormatting.rest(rest), systemImage: "pause.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if set.laps.isEmpty {
                        SplitRow(title: WorkoutSplitFormatting.setTitle(set.summary.number, field: field), split: set.summary, field: field)
                    } else {
                        DisclosureGroup {
                            ForEach(set.laps) { lap in
                                SplitRow(
                                    title: WorkoutSplitFormatting.lapTitle(lap.number, field: field),
                                    split: lap,
                                    field: field,
                                    compact: true
                                )
                            }
                        } label: {
                            SplitRow(title: WorkoutSplitFormatting.setTitle(set.summary.number, field: field), split: set.summary, field: field)
                        }
                    }
                }
            }
        }
        if !report.laps.isEmpty {
            Section(WorkoutSplitFormatting.lapsTitle(field: field)) {
                ForEach(report.laps) { lap in
                    SplitRow(title: WorkoutSplitFormatting.lapTitle(lap.number, field: field), split: lap, field: field)
                }
            }
        }
        if let length = report.splitLengthMeters, !report.distanceSplits.isEmpty {
            Section(WorkoutSplitFormatting.splitsTitle(length: length)) {
                ForEach(report.distanceSplits) { split in
                    SplitRow(title: WorkoutSplitFormatting.splitTitle(split, length: length), split: split, field: field, showsDistance: false)
                }
            }
        }
    }
}

/// Eine Zeile: Titel und Zeit, darunter die Details.
private struct SplitRow: View {
    let title: String
    let split: WorkoutSplit
    let field: LiveField
    var compact = false
    var showsDistance = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(compact ? .body : .headline)
                Spacer()
                Text(WorkoutSplitFormatting.duration(split.duration))
                    .font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
                    .monospacedDigit()
            }
            let detail = WorkoutSplitFormatting.detail(split, field: field, includeDistance: showsDistance)
            if !detail.isEmpty {
                Text(detail)
                    .font(compact ? .footnote : .subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, compact ? 2 : 4)
        .accessibilityElement(children: .combine)
    }
}

/// Puls über die Minuten der Einheit. Tippen wählt die nächste Minute mit Messung.
private struct HeartRateChart: View {
    let curve: HeartRateCurve
    let averageHeartRate: Double?

    @State private var selected: HeartRateCurve.Point?

    private var lowerBound: Double { max((curve.minimum ?? 60) - 10, 0) }
    private var upperBound: Double { (curve.maximum ?? 180) + 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let selected {
                    Text("Nach \(Int(selected.minute.rounded())) min")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(selected.beatsPerMinute.rounded())) bpm")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text(summary)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Chart {
                ForEach(curve.points) { point in
                    AreaMark(
                        x: .value("Minute", point.minute),
                        yStart: .value("Untergrenze", lowerBound),
                        yEnd: .value("Puls", point.beatsPerMinute)
                    )
                    .foregroundStyle(Color.red.opacity(0.12))
                    LineMark(x: .value("Minute", point.minute), y: .value("Puls", point.beatsPerMinute))
                        .foregroundStyle(Color.red)
                        .interpolationMethod(.monotone)
                }
                if let averageHeartRate {
                    RuleMark(y: .value("Durchschnitt", averageHeartRate))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let selected {
                    RuleMark(x: .value("Minute", selected.minute))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    PointMark(x: .value("Minute", selected.minute), y: .value("Puls", selected.beatsPerMinute))
                        .foregroundStyle(Color.red)
                        .symbolSize(120)
                }
            }
            .chartYScale(domain: lowerBound...upperBound)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minute = value.as(Double.self) {
                            Text("\(Int(minute)) min")
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { tap in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = tap.location.x - geometry[plotFrame].minX
                                guard let minute = proxy.value(atX: x, as: Double.self) else { return }
                                let nearest = curve.points.min { abs($0.minute - minute) < abs($1.minute - minute) }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selected = nearest == selected ? nil : nearest
                                }
                            }
                        )
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Pulsverlauf")
            .accessibilityValue(summary)

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .opacity(selected == nil ? 0 : 1)
        }
        .padding(.vertical, 4)
    }

    /// "Ø 142 · min 98 · max 171 bpm"
    private var summary: String {
        var parts: [String] = []
        if let averageHeartRate { parts.append("Ø \(Int(averageHeartRate.rounded()))") }
        if let minimum = curve.minimum { parts.append("min \(Int(minimum.rounded()))") }
        if let maximum = curve.maximum { parts.append("max \(Int(maximum.rounded()))") }
        return parts.isEmpty ? "" : parts.joined(separator: " · ") + " bpm"
    }
}
