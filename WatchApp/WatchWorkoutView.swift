import SwiftUI
import SwimInstructorCore

/// Laufende Einheit: Werte, Stand im Plan, Steuerung. Seitlich wischen wie in Apples Workout-App.
struct WatchWorkoutView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsView()
                .tag(0)
            WorkoutMetricsView(isCurrentPage: page == 1)
                .tag(1)
            WorkoutPlanView(isCurrentPage: page == 2)
                .tag(2)
        }
        .tabViewStyle(.page)
        .onChange(of: workoutManager.phase) { _, _ in
            // Nach Pause oder Fortsetzen zurück zu den Werten.
            withAnimation { page = 1 }
        }
    }
}

/// Crown-Steuerung für den Wechsel von Satz zu Satz. Sitzt an jeder Seite, die sie braucht, und nicht am
/// Seiten-Container: Die Crown geht an die Ansicht mit dem Fokus, und den bekommt nur die Seite, die
/// gerade sichtbar ist (`isActive`).
private struct CrownSectionControl: ViewModifier {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    let isActive: Bool
    @State private var crown = 0.0
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable(isActive)
            .focused($focused)
            .digitalCrownRotation($crown, from: -50.0, through: 50.0, by: 1.0, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, value in
                if workoutManager.crownMoved(value) { crown = 0 }
            }
            .onAppear { focused = isActive }
            .onChange(of: isActive) { _, active in focused = active }
    }
}

/// Der laufende Abschnitt des Plans: Name, Equipment, Stand und was zu tun ist. Gemeinsam für die
/// Startseite (kompakt) und die Plan-Seite.
private struct SectionBlock: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    let compact: Bool

    var body: some View {
        switch workoutManager.progress {
        case nil, .noSets?:
            Text("Kein Plan für heute")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .inProgress(position)?:
            inProgress(position)
        case let .completed(extraMeters)?:
            Label("Plan geschafft", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
            if extraMeters > 0 {
                Text("+ \(PlanFormatting.meters(extraMeters))")
                    .font(.caption2)
            }
        }
    }

    private func inProgress(_ position: PlanPosition) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(position.setIndex + 1)/\(workoutManager.planSets.count) \(position.set.name)")
                .font(compact ? .footnote.weight(.semibold) : .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !position.set.equipment.isEmpty {
                Label(PlanFormatting.equipment(position.set.equipment), systemImage: "backpack")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("\(PlanFormatting.repetition(position)) · \(PlanFormatting.remaining(position))")
                .font(compact ? .caption.monospacedDigit() : .footnote.monospacedDigit())
                .foregroundStyle(.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !compact {
                let details = PlanFormatting.setDetails(position.set)
                if !details.isEmpty {
                    Text(details)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !position.set.instructions.isEmpty {
                Text(position.set.instructions)
                    .font(.caption2)
                    .foregroundStyle(compact ? Color.secondary : Color.primary)
                    .lineLimit(compact ? 2 : 6)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// Kontrollzeile für Wassersperre, Crown und letzte Eingabe. Zeigt auch, wo es hakt, falls eine
/// Eingabe nicht ankommt.
private struct ControlStatusLine: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if workoutManager.crownProgress > 0 {
                ProgressView(value: workoutManager.crownProgress)
                    .tint(workoutManager.crownStep == .previous ? Color.orange : Color.yellow)
            }
            Label(
                workoutManager.lastGestureNote,
                systemImage: workoutManager.isWaterLocked ? "lock.fill" : "lock.open.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(workoutManager.isWaterLocked ? Color.secondary : Color.yellow)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

private struct WorkoutMetricsView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    let isCurrentPage: Bool

    private var metrics: LiveSwimMetrics { workoutManager.metrics }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                // Zeit und Puls sind das, was man im Becken liest: groß, der Plan darunter kleiner.
                Text(PlanFormatting.elapsed(workoutManager.elapsedTime(at: context.date)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(workoutManager.phase == .paused ? Color.orange : Color.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                    Text(metrics.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                SectionBlock(compact: true)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(PlanFormatting.meters(Int(metrics.distanceMeters)))
                    Text("\(metrics.laps) Bahnen")
                    if let pace = metrics.averagePaceSecondsPer100m {
                        Text(PlanFormatting.pace(pace))
                    }
                }
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                ControlStatusLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(CrownSectionControl(isActive: isCurrentPage))
    }
}

/// Wo im Tagesplan man steht, mit allen Angaben zum Abschnitt.
private struct WorkoutPlanView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    let isCurrentPage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionBlock(compact: false)
            Spacer(minLength: 0)
            Button("Nächster Satz") {
                workoutManager.advanceSection()
            }
            .font(.footnote)
            ControlStatusLine()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CrownSectionControl(isActive: isCurrentPage))
    }
}

private struct WorkoutControlsView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager

    var body: some View {
        VStack(spacing: 8) {
            if workoutManager.phase == .saving || workoutManager.phase == .starting {
                ProgressView()
                Text(workoutManager.phase == .saving ? "Speichert …" : "Startet …")
                    .font(.footnote)
            } else {
                HStack(spacing: 12) {
                    VStack {
                        Button {
                            workoutManager.end()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .tint(.red)
                        Text("Beenden").font(.footnote)
                    }
                    VStack {
                        Button {
                            if workoutManager.phase == .paused {
                                workoutManager.resume()
                            } else {
                                workoutManager.pause()
                            }
                        } label: {
                            Image(systemName: workoutManager.phase == .paused ? "play.fill" : "pause.fill")
                        }
                        .tint(.yellow)
                        Text(workoutManager.phase == .paused ? "Weiter" : "Pause").font(.footnote)
                    }
                }
                Button {
                    workoutManager.advanceSection()
                } label: {
                    Label("Nächster Satz", systemImage: "forward.end.fill")
                        .font(.footnote)
                }
                ControlStatusLine()
            }
            if let error = workoutManager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// Nach dem Beenden: die wichtigsten Werte und ob das Workout in Health gelandet ist.
struct WatchSummaryView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    let saved: Bool

    private var metrics: LiveSwimMetrics { workoutManager.metrics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Geschafft")
                    .font(.headline)
                LabeledContent("Zeit", value: PlanFormatting.elapsed(metrics.elapsed))
                LabeledContent("Strecke", value: PlanFormatting.meters(Int(metrics.distanceMeters)))
                LabeledContent("Bahnen", value: "\(metrics.laps)")
                if let pace = metrics.averagePaceSecondsPer100m {
                    LabeledContent("Pace", value: "\(PlanFormatting.pace(pace)) /100 m")
                }
                if let strokes = metrics.strokesPerLap {
                    LabeledContent("Züge/Bahn", value: "\(Int(strokes.rounded()))")
                }
                Text(saved ? "In Health gespeichert. Das iPhone berücksichtigt die Einheit beim nächsten Plan." : (workoutManager.errorMessage ?? "Nicht in Health gespeichert."))
                    .font(.footnote)
                    .foregroundStyle(saved ? Color.secondary : Color.red)
                    .padding(.top, 4)
                Button("Fertig") {
                    workoutManager.reset()
                }
                .padding(.top, 4)
            }
        }
    }
}
