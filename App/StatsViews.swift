import SwiftUI
import SwimInstructorCore

/// Die Woche in Zahlen: trainiert gegen geplant in Minuten, je Sportart in ihrer Einheit, Einheiten.
struct WeekStatsRows: View {
    let summary: MultiSportWeekSummary
    let hasPlan: Bool

    private let registry = SportRegistry.standard

    var body: some View {
        LabeledContent("Diese Woche") {
            Text(hasPlan
                 ? "\(PlanV2Formatting.duration(minutes: summary.actualMinutes)) von \(PlanV2Formatting.duration(minutes: summary.plannedMinutes))"
                 : PlanV2Formatting.duration(minutes: summary.actualMinutes))
        }
        ForEach(summary.sports) { total in
            LabeledContent {
                Text(PlanV2Formatting.comparison(planned: total.planned, actual: total.actual, unit: total.unit))
                    .monospacedDigit()
            } label: {
                Label(registry.displayName(for: total.sport), systemImage: registry.symbolName(for: total.sport))
            }
        }
        if hasPlan {
            LabeledContent("Einheiten der Woche") {
                Text("\(summary.sessionsDone) von \(summary.sessionsDue) fälligen, \(summary.sessionsPlanned) geplant")
            }
        }
    }
}

/// Kurzfassung des Snapshots: das, woraus der Plan entstanden ist.
struct StateSummaryView: View {
    let reading: AthleteStateReading

    private var snapshot: AthleteStateSnapshot { reading.snapshot }

    var body: some View {
        LabeledContent("Letzte 7 Tage") {
            Text("\(PlanFormatting.meters(Int(snapshot.volume.lastSevenDaysMeters))) in \(snapshot.volume.sessionsLastSevenDays) Einheiten")
        }
        if let pace = snapshot.pace.recentPaceSecondsPerHundredMeters {
            LabeledContent("Pace (4 Wochen)") {
                Text("\(PlanFormatting.pace(pace)) /100 m, Ziel \(PlanFormatting.pace(snapshot.goal.targetPaceSecondsPerHundredMeters))")
            }
        }
        LabeledContent("Erholung") {
            Text(recoveryText)
        }
        LabeledContent("Bis zum Ziel") {
            Text("\(snapshot.goal.daysUntilGoal) Tage")
        }
    }

    private var recoveryText: String {
        guard reading.vitalsAvailable else { return "keine Daten" }
        switch snapshot.recovery.status {
        case .good: return "gut"
        case .moderate: return "mäßig"
        case .poor: return "schlecht"
        case .unknown: return "zu wenig Daten"
        }
    }
}

/// Eine Einheit beliebiger Sportart im Verlauf: Symbol und Name kommen aus dem Sport-Modul.
struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        let sports = SportRegistry.standard
        HStack(spacing: 12) {
            Image(systemName: sports.symbolName(for: workout.sport))
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sports.displayName(for: workout.sport))
                    Spacer()
                    Text(workout.startDate, style: .date)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                HStack(spacing: 12) {
                    if let distance = workout.distanceMeters, distance > 0 {
                        Text(PlanFormatting.distance(distance))
                    }
                    Text(Duration.seconds(workout.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    if let heartRate = workout.averageHeartRate {
                        Text("\(Int(heartRate.rounded())) bpm")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

