import Charts
import SwiftUI
import SwimInstructorCore

/// Verlauf: Was war geplant, was hast du gemacht? Die letzten 4 Wochen, über alle Sportarten.
struct HistoryView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader

    private let calculator = MultiSportAdherenceCalculator()

    var body: some View {
        NavigationStack {
            let entries = calculator.entries(
                plans: loader.planHistory,
                workouts: loader.reading?.allWorkouts ?? [],
                now: Date()
            )
            List {
                Group {
                    workoutsSection
                    if entries.isEmpty {
                        Section {
                            Text("Noch kein Verlauf. Ab jetzt merkt sich die App jeden Tagesplan und legt ihn neben deine Einheiten. Rückwirkend gibt es nichts zu vergleichen.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        SummarySection(summary: calculator.summary(of: entries))
                        ChartSection(entries: entries)
                        Section("Tage") {
                            ForEach(entries) { entry in
                                NavigationLink {
                                    HistoryDayView(entry: entry, workouts: workouts(on: entry.date), input: statisticInput)
                                } label: {
                                    HistoryRow(entry: entry)
                                }
                            }
                        }
                    }
                }
                .cardRows()
            }
            .themedList()
            .navigationTitle("Verlauf")
            .settingsToolbar()
            .refreshable { await loader.refreshIfNeeded() }
        }
        .task { await loader.refreshIfNeeded() }
    }
}

extension HistoryView {
    /// Für die Werte im Detail einer Einheit (Trainingslast mit Ruhe- und Maximalpuls wie in der Statistik).
    fileprivate var statisticInput: StatisticInput {
        guard let reading = loader.reading else { return StatisticInput(workouts: [], now: Date()) }
        return StatisticInput(reading: reading, plans: loader.planHistory, now: Date())
    }

    /// Die Einheiten eines Tags (`yyyy-MM-dd`), neueste zuerst.
    fileprivate func workouts(on day: String) -> [Workout] {
        (loader.reading?.allWorkouts ?? [])
            .filter { PlanFormatting.isoDay($0.startDate) == day }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Die Einheiten aus Health (neueste zuerst), früher auf dem Heute-Bildschirm. Antippen öffnet die Einheit.
    @ViewBuilder
    fileprivate var workoutsSection: some View {
        Section("Letzte Einheiten") {
            if loader.isLoadingHealth && loader.reading == nil {
                HStack(spacing: 12) {
                    ForgeAnimation()
                    Text("Lese Health-Daten …").foregroundStyle(.secondary)
                }
            } else if let error = loader.healthError {
                Text("Health: \(error)").foregroundStyle(.red)
            } else if let workouts = loader.reading?.allWorkouts, !workouts.isEmpty {
                ForEach(workouts.prefix(20)) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout, input: statisticInput)
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                }
            } else {
                Text("Noch keine Einheiten gefunden")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Zusammenfassung

private struct SummarySection: View {
    let summary: PlanAdherenceSummary

    var body: some View {
        Section("Die letzten 4 Wochen") {
            if summary.plannedTrainingDays > 0 {
                LabeledContent("Geplante Einheiten") {
                    Text("\(summary.trainedDays) von \(summary.plannedTrainingDays) trainiert")
                }
            }
            if summary.restDays > 0 {
                LabeledContent("Ruhetage") {
                    Text("\(summary.restDaysKept) von \(summary.restDays) eingehalten")
                }
            }
            if summary.plannedTrainingDays == 0 && summary.restDays == 0 {
                Text("Noch kein abgeschlossener Tag.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Diagramm

private struct ChartSection: View {
    let entries: [MultiSportAdherenceEntry]

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let minutes: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    /// Geplante und trainierte Minuten über alle Sportarten, die letzten 14 Tage (älteste links).
    private var bars: [Bar] {
        let weekCalendar = WeekCalendar()
        return entries
            .prefix(14)
            .reversed()
            .flatMap { entry -> [Bar] in
                guard let date = weekCalendar.date(from: entry.date) else { return [] }
                return [
                    Bar(date: date, kind: "Geplant", minutes: entry.comparisons.reduce(0) { $0 + $1.plannedMinutes }),
                    Bar(date: date, kind: "Trainiert", minutes: entry.comparisons.reduce(0) { $0 + $1.actualMinutes })
                ]
            }
    }

    var body: some View {
        let data = bars
        if data.contains(where: { $0.minutes > 0 }) {
            Section {
                Chart(data) { bar in
                    BarMark(
                        x: .value("Tag", bar.date, unit: .day),
                        y: .value("Minuten", bar.minutes)
                    )
                    .foregroundStyle(by: .value("Art", bar.kind))
                    .position(by: .value("Art", bar.kind))
                }
                .chartForegroundStyleScale(["Geplant": Color.gray.opacity(0.5), "Trainiert": Color.blue])
                .frame(height: 180)
                .accessibilityLabel("Geplante und trainierte Minuten der letzten Tage")
            } header: {
                Text("Geplant und trainiert")
            } footer: {
                Text("Minuten über alle Sportarten, die letzten 14 Tage mit gespeichertem Plan.")
            }
        }
    }
}

// MARK: - Tag

/// Ein Tag des Verlaufs: Plan gegen Training, die geplanten Einheiten und die gemachten (antippen öffnet sie).
private struct HistoryDayView: View {
    let entry: MultiSportAdherenceEntry
    let workouts: [Workout]
    let input: StatisticInput

    private let registry = SportRegistry.standard

    var body: some View {
        List {
            Group {
                Section {
                    HistoryRow(entry: entry)
                }
                if !entry.plan.sessions.isEmpty {
                    Section("Geplant") {
                        ForEach(Array(entry.plan.sessions.enumerated()), id: \.offset) { _, session in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(
                                    PlanV2Formatting.sessionTitle(sport: session.sport, amount: session.amount, unit: session.unit),
                                    systemImage: registry.symbolName(for: session.sport)
                                )
                                if !session.focus.isEmpty {
                                    Text(session.focus)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Trainiert") {
                    if workouts.isEmpty {
                        Text("Keine Einheit an diesem Tag.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout, input: input)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                    }
                }
                if !entry.plan.rationale.isEmpty {
                    Section("Warum dieser Plan") {
                        Text(entry.plan.rationale)
                            .font(.callout)
                    }
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(PlanFormatting.germanDate(entry.date))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Zeile

/// Ein Tag mit Plan: Ausgang und je Sportart geplant gegen gemacht. Auch in der Statistik ("Plan erfüllt").
struct HistoryRow: View {
    let entry: MultiSportAdherenceEntry

    private let registry = SportRegistry.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(PlanFormatting.germanDate(entry.date))
                    .font(.subheadline)
                Spacer()
                Label(PlanV2Formatting.outcomeText(entry.outcome), systemImage: Self.symbol(entry.outcome))
                    .font(.caption)
                    .foregroundStyle(Self.color(entry.outcome))
            }
            if entry.plan.isRestDay {
                Text("Geplant: Ruhetag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.comparisons) { comparison in
                HStack(spacing: 6) {
                    Image(systemName: registry.symbolName(for: comparison.sport))
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(line(comparison))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "Schwimmen: 1.200 m von 1.500 m", "Laufen: nicht gemacht (40 min geplant)", "Rad: 45 min, nicht geplant".
    private func line(_ comparison: SportComparison) -> String {
        let name = registry.displayName(for: comparison.sport)
        if !comparison.isPlanned {
            return "\(name): \(PlanV2Formatting.amount(comparison.actual, unit: comparison.unit)), nicht geplant"
        }
        if comparison.workoutCount == 0 {
            return "\(name): nicht gemacht (\(PlanV2Formatting.amount(comparison.planned, unit: comparison.unit)) geplant)"
        }
        return "\(name): \(PlanV2Formatting.comparison(planned: comparison.planned, actual: comparison.actual, unit: comparison.unit))"
    }

    private static func symbol(_ outcome: AdherenceOutcome) -> String {
        switch outcome {
        case .followed, .restKept: return "checkmark.circle.fill"
        case .shorter, .longer: return "arrow.up.arrow.down.circle"
        case .missed: return "xmark.circle"
        case .restBroken: return "exclamationmark.circle"
        case .pending: return "clock"
        }
    }

    private static func color(_ outcome: AdherenceOutcome) -> Color {
        switch outcome {
        case .followed, .restKept: return .green
        case .shorter, .longer, .restBroken: return .orange
        case .missed: return .red
        case .pending: return .secondary
        }
    }
}
