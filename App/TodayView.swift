import SwiftUI
import SwimInstructorCore

/// Heute-Bildschirm: Plan für heute, Zustand in Kürze, bisherige Einheiten.
struct TodayView: View {
    @EnvironmentObject private var loader: TodayPlanLoader
    @EnvironmentObject private var settings: BackendSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false
    @State private var wishDraft = ""

    var body: some View {
        NavigationStack {
            List {
                planSection
                wishSection
                if let reading = loader.reading {
                    Section("Dein Stand") {
                        StateSummaryView(reading: reading)
                    }
                }
                workoutsSection
            }
            .navigationTitle("Heute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .refreshable { await loader.refresh() }
            .sheet(isPresented: $showsSettings) {
                SettingsView {
                    Task { await loader.refresh() }
                }
            }
        }
        .task { await loader.refreshIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            // Über Nacht offen gelassen: beim Zurückkommen den Plan für den neuen Tag holen.
            if phase == .active {
                Task { await loader.refreshIfNeeded() }
            }
        }
    }

    // MARK: - Plan

    @ViewBuilder
    private var planSection: some View {
        Section {
            if loader.isLoadingPlan {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Claude schreibt deinen Plan …")
                        .foregroundStyle(.secondary)
                }
            }
            if let response = loader.response {
                PlanCardView(response: response)
            } else if !loader.isLoadingPlan {
                emptyPlanRow
            }
            if let error = loader.planError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        }
    }

    @ViewBuilder
    private var emptyPlanRow: some View {
        if loader.needsConfiguration || !settings.hasToken {
            VStack(alignment: .leading, spacing: 8) {
                Text("Noch kein Server-Token hinterlegt.")
                Button("Einstellungen öffnen") { showsSettings = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        } else if loader.healthError != nil {
            Text("Ohne Health-Daten kann kein Plan erstellt werden.")
                .foregroundStyle(.secondary)
        } else {
            Text("Noch kein Plan. Zum Aktualisieren nach unten ziehen.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Wunsch

    /// Freitext für heute. Er geht mit jeder Plananfrage des Tages mit und gilt morgen nicht mehr.
    private var wishSection: some View {
        Section {
            TextField("z. B. Heute lieber Technik, die Schulter zwickt", text: $wishDraft, axis: .vertical)
                .lineLimit(2...5)
                .onChange(of: wishDraft) { _, text in
                    if text.count > DailyWish.maxLength {
                        wishDraft = String(text.prefix(DailyWish.maxLength))
                    }
                }
            Button {
                Task { await loader.replan(withWish: wishDraft) }
            } label: {
                if loader.isLoadingPlan {
                    Text("Claude schreibt …")
                } else {
                    Text(wishDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "Plan ohne Wunsch neu erstellen"
                         : "Plan mit Wunsch neu erstellen")
                }
            }
            .disabled(loader.isLoadingPlan || loader.isLoadingHealth || !settings.hasToken)
        } header: {
            Text("Dein Wunsch für heute")
        } footer: {
            Text("Gilt nur für heute. Claude berücksichtigt ihn, soweit er in die Sicherheitsgrenzen passt (Umfang, Intensität, Ruhetag). Ziehen zum Aktualisieren nutzt ihn ebenfalls.")
        }
        .onAppear { wishDraft = loader.wish }
        .onChange(of: loader.wish) { old, new in
            // Neuer Tag oder gespeicherter Wunsch geändert: Feld nachziehen, aber nichts Ungespeichertes überschreiben.
            if wishDraft == old { wishDraft = new }
        }
    }

    // MARK: - Einheiten

    @ViewBuilder
    private var workoutsSection: some View {
        Section("Bisherige Einheiten") {
            if loader.isLoadingHealth && loader.reading == nil {
                ProgressView()
            } else if let error = loader.healthError {
                Text("Health: \(error)").foregroundStyle(.red)
            } else if let workouts = loader.reading?.workouts, !workouts.isEmpty {
                ForEach(workouts.prefix(20)) { workout in
                    SwimWorkoutRow(workout: workout)
                }
            } else {
                Text("Noch keine Schwimm-Workouts gefunden")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Kurzfassung des Snapshots: das, woraus der Plan entstanden ist.
private struct StateSummaryView: View {
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

private struct SwimWorkoutRow: View {
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
