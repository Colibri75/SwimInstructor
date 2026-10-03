import Charts
import SwiftUI
import SwimInstructorCore

/// Verlauf: Was war geplant, was hast du geschwommen? Die letzten 4 Wochen.
struct HistoryView: View {
    @EnvironmentObject private var loader: TodayPlanLoader

    private let calculator = PlanAdherenceCalculator()

    var body: some View {
        NavigationStack {
            let entries = calculator.entries(
                plans: loader.planHistory,
                workouts: loader.reading?.workouts ?? [],
                now: Date()
            )
            List {
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
                            HistoryRow(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("Verlauf")
            .refreshable { await loader.refreshIfNeeded() }
        }
        .task { await loader.refreshIfNeeded() }
    }
}

extension HistoryView {
    /// Die Einheiten aus Health (neueste zuerst), früher auf dem Heute-Bildschirm.
    @ViewBuilder
    fileprivate var workoutsSection: some View {
        Section("Letzte Einheiten") {
            if loader.isLoadingHealth && loader.reading == nil {
                ProgressView()
            } else if let error = loader.healthError {
                Text("Health: \(error)").foregroundStyle(.red)
            } else if let workouts = loader.reading?.allWorkouts, !workouts.isEmpty {
                ForEach(workouts.prefix(20)) { workout in
                    WorkoutRow(workout: workout)
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
                    Text("\(summary.trainedDays) von \(summary.plannedTrainingDays) geschwommen")
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
    let entries: [PlanAdherenceEntry]

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let meters: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    /// Nur Tage mit Training oder Strecke, die letzten 14 Tage (älteste links).
    private var bars: [Bar] {
        entries
            .prefix(14)
            .reversed()
            .flatMap { entry -> [Bar] in
                guard let date = Self.parse(entry.date) else { return [] }
                return [
                    Bar(date: date, kind: "Geplant", meters: Double(entry.plannedMeters)),
                    Bar(date: date, kind: "Geschwommen", meters: entry.actualMeters)
                ]
            }
    }

    var body: some View {
        let data = bars
        if data.contains(where: { $0.meters > 0 }) {
            Section {
                Chart(data) { bar in
                    BarMark(
                        x: .value("Tag", bar.date, unit: .day),
                        y: .value("Meter", bar.meters)
                    )
                    .foregroundStyle(by: .value("Art", bar.kind))
                    .position(by: .value("Art", bar.kind))
                }
                .chartForegroundStyleScale(["Geplant": Color.gray.opacity(0.5), "Geschwommen": Color.blue])
                .frame(height: 180)
                .accessibilityLabel("Geplante und geschwommene Meter der letzten Tage")
            } header: {
                Text("Geplant und geschwommen")
            } footer: {
                Text("Die letzten 14 Tage mit gespeichertem Plan.")
            }
        }
    }

    private static func parse(_ isoDay: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: isoDay)
    }
}

// MARK: - Zeile

private struct HistoryRow: View {
    let entry: PlanAdherenceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(PlanFormatting.germanDate(entry.date))
                    .font(.subheadline)
                Spacer()
                Label(Self.title(entry.outcome), systemImage: Self.symbol(entry.outcome))
                    .font(.caption)
                    .foregroundStyle(Self.color(entry.outcome))
            }
            Text(planned)
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.workoutCount > 0 {
                Text(swum)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var planned: String {
        let type = PlanFormatting.sessionType(entry.plan.sessionType)
        return entry.plan.isRestDay ? "Geplant: \(type)" : "Geplant: \(type), \(PlanFormatting.meters(entry.plannedMeters))"
    }

    private var swum: String {
        let count = entry.workoutCount == 1 ? "1 Einheit" : "\(entry.workoutCount) Einheiten"
        return entry.actualMeters > 0
            ? "Geschwommen: \(PlanFormatting.meters(Int(entry.actualMeters))) in \(count)"
            : "Geschwommen: \(count), ohne Streckenangabe"
    }

    private static func title(_ outcome: AdherenceOutcome) -> String {
        switch outcome {
        case .followed: return "umgesetzt"
        case .shorter: return "kürzer"
        case .longer: return "länger"
        case .missed: return "nicht geschwommen"
        case .restKept: return "Ruhetag eingehalten"
        case .restBroken: return "trotz Ruhetag geschwommen"
        case .pending: return "offen"
        }
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
