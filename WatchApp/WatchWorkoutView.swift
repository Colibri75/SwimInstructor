import SwiftUI
import SwimInstructorCore

/// Laufende Einheit: Werte, Stand im Plan, Steuerung. Seitlich wischen wie in Apples Workout-App.
struct WatchWorkoutView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    @State private var page = 1
    @State private var crown = 0.0
    @FocusState private var crownHasFocus: Bool

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsView()
                .tag(0)
            WorkoutMetricsView()
                .tag(1)
            WorkoutPlanView()
                .tag(2)
        }
        .tabViewStyle(.page)
        .onChange(of: workoutManager.phase) { _, _ in
            // Nach Pause oder Fortsetzen zurück zu den Werten.
            withAnimation { page = 1 }
            // Die Crown liefert nur Drehungen, solange die Ansicht den Fokus hat.
            crownHasFocus = true
        }
        // Nach dem Entsperren schaltet eine weitere Crown-Drehung den nächsten Abschnitt weiter. Das
        // Entsperren selbst übernimmt das System.
        .focusable()
        .focused($crownHasFocus)
        .onAppear { crownHasFocus = true }
        .digitalCrownRotation($crown, from: -20, through: 20, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in
            if workoutManager.crownMoved(value) { crown = 0 }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            workoutManager.tickWaterLock()
            // Reste einer Drehung verfallen, sobald die Uhr wieder gesperrt ist.
            if workoutManager.isWaterLocked {
                if crown != 0 { crown = 0 }
            } else if workoutManager.evaluateCrown(crown) {
                crown = 0
            }
        }
    }
}

private struct WorkoutMetricsView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager

    private var metrics: LiveSwimMetrics { workoutManager.metrics }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanFormatting.elapsed(workoutManager.elapsedTime(at: context.date)))
                    .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(workoutManager.phase == .paused ? Color.orange : Color.yellow)
                Text(PlanFormatting.meters(Int(metrics.distanceMeters)))
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                Text("\(metrics.laps) Bahnen à \(workoutManager.poolLengthMeters) m")
                    .font(.footnote)
                if let pace = metrics.averagePaceSecondsPer100m {
                    Text("\(PlanFormatting.pace(pace)) /100 m")
                        .font(.footnote.monospacedDigit())
                }
                HStack(spacing: 8) {
                    if let strokes = metrics.strokesPerLap {
                        Text("\(Int(strokes.rounded())) Züge/Bahn")
                    }
                    if let heartRate = metrics.heartRate {
                        Label("\(Int(heartRate.rounded()))", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.footnote.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Wo im Tagesplan man steht, gemessen an der geschwommenen Strecke.
private struct WorkoutPlanView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    @EnvironmentObject private var planStore: WatchPlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch progress {
            case nil, .noSets?:
                Text("Kein Plan für heute")
                    .foregroundStyle(.secondary)
            case let .inProgress(position)?:
                Text(position.set.name)
                    .font(.headline)
                // Was genau zu tun ist (locker, Technikübung, ...). Lange Texte werden verkleinert und
                // nach sechs Zeilen gekürzt, damit Strecke und Schloss sichtbar bleiben.
                if !position.set.instructions.isEmpty {
                    Text(position.set.instructions)
                        .font(.footnote)
                        .lineLimit(6)
                        .minimumScaleFactor(0.8)
                }
                Text(PlanFormatting.repetition(position))
                    .font(.body.monospacedDigit())
                Text(PlanFormatting.remaining(position))
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundStyle(.blue)
                let details = PlanFormatting.setDetails(position.set)
                if !details.isEmpty {
                    Text(details)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

            case let .completed(extraMeters)?:
                Label("Plan geschafft", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if extraMeters > 0 {
                    Text("+ \(PlanFormatting.meters(extraMeters))")
                        .font(.footnote)
                }
            }
            controlHints
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Schloss, Fortschritt der Crown, letzte erkannte Taste und eine Taste für den entsperrten Zustand.
    /// Die Anzeigen zeigen auch, wo es hakt, falls eine Eingabe nicht ankommt.
    private var controlHints: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                workoutManager.isWaterLocked ? "Gesperrt" : "Entsperrt",
                systemImage: workoutManager.isWaterLocked ? "lock.fill" : "lock.open.fill"
            )
            .font(.caption2)
            .foregroundStyle(workoutManager.isWaterLocked ? Color.secondary : Color.yellow)
            if !workoutManager.isWaterLocked {
                ProgressView(value: workoutManager.crownProgress)
                    .tint(.yellow)
                Button("Nächster Abschnitt") {
                    workoutManager.advanceSection()
                }
                .font(.footnote)
            }
            Text("Tasten: \(workoutManager.lastGestureNote)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, 4)
    }

    private var progress: PlanProgressState? {
        guard let plan = planStore.response?.plan else { return nil }
        return PlanProgress.state(
            sets: plan.sets,
            swumMeters: workoutManager.metrics.distanceMeters,
            advancedAt: workoutManager.sectionAdvances
        )
    }
}

private struct WorkoutControlsView: View {
    @EnvironmentObject private var workoutManager: SwimWorkoutManager

    var body: some View {
        VStack(spacing: 12) {
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
