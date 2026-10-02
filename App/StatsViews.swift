import SwiftUI
import SwimInstructorCore

/// Die Woche in Zahlen: geschwommen gegen geplant, Einheiten.
struct WeekStatsRows: View {
    let summary: WeekSummary
    let hasPlan: Bool

    var body: some View {
        LabeledContent("Diese Woche") {
            Text(hasPlan
                 ? "\(PlanFormatting.meters(summary.swumMeters)) von \(PlanFormatting.meters(summary.plannedMeters))"
                 : PlanFormatting.meters(summary.swumMeters))
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

struct SwimWorkoutRow: View {
    let workout: SwimWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.startDate, style: .date)
                .font(.subheadline)
            HStack(spacing: 12) {
                if let distance = workout.totalDistanceMeters {
                    Text(PlanFormatting.meters(Int(distance)))
                }
                Text(Duration.seconds(workout.duration).formatted(.units(allowed: [.minutes, .seconds])))
                if let pace = workout.averagePaceSecondsPer100m {
                    Text("\(PlanFormatting.pace(pace)) /100 m")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
