import SwiftUI
import SwimInstructorCore

/// Heute-Bildschirm: der Teil des Wochenplans, der heute ansteht, die Einheit für heute und ein paar
/// allgemeine Statistiken.
struct TodayView: View {
    @EnvironmentObject private var loader: TodayPlanLoader
    @EnvironmentObject private var weekLoader: WeekPlanLoader
    @EnvironmentObject private var settings: BackendSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false
    @State private var wishDraft = ""

    private let onShowWeek: () -> Void
    private let progress = WeekProgressCalculator()

    /// - Parameter onShowWeek: wechselt in den Tab "Woche" (für den Hinweis ohne Wochenplan).
    init(onShowWeek: @escaping () -> Void = {}) {
        self.onShowWeek = onShowWeek
    }

    /// Stand der laufenden Woche gegen den Plan, aus Health und dem gespeicherten Wochenplan.
    private var weekStatuses: [WeekDayStatus] {
        progress.statuses(
            plan: weekLoader.week(starting: weekLoader.currentWeekStart),
            weekStart: weekLoader.currentWeekStart,
            workouts: loader.reading?.workouts ?? [],
            now: Date()
        )
    }

    var body: some View {
        NavigationStack {
            List {
                weekTodaySection
                planSection
                wishSection
                if let reading = loader.reading {
                    Section("Statistik") {
                        WeekStatsRows(summary: progress.summary(of: weekStatuses), hasPlan: weekLoader.week(starting: weekLoader.currentWeekStart) != nil)
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

    // MARK: - Heute im Wochenplan

    /// Was der Wochenplan für heute vorgibt. Die Details der Einheit stehen darunter.
    @ViewBuilder
    private var weekTodaySection: some View {
        Section {
            if let entry = weekLoader.todayEntry {
                let state = weekStatuses.first { $0.date == weekLoader.todayKey }?.state
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.isRestDay
                             ? (entry.isUnavailable ? "Keine Zeit" : "Ruhetag")
                             : "\(PlanFormatting.sessionType(entry.sessionType)) · \(PlanFormatting.meters(entry.targetDistanceMeters))")
                            .font(.headline)
                        Spacer()
                        if let state {
                            Text(PlanFormatting.stateText(state))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !entry.focus.isEmpty, !entry.isRestDay {
                        Text(entry.focus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !entry.isRestDay {
                        Text("ca. \(entry.estimatedDurationMinutes) min · \(PlanFormatting.intensity(entry.intensity))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Für heute gibt es keinen Eintrag im Wochenplan.")
                    Button("Zum Wochenplan") { onShowWeek() }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Heute im Wochenplan")
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
            Text("Deine Einheit, \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
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
                    // Sofort speichern: Ziehen zum Aktualisieren nutzt den gespeicherten Wunsch und
                    // soll auch dann mit ihm planen, wenn der Knopf nicht getippt wurde.
                    loader.setWish(wishDraft)
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
            Text("Gilt nur für heute. Claude berücksichtigt ihn, soweit er in die Sicherheitsgrenzen passt (Umfang, Intensität, Ruhetag). Er wird beim Tippen gespeichert, Ziehen zum Aktualisieren nutzt ihn ebenfalls. Steht er nach dem Erstellen über dem Plan, ist er beim Server angekommen.")
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
        Section("Letzte Einheiten") {
            if loader.isLoadingHealth && loader.reading == nil {
                ProgressView()
            } else if let error = loader.healthError {
                Text("Health: \(error)").foregroundStyle(.red)
            } else if let workouts = loader.reading?.workouts, !workouts.isEmpty {
                ForEach(workouts.prefix(5)) { workout in
                    SwimWorkoutRow(workout: workout)
                }
            } else {
                Text("Noch keine Schwimm-Workouts gefunden")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Die Woche in Zahlen: geschwommen gegen geplant, Einheiten.
private struct WeekStatsRows: View {
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
