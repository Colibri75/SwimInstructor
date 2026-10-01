import Charts
import SwiftUI
import SwimInstructorCore

/// Fortschritt auf einen Blick: Weg zum Ziel, Wochenumfang und Pace-Entwicklung der letzten 8 Wochen.
struct DashboardView: View {
    @EnvironmentObject private var loader: TodayPlanLoader

    private let statistics = TrainingStatistics()

    var body: some View {
        NavigationStack {
            List {
                if let reading = loader.reading {
                    GoalSection(snapshot: reading.snapshot)
                    VolumeSection(weeks: statistics.weeklyVolumes(workouts: reading.workouts, now: Date()))
                    PaceSection(
                        samples: statistics.paceSamples(workouts: reading.workouts, now: Date()),
                        targetPace: reading.snapshot.goal.targetPaceSecondsPerHundredMeters
                    )
                } else if loader.isLoadingHealth {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Lese Health-Daten …").foregroundStyle(.secondary)
                    }
                } else if let error = loader.healthError {
                    Text("Health: \(error)").foregroundStyle(.red)
                } else {
                    Text("Noch keine Daten. Öffne zuerst den Tab \"Heute\".")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dashboard")
            // Liest nur Health neu. Einen neuen Plan holt erst der Tab "Heute" (kostet einen Claude-Aufruf).
            .refreshable { await loader.refreshIfNeeded() }
        }
        .task { await loader.refreshIfNeeded() }
    }
}

// MARK: - Ziel

private struct GoalSection: View {
    let snapshot: AthleteStateSnapshot

    private var goal: AthleteStateSnapshot.GoalSummary { snapshot.goal }

    var body: some View {
        Section("Dein Ziel") {
            LabeledContent("Ziel") {
                Text("\(PlanFormatting.meters(Int(goal.distanceMeters))) in \(Int(goal.targetDurationSeconds / 60)) min")
            }
            LabeledContent("Bis zum Ziel") {
                Text("\(goal.daysUntilGoal) Tage")
            }
            VStack(alignment: .leading, spacing: 6) {
                let longest = snapshot.volume.longestSessionMeters
                ProgressView(value: min(longest, goal.distanceMeters), total: goal.distanceMeters)
                Text("Längste Einheit (4 Wochen): \(PlanFormatting.meters(Int(longest))) von \(PlanFormatting.meters(Int(goal.distanceMeters)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            paceRow
        }
    }

    @ViewBuilder
    private var paceRow: some View {
        if let pace = snapshot.pace.recentPaceSecondsPerHundredMeters {
            LabeledContent("Pace (4 Wochen)") {
                Text("\(PlanFormatting.pace(pace)) /100 m")
            }
            if let gap = snapshot.pace.gapToTargetSecondsPerHundredMeters {
                Text(gap > 0
                     ? "Zielpace \(PlanFormatting.pace(goal.targetPaceSecondsPerHundredMeters)): noch \(Int(gap.rounded())) s pro 100 m zu langsam."
                     : "Zielpace \(PlanFormatting.pace(goal.targetPaceSecondsPerHundredMeters)) erreicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let trend = snapshot.pace.trendSecondsPerHundredMeters, trend != 0 {
                Text(trend < 0
                     ? "Gegenüber den 4 Wochen davor \(Int(abs(trend).rounded())) s pro 100 m schneller."
                     : "Gegenüber den 4 Wochen davor \(Int(trend.rounded())) s pro 100 m langsamer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Für die Pace fehlen Einheiten mit Strecke in den letzten 4 Wochen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Wochenumfang

private struct VolumeSection: View {
    let weeks: [WeeklyVolume]

    var body: some View {
        Section {
            if weeks.allSatisfy({ $0.sessions == 0 }) {
                Text("In den letzten 8 Wochen keine Einheit.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(weeks) { week in
                    BarMark(
                        x: .value("Woche", week.weekStart, unit: .weekOfYear),
                        y: .value("Meter", week.meters)
                    )
                    .opacity(week.isCurrentWeek ? 0.5 : 1)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let meters = value.as(Double.self) {
                                Text(PlanFormatting.meters(Int(meters)))
                            }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Wochenumfang der letzten 8 Wochen")
                .accessibilityValue(summary)
            }
        } header: {
            Text("Wochenumfang")
        } footer: {
            Text("Die laufende Woche ist noch nicht vorbei und blasser dargestellt.")
        }
    }

    private var summary: String {
        weeks.map { "\(PlanFormatting.meters(Int($0.meters)))" }.joined(separator: ", ")
    }
}

// MARK: - Pace

private struct PaceSection: View {
    let samples: [PaceSample]
    let targetPace: Double

    var body: some View {
        Section {
            if samples.isEmpty {
                Text("Noch keine Einheit mit Strecke ab \(Int(TrainingStatistics.minimumDistanceForPace)) m in den letzten 8 Wochen.")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(samples) { sample in
                        PointMark(
                            x: .value("Datum", sample.date),
                            y: .value("Pace", sample.paceSecondsPer100m)
                        )
                    }
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Datum", sample.date),
                            y: .value("Pace", sample.paceSecondsPer100m)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.secondary)
                    }
                    RuleMark(y: .value("Ziel", targetPace))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(.green)
                        .annotation(position: .top, alignment: .leading) {
                            Text("Ziel \(PlanFormatting.pace(targetPace))")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let pace = value.as(Double.self) {
                                Text(PlanFormatting.pace(pace))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityLabel("Pace pro Einheit")
                .accessibilityValue(samples.map { PlanFormatting.pace($0.paceSecondsPer100m) }.joined(separator: ", "))
            }
        } header: {
            Text("Pace pro Einheit")
        } footer: {
            Text("Pro 100 m. Niedriger ist schneller. Die gestrichelte grüne Linie ist deine Zielpace. Die Pace enthält Pausen, weil Health die gesamte Dauer meldet.")
        }
    }

    /// Achse mit etwas Luft um die Werte und das Ziel, damit die Punkte nicht am Rand kleben.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.paceSecondsPer100m) + [targetPace]
        let low = (values.min() ?? targetPace) - 10
        let high = (values.max() ?? targetPace) + 10
        return low...high
    }
}
