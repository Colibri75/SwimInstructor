import SwiftUI
import SwimInstructorCore

/// Hinweise zu einer Einheit: Koppeltraining und drinnen.
struct SessionHintsView: View {
    let hints: [String]

    var body: some View {
        if !hints.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(hints, id: \.self) { hint in
                    Label(hint, systemImage: hint.hasPrefix("Koppel") ? "link" : "house")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Ein Kraft- oder Mobilitätsblock des Tages mit seinen Übungen.
struct ExtraCardView: View {
    let extra: DayExtra

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: extra.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(extra.kind.displayName)
                        .font(.title3.bold())
                    Text("ca. \(PlanV2Formatting.duration(minutes: extra.minutes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !extra.focus.isEmpty {
                Text(extra.focus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(extra.exercises.enumerated()), id: \.offset) { _, exercise in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(exercise.summary)
                                .font(.subheadline.monospacedDigit())
                        }
                        if exercise.restSeconds > 0 {
                            Text("\(PlanFormatting.rest(exercise.restSeconds)) Pause")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !exercise.instructions.isEmpty {
                            Text(exercise.instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// Kraft und Mobilität eines Tages im Plan der sieben Tage, in einer Zeile.
struct WeekExtrasLine: View {
    let extras: [WeekExtra]

    var body: some View {
        if !extras.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(extras.enumerated()), id: \.offset) { _, extra in
                    Label(PlanV2Formatting.extraTitle(kind: extra.kind, minutes: extra.minutes), systemImage: extra.kind.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Rückmeldung zu einer Einheit: wie anstrengend und ob etwas weh tut. Der Plan reagiert darauf von selbst.
struct SessionFeedbackSheet: View {
    let workout: Workout
    let onSave: (SessionFeedback) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var effort: Double
    @State private var pain = PainLevel.none
    @State private var area = PainArea.knee

    private let registry = SportRegistry.standard

    init(workout: Workout, onSave: @escaping (SessionFeedback) -> Void) {
        self.workout = workout
        self.onSave = onSave
        // Vorbelegt mit der Anstrengung aus Health, sonst mittel.
        _effort = State(initialValue: min(max((workout[.effort] ?? 5).rounded(), 1), 10))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(registry.displayName(for: workout.sport), value: workout.startDate.formatted(date: .abbreviated, time: .shortened))
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("Anstrengung \(Int(effort)) von 10")
                            .font(.headline)
                        Slider(value: $effort, in: 1...10, step: 1)
                        Text(effortHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Wie anstrengend war es?")
                }
                Section {
                    Picker("Beschwerden", selection: $pain) {
                        ForEach(PainLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    if pain != .none {
                        Picker("Wo?", selection: $area) {
                            ForEach(PainArea.allCases) { area in
                                Text(area.displayName).tag(area)
                            }
                        }
                    }
                } header: {
                    Text("Tut etwas weh?")
                } footer: {
                    Text(painHint)
                }
            }
            .navigationTitle("Wie war's?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        onSave(SessionFeedback(
                            workoutID: workout.id,
                            date: PlanFormatting.isoDay(workout.startDate),
                            sport: workout.sport,
                            effort: Int(effort),
                            pain: pain,
                            painArea: pain == .none ? nil : area,
                            recordedAt: Date()
                        ))
                        dismiss()
                    }
                }
            }
        }
    }

    private var effortHint: String {
        switch Int(effort) {
        case ...3: return "Locker, du hättest dich gut unterhalten können."
        case 4...6: return "Mittel, fordernd, aber im Griff."
        case 7: return "Hart."
        default: return "Sehr hart: Danach plant die App erst etwas Lockeres."
        }
    }

    private var painHint: String {
        switch pain {
        case .none: return "Kein Problem: Der Plan bleibt, wie er ist."
        case .light: return "Leicht: einen Tag keine harte Einheit in dieser Sportart."
        case .moderate: return "Deutlich: zwei Tage nur locker und kürzer in dieser Sportart. Der Plan wird sofort angepasst."
        case .strong: return "Stark: drei Tage Pause in dieser Sportart, andere Sportarten gehen weiter. Hält es an, lass es ärztlich abklären."
        }
    }
}
