import SwiftUI
import SwimInstructorCore

/// Der Tagesplan v2 im Überblick: Herkunft, Wunsch, Begründung, Hinweise und Korrekturen. Die Einheiten stehen als eigene
/// Karten darunter (`SessionCardView`).
struct DayPlanHeaderView: View {
    let response: DayPlanV2Response

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = PlanV2Formatting.sourceNotice(response) {
                Label(notice, systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if response.plan.isRestDay {
                Text("Ruhetag")
                    .font(.title2.bold())
            } else if response.plan.sessions.count > 1 {
                Text("\(response.plan.sessions.count) Einheiten · ca. \(PlanV2Formatting.duration(minutes: response.plan.totalMinutes))")
                    .font(.headline)
            }
            if let wish = response.wishes, !wish.isEmpty {
                Label("Dein Wunsch: \(wish)", systemImage: "text.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !response.plan.rationale.isEmpty {
                Text(response.plan.rationale)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !response.plan.equipmentNeeded.isEmpty {
                Label("Mitnehmen: \(PlanFormatting.equipment(response.plan.equipmentNeeded))", systemImage: "backpack")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !response.plan.coachNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(response.plan.coachNotes, id: \.self) { note in
                        Label(note, systemImage: "lightbulb")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            AdjustmentsDisclosure(adjustments: response.adjustments)
        }
        .padding(.vertical, 4)
    }
}

/// Eine Einheit des Tagesplans v2: Sportart, Art, Umfang, Schritte und Hilfsmittel. Bei einem Leistungstest steht
/// darunter der Knopf zum Eintragen des Ergebnisses.
struct SessionCardView: View {
    let session: DaySession
    /// Die Sportart der Einheit davor (für "Koppeltraining: direkt nach …"), `nil` bei der ersten.
    var previousSport: SportID?
    /// Öffnet die Eingabe des Testergebnisses; `nil` blendet den Knopf aus.
    var onEnterResult: (() -> Void)?

    private let registry = SportRegistry.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            SessionHintsView(hints: PlanV2Formatting.sessionHints(
                brick: session.brick, indoor: session.indoor, openWater: session.openWater, sport: session.sport, previous: previousSport, registry: registry
            ), startsWithBrick: session.brick && previousSport != nil)
            if !session.focus.isEmpty {
                Text(session.focus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let test = session.test {
                testBox(test)
            }
            if !session.steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                        PlanStepRow(step: step)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: registry.symbolName(for: session.sport))
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(registry.displayName(for: session.sport))
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            IntensityBadge(intensity: session.intensity)
        }
    }

    private var subtitle: String {
        var parts = [PlanFormatting.sessionType(session.sessionType), PlanV2Formatting.amount(session.amount, unit: session.unit)]
        // Bei Minuten steht die Dauer schon im Umfang.
        if session.unit == .meters, session.durationMinutes > 0 {
            parts.append(String(localized: "ca. \(PlanV2Formatting.duration(minutes: session.durationMinutes))"))
        }
        return parts.joined(separator: " · ")
    }

    private func testBox(_ test: PlannedTest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(test.maximalEffort ? "Leistungstest: \(test.displayName)" : "Einstiegstest: \(test.displayName)", systemImage: "stopwatch")
                .font(.subheadline.weight(.semibold))
            Text(test.maximalEffort
                 ? "Volle Belastung. Trag danach dein Ergebnis ein: Die App zeigt dir den Vergleich zum bisherigen Wert, übernommen wird erst nach deiner Bestätigung."
                 : "Locker, ohne Vollbelastung. Die App schätzt dein Tempo danach aus der Einheit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let onEnterResult {
                Button("Ergebnis eintragen", action: onEnterResult)
                    .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Ein Schritt einer Einheit: Name, Umfang, Ziel und Pause, Hilfsmittel, Anleitung.
struct PlanStepRow: View {
    let step: PlanStep

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(PlanV2Formatting.stepVolume(step))
                    .font(.subheadline.monospacedDigit())
            }
            let details = PlanV2Formatting.stepDetails(step)
            if !details.isEmpty {
                Text(details)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !step.equipment.isEmpty {
                Label(PlanFormatting.equipment(step.equipment), systemImage: "backpack")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !step.instructions.isEmpty {
                // Der Plan erklärt Übungen in ein bis zwei Sätzen: Der Text muss in voller Länge umbrechen.
                Text(step.instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Die Korrekturen der Sicherheitsschicht, eingeklappt.
struct AdjustmentsDisclosure: View {
    let adjustments: [String]
    var title = String(localized: "Zur Sicherheit angepasst")

    var body: some View {
        if !adjustments.isEmpty {
            DisclosureGroup("\(title) (\(adjustments.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(adjustments, id: \.self) { adjustment in
                        Text(adjustment)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

struct IntensityBadge: View {
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
        Section {
            SessionCardView(
                session: DaySession(
                    // Die erste Sportart der Registry; feste Kennungen stehen nur in den Modulen.
                    sport: SportRegistry.standard.ids[0],
                    sessionType: .test,
                    intensity: .hard,
                    focus: "CSS bestimmen",
                    test: PlannedTest(id: "css_400_200", displayName: "CSS-Test 400/200 m", maximalEffort: true, produces: ["css_pace"]),
                    amount: 1600,
                    unit: .meters,
                    distanceMeters: 1600,
                    durationMinutes: 45,
                    steps: [
                        PlanStep(name: "Einschwimmen", repetitions: 1, measure: .distance, distanceMeters: 400, instructions: "Locker, Kraul und Rücken im Wechsel."),
                        PlanStep(name: "400 m Test", repetitions: 1, measure: .distance, distanceMeters: 400, targetType: .perceivedEffort, targetValue: 9, restSeconds: 300)
                    ]
                ),
                onEnterResult: {}
            )
        }
    }
}
