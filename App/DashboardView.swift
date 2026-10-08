import SwiftUI
import SwimInstructorCore

/// Fortschritt auf einen Blick: Kacheln der Statistik (T6, frei wählbar), die Woche über alle Sportarten, dazu das Ziel.
struct DashboardView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var dashboard: StatisticDashboard

    @State private var showsAddTile = false
    @State private var confirmsReset = false
    /// Die Kachel, deren Detail offen ist.
    @State private var openedTileID: UUID?
    /// Eigener Bearbeiten-Zustand statt `EditButton`: Der reagierte in der Toolbar oft erst beim zweiten Tipp und blieb
    /// beim Tabwechsel an.
    @State private var editMode: EditMode = .inactive

    private var isEditing: Bool { editMode.isEditing }

    private let weekProgress = MultiSportWeekProgressCalculator()

    /// Stand der laufenden Woche gegen den Plan, aus Health und dem gespeicherten Plan, über alle Sportarten.
    private var weekStatuses: [MultiSportDayStatus] {
        weekProgress.statuses(
            plan: weekLoader.week(starting: weekLoader.currentWeekStart),
            weekStart: weekLoader.currentWeekStart,
            workouts: loader.reading?.allWorkouts ?? [],
            now: Date()
        )
    }

    /// Einheiten und Tageswerte aus dem zuletzt gelesenen Zustand, Pläne aus dem Verlauf.
    private var statisticInput: StatisticInput {
        guard let reading = loader.reading else { return StatisticInput(workouts: [], now: Date()) }
        return StatisticInput(reading: reading, plans: loader.planHistory, now: Date())
    }

    var body: some View {
        NavigationStack {
            List {
                if let reading = loader.reading {
                    Section {
                        if dashboard.tiles.isEmpty {
                            Text("Keine Kacheln.")
                                .foregroundStyle(.secondary)
                                .cardRows()
                        }
                        StatisticTileRows(dashboard: dashboard, input: statisticInput, isEditing: isEditing) { tile in
                            openedTileID = tile.id
                        }
                        Button {
                            showsAddTile = true
                        } label: {
                            Label("Kachel hinzufügen", systemImage: "plus.circle.fill")
                        }
                        .cardRows()
                    } header: {
                        Text("Statistik")
                    } footer: {
                        Text("Tippen: Details mit allen Werten. Lange drücken: Sportart, Kennzahl und Zeitraum wählen. Nach links wischen: entfernen. \"Bearbeiten\": entfernen und Reihenfolge ändern.")
                    }
                    Section("Diese Woche") {
                        WeekStatsRows(
                            summary: weekProgress.summary(of: weekStatuses),
                            hasPlan: weekLoader.week(starting: weekLoader.currentWeekStart) != nil
                        )
                        RecoveryRow(reading: reading)
                    }
                    .cardRows()
                    GoalSection(snapshot: reading.snapshot)
                        .cardRows()
                } else if loader.isLoadingHealth {
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Lese Health-Daten …").foregroundStyle(.secondary)
                    }
                } else if let error = loader.healthError {
                    Text("Health: \(error)").foregroundStyle(.red)
                } else {
                    Text("Noch keine Daten. Öffne zuerst den Tab \"Aktuell\".")
                        .foregroundStyle(.secondary)
                }
            }
            .themedList()
            .environment(\.editMode, $editMode)
            .navigationTitle("Dashboard")
            .settingsToolbar()
            .navigationDestination(item: $openedTileID) { id in
                StatisticDetailView(dashboard: dashboard, tileID: id, input: statisticInput)
            }
            .toolbar {
                if loader.reading != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "Fertig" : "Bearbeiten") {
                            withAnimation { editMode = isEditing ? .inactive : .active }
                        }
                        .fontWeight(isEditing ? .semibold : .regular)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showsAddTile = true
                        } label: {
                            Label("Kachel hinzufügen", systemImage: "plus")
                        }
                        Button(role: .destructive) {
                            confirmsReset = true
                        } label: {
                            Label("Standard-Kacheln wiederherstellen", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Label("Kacheln", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showsAddTile) {
                AddStatisticTileSheet(dashboard: dashboard, input: statisticInput)
            }
            .confirmationDialog("Deine Auswahl geht verloren.", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Standard-Kacheln wiederherstellen", role: .destructive) {
                    withAnimation { dashboard.reset() }
                }
            }
            // Ziehen liest nur Health neu, der Plan bleibt.
            .refreshable { await loader.pullToRefresh() }
        }
        .task { await loader.refreshIfNeeded() }
        // Beim Wechsel in einen anderen Tab endet das Bearbeiten.
        .onDisappear { editMode = .inactive }
    }
}

// MARK: - Ziel

private struct GoalSection: View {
    let snapshot: AthleteStateSnapshot

    private var goal: AthleteStateSnapshot.GoalSummary { snapshot.goal }

    var body: some View {
        Section("Dein Ziel") {
            LabeledContent("Ziel") {
                Text("\(PlanFormatting.meters(Int(goal.distanceMeters))) in \(Int(goal.targetDurationSeconds / 60)) min")
            }
            LabeledContent("Bis zum Ziel") {
                Text("\(goal.daysUntilGoal) Tage")
            }
            VStack(alignment: .leading, spacing: 6) {
                let longest = snapshot.volume.longestSessionMeters
                ProgressView(value: min(longest, goal.distanceMeters), total: goal.distanceMeters)
                Text("Längste Einheit (4 Wochen): \(PlanFormatting.meters(Int(longest))) von \(PlanFormatting.meters(Int(goal.distanceMeters)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            paceRow
        }
    }

    @ViewBuilder
    private var paceRow: some View {
        if let pace = snapshot.pace.recentPaceSecondsPerHundredMeters {
            LabeledContent("Pace (4 Wochen)") {
                Text("\(PlanFormatting.pace(pace)) /100 m")
            }
            if let gap = snapshot.pace.gapToTargetSecondsPerHundredMeters {
                Text(gap > 0
                     ? "Zielpace \(PlanFormatting.pace(goal.targetPaceSecondsPerHundredMeters)): noch \(Int(gap.rounded())) s pro 100 m zu langsam."
                     : "Zielpace \(PlanFormatting.pace(goal.targetPaceSecondsPerHundredMeters)) erreicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let trend = snapshot.pace.trendSecondsPerHundredMeters, trend != 0 {
                Text(trend < 0
                     ? "Gegenüber den 4 Wochen davor \(Int(abs(trend).rounded())) s pro 100 m schneller."
                     : "Gegenüber den 4 Wochen davor \(Int(trend.rounded())) s pro 100 m langsamer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Für die Pace fehlen Einheiten mit Strecke in den letzten 4 Wochen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
