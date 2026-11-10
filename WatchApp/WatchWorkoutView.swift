import SwiftUI
import SwimInstructorCore

/// Laufende Einheit: Werte, Stand im Plan, Steuerung. Seitlich wischen wie in Apples Workout-App.
struct WatchWorkoutView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
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

/// Crown-Steuerung für den Wechsel von Schritt zu Schritt. Sitzt an jeder Seite, die sie braucht, und nicht am
/// Seiten-Container: Die Crown geht an die Ansicht mit dem Fokus, und den bekommt nur die Seite, die gerade sichtbar ist
/// (`isActive`).
private struct CrownSectionControl: ViewModifier {
    @EnvironmentObject private var workoutManager: WorkoutManager
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

/// Der laufende Schritt des Plans: Name, Hilfsmittel, Stand und was zu tun ist; in der Pause, was danach kommt. Gemeinsam
/// für die Werte-Seite (kompakt) und die Plan-Seite.
private struct StepBlock: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    let status: ProgressStatus
    let compact: Bool

    var body: some View {
        switch status {
        case .noUnits:
            Text(ProgressFormatting.remaining(status))
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .completed:
            Label(ProgressFormatting.remaining(status), systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.spark)
        case let .rest(_, next, _):
            VStack(alignment: .leading, spacing: 1) {
                Label(ProgressFormatting.remaining(status), systemImage: "timer")
                    .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.spark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let next {
                    Text("Danach: \(next.step.name)")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(ProgressFormatting.cue(next))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 3)
                        .minimumScaleFactor(0.7)
                }
            }
        case let .work(unit, _, _):
            work(unit)
        }
    }

    private func work(_ unit: ProgressUnit) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ProgressFormatting.stepTitle(unit, stepCount: workoutManager.progress.stepCount))
                .font(compact ? .footnote.weight(.semibold) : .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !unit.step.equipment.isEmpty {
                Label(PlanFormatting.equipment(unit.step.equipment), systemImage: "backpack")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(ProgressFormatting.line(status))
                .font(.system(size: compact ? 18 : 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ember)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if compact {
                // Unterwegs zählen wenige Worte: der Kurztext, eine Zeile.
                Text(ProgressFormatting.cue(unit))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                let details = PlanV2Formatting.stepDetails(unit.step)
                if !details.isEmpty {
                    Text(details)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !unit.step.instructions.isEmpty {
                    // Plan-Seite: die ganze Anleitung.
                    Text(unit.step.instructions)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(10)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

/// Kontrollzeile für Wassersperre, Crown und letzte Eingabe. Zeigt auch, wo es hakt, falls eine Eingabe nicht ankommt.
private struct ControlStatusLine: View {
    @EnvironmentObject private var workoutManager: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if workoutManager.crownProgress > 0 {
                ProgressView(value: workoutManager.crownProgress)
                    .tint(workoutManager.crownStep == .previous ? Color.orange : Color.yellow)
            }
            Label(
                workoutManager.lastGestureNote,
                systemImage: workoutManager.usesWaterLock ? (workoutManager.isWaterLocked ? "lock.fill" : "lock.open.fill") : "digitalcrown.horizontal.arrow.clockwise"
            )
            .font(.system(size: 11))
            .foregroundStyle(workoutManager.usesWaterLock && !workoutManager.isWaterLocked ? Color.yellow : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

private struct WorkoutMetricsView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    let isCurrentPage: Bool

    private var metrics: LiveWorkoutMetrics { workoutManager.metrics }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = workoutManager.status(at: context.date)
            // Schriften nach der Höhe des Displays: Auf jeder Uhrgröße füllt die Seite den Bildschirm.
            GeometryReader { geometry in
                let height = geometry.size.height
                VStack(alignment: .leading, spacing: 0) {
                    timeAndPulse(at: context.date, height: height)
                    Spacer(minLength: 0)
                    // Was jetzt zu tun ist, am größten: die Meter (oder Zeit) bis zum Wechsel, in der Pause die Restzeit.
                    Text(ProgressFormatting.remaining(status))
                        .font(Self.font(height * 0.2, .bold))
                        .foregroundStyle(remainingColor(status))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    description(status, height: height)
                    Spacer(minLength: 0)
                    paceAndDistance(height: height)
                    ControlStatusLine()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .modifier(CrownSectionControl(isActive: isCurrentPage))
    }

    private static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Zeit groß links, Puls kleiner rechts.
    private func timeAndPulse(at date: Date, height: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(PlanFormatting.elapsed(workoutManager.elapsedTime(at: date)))
                .font(Self.font(height * 0.15, .semibold))
                .foregroundStyle(workoutManager.phase == .paused ? Color.orange : Color.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.system(size: height * 0.06))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(metrics.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(Self.font(height * 0.1, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Puls")
        }
    }

    /// Der Schritt in Worten: Nummer und Name, Wiederholung, Hilfsmittel und der Kurztext des Plans (zwei Zeilen). In der
    /// Pause, was danach kommt.
    @ViewBuilder
    private func description(_ status: ProgressStatus, height: CGFloat) -> some View {
        switch status {
        case let .work(unit, _, _):
            let title = [ProgressFormatting.stepTitle(unit, stepCount: workoutManager.progress.stepCount), ProgressFormatting.repetition(unit)]
                .compactMap { $0 }
                .joined(separator: " · ")
            Text(title)
                .font(Self.font(height * 0.085, .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !unit.step.equipment.isEmpty {
                Label(PlanFormatting.equipment(unit.step.equipment), systemImage: "backpack")
                    .font(.system(size: height * 0.075, weight: .medium, design: .rounded))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(ProgressFormatting.cue(unit))
                .font(.system(size: height * 0.095, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        case let .rest(_, next?, _):
            Text("Danach: \(next.step.name)")
                .font(Self.font(height * 0.085, .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(ProgressFormatting.cue(next))
                .font(.system(size: height * 0.095, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        default:
            EmptyView()
        }
    }

    /// Tempo und Strecke (beim Schwimmen auch Bahnen) unten in einer Zeile.
    private func paceAndDistance(height: CGFloat) -> some View {
        let profile = workoutManager.recordingProfile
        let secondary = profile.secondaryFields.compactMap { LiveFieldFormatting.text($0, metrics: metrics) }
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(LiveFieldFormatting.value(profile.primaryField, metrics: metrics) ?? "--")
                .font(Self.font(height * 0.09, .semibold))
                .foregroundStyle(.cyan)
            Text(LiveFieldFormatting.unit(profile.primaryField))
                .font(.system(size: height * 0.05))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            if !secondary.isEmpty {
                // Wie weit man schon ist: größer als das Tempo.
                Text(secondary.joined(separator: " · "))
                    .font(Self.font(height * 0.12, .semibold))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .combine)
    }

    private func remainingColor(_ status: ProgressStatus) -> Color {
        switch status {
        case .rest, .completed: return Theme.spark
        case .work: return Theme.ember
        case .noUnits: return .white
        }
    }
}

/// Wo im Plan man steht, mit allen Angaben zum Schritt.
private struct WorkoutPlanView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    let isCurrentPage: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                StepBlock(status: workoutManager.status(at: context.date), compact: false)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    capsuleButton("Zurück") { workoutManager.moveSection(.previous, source: String(localized: "Taste")) }
                    capsuleButton("Weiter") { workoutManager.advanceSection() }
                }
                ControlStatusLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(CrownSectionControl(isActive: isCurrentPage))
    }

    private func capsuleButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.ember.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutControlsView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 8) {
            if workoutManager.phase == .saving || workoutManager.phase == .starting {
                ForgeAnimation(size: 32)
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
                        .accessibilityLabel("Beenden")
                        // Steht schon am Knopf.
                        Text("Beenden").font(.footnote)
                            .accessibilityHidden(true)
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
                        .accessibilityLabel(Text(workoutManager.phase == .paused ? "Weiter" : "Pause"))
                        Text(workoutManager.phase == .paused ? "Weiter" : "Pause").font(.footnote)
                            .accessibilityHidden(true)
                    }
                }
                Button {
                    workoutManager.advanceSection()
                } label: {
                    Label("Nächster Schritt", systemImage: "forward.end.fill")
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

/// Nach dem Beenden: die wichtigsten Werte, das Testergebnis und ob das Workout in Health gelandet ist.
struct WatchSummaryView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    let saved: Bool

    private var metrics: LiveWorkoutMetrics { workoutManager.metrics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Geschafft")
                    .font(.headline)
                LabeledContent("Zeit", value: PlanFormatting.elapsed(metrics.elapsed))
                if metrics.distanceMeters > 0 {
                    LabeledContent("Strecke", value: PlanFormatting.distance(metrics.distanceMeters))
                }
                if let average = LiveFieldFormatting.average(workoutManager.recordingProfile.primaryField, metrics: metrics) {
                    LabeledContent("Schnitt", value: average)
                }
                if metrics.laps > 0 {
                    LabeledContent("Bahnen", value: "\(metrics.laps)")
                }
                if let gain = LiveFieldFormatting.text(.elevationGain, metrics: metrics) {
                    LabeledContent("Bergauf", value: gain)
                }
                if let result = workoutManager.testResult {
                    TestResultBlock(result: result, definitions: workoutManager.module?.performanceMetrics ?? [])
                        .padding(.top, 4)
                }
                if saved, workoutManager.canRateEffort {
                    EffortRatingBlock()
                        .padding(.top, 4)
                }
                Text(saved ? String(localized: "In Health gespeichert. Das iPhone berücksichtigt die Einheit beim nächsten Plan.") : (workoutManager.errorMessage ?? String(localized: "Nicht in Health gespeichert.")))
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

/// Nach dem Ende: Wie anstrengend war es? 1 bis 10 mit der Crown oder den Knöpfen, gespeichert als eigene Bewertung in
/// Health. Das iPhone nimmt sie für die Trainingslast und schlägt sie in "Wie war's?" vor.
private struct EffortRatingBlock: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @State private var effort = 5.0

    private var value: Int { Int(effort.rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let saved = workoutManager.savedEffort {
                Label("Anstrengung \(saved) von 10 gespeichert", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                Text("Wie anstrengend?")
                    .font(.headline)
                HStack {
                    Button {
                        effort = max(effort.rounded() - 1, 1)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .frame(width: 40)
                    .accessibilityLabel("Weniger")
                    VStack(spacing: 0) {
                        Text("\(value)")
                            .font(.title.weight(.heavy))
                            .monospacedDigit()
                        Text(SessionFeedback.effortLabel(value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .focusable()
                    .digitalCrownRotation($effort, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Anstrengung")
                    .accessibilityValue("\(value) von 10, \(SessionFeedback.effortLabel(value))")
                    // Mit VoiceOver nach oben oder unten wischen ändert den Wert wie die Crown.
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: effort = min(effort.rounded() + 1, 10)
                        case .decrement: effort = max(effort.rounded() - 1, 1)
                        @unknown default: break
                        }
                    }
                    Button {
                        effort = min(effort.rounded() + 1, 10)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .frame(width: 40)
                    .accessibilityLabel("Mehr")
                }
                Button(workoutManager.isSavingEffort ? "Speichert …" : "Sichern") {
                    Task { await workoutManager.saveEffort(value) }
                }
                .tint(Theme.ember)
                .disabled(workoutManager.isSavingEffort)
            }
        }
    }
}

/// Ergebnis eines Leistungstests: die neuen Werte oder warum der Test nicht zählt.
private struct TestResultBlock: View {
    let result: RecordedTestResult
    let definitions: [PerformanceMetricDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.isValid ? "Testergebnis" : "Test nicht gewertet")
                .font(.headline)
                .foregroundStyle(result.isValid ? Color.green : Color.orange)
            ForEach(definitions.filter { result.values[$0.metric] != nil }, id: \.metric) { definition in
                LabeledContent(definition.displayName, value: PlanV2Formatting.performanceValue(result.values[definition.metric] ?? 0, unit: definition.unit))
            }
            ForEach(result.problems, id: \.self) { problem in
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result.isValid {
                Text("Auf dem iPhone bestätigen: Erst dann gilt der neue Wert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Countdown vor dem Training: 30 Sekunden, um ins Wasser oder aufs Rad zu kommen. Die letzten drei Sekunden geben Impulse,
/// am Ende startet die Aufzeichnung von selbst.
struct WatchCountdownView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 6) {
            Text("Gleich geht's los")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(workoutManager.countdownRemaining ?? 0)")
                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.spark)
                .minimumScaleFactor(0.6)
            HStack(spacing: 12) {
                Button {
                    workoutManager.cancelCountdown()
                } label: {
                    Image(systemName: "xmark")
                }
                .tint(.red)
                .accessibilityLabel("Abbrechen")
                Button {
                    workoutManager.skipCountdown()
                } label: {
                    Image(systemName: "play.fill")
                }
                .tint(Theme.ember)
                .accessibilityLabel("Jetzt starten")
            }
        }
    }
}
