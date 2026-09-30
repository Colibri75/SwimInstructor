import SwiftUI
import SwimInstructorCore

/// Der Tagesplan: Art, Umfang, Begründung, Abschnitte, Hinweise.
struct PlanCardView: View {
    let response: PlanResponse

    private var plan: TrainingPlan { response.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = PlanFormatting.sourceNotice(response) {
                Label(notice, systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            header

            Text(plan.rationale)
                .font(.callout)

            if !plan.sets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(plan.sets.enumerated()), id: \.offset) { _, set in
                        PlanSetRow(set: set)
                    }
                }
                .padding(.top, 4)
            }

            if !plan.coachNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.coachNotes, id: \.self) { note in
                        Label(note, systemImage: "lightbulb")
                            .font(.footnote)
                    }
                }
            }

            if !response.adjustments.isEmpty {
                DisclosureGroup("Zur Sicherheit angepasst (\(response.adjustments.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(response.adjustments, id: \.self) { adjustment in
                            Text(adjustment)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanFormatting.sessionType(plan.sessionType))
                    .font(.title2.bold())
                if !plan.isRestDay {
                    Text("\(PlanFormatting.meters(plan.totalDistanceMeters)) · ca. \(plan.estimatedDurationMinutes) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !plan.isRestDay {
                IntensityBadge(intensity: plan.intensity)
            }
        }
    }
}

private struct PlanSetRow: View {
    let set: PlanSet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(set.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(PlanFormatting.setVolume(set))
                    .font(.subheadline.monospacedDigit())
            }
            let details = PlanFormatting.setDetails(set)
            if !details.isEmpty {
                Text(details)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !set.instructions.isEmpty {
                Text(set.instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct IntensityBadge: View {
    let intensity: PlanIntensity

    private var color: Color {
        switch intensity {
        case .rest, .easy: return .green
        case .moderate: return .orange
        case .hard: return .red
        case .unknown: return .gray
        }
    }

    var body: some View {
        Text(PlanFormatting.intensity(intensity))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

#Preview {
    List {
        PlanCardView(response: PlanResponse(
            source: .claude,
            date: "2026-09-30",
            generatedAt: .now,
            stale: false,
            plan: TrainingPlan(
                sessionType: .endurance,
                intensity: .moderate,
                rationale: "Deine Erholung ist gut und die letzte harte Einheit liegt zwei Tage zurück.",
                totalDistanceMeters: 1600,
                estimatedDurationMinutes: 45,
                sets: [
                    PlanSet(name: "Einschwimmen", repetitions: 1, distanceMeters: 300, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "locker, Kraul und Rücken"),
                    PlanSet(name: "Hauptsatz", repetitions: 6, distanceMeters: 200, targetPaceSecondsPerHundredMeters: 140, restSeconds: 30, instructions: "gleichmäßig"),
                    PlanSet(name: "Ausschwimmen", repetitions: 1, distanceMeters: 100, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "")
                ],
                coachNotes: ["Auf lockere Atmung achten."]
            ),
            adjustments: ["Umfang von 2000 m auf 1600 m gekürzt"]
        ))
    }
}
