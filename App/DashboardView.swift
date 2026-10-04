import SwiftUI
import SwimInstructorCore

/// Fortschritt auf einen Blick: Kacheln der Statistik (T6, frei wählbar), die Woche über alle Sportarten, dazu das Ziel.
struct DashboardView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var dashboard: StatisticDashboard

    @State private var showsAddTile = false
    @State private var confirmsReset = false

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
                        StatisticTilesGrid(dashboard: dashboard, input: statisticInput)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Statistik")
                    } footer: {
                        Text("Lange drücken: Sportart, Kennzahl und Zeitraum wählen. Auf eine andere Kachel ziehen: Reihenfolge ändern.")
                    }
                    Section("Diese Woche") {
                        WeekStatsRows(
                            summary: weekProgress.summary(of: weekStatuses),
                            hasPlan: weekLoader.week(starting: weekLoader.currentWeekStart) != nil
                        )
                        RecoveryRow(reading: reading)
                    }
                    GoalSection(snapshot: reading.snapshot)
                    Section {
                        NavigationLink {
                            ProfileView()
                        } label: {
                            Label("Leistungsprofil", systemImage: "gauge.with.dots.needle.67percent")
                        }
                    }
                } else if loader.isLoadingHealth {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Lese Health-Daten …").foregroundStyle(.secondary)
                    }
                } else if let error = loader.healthError {
                    Text("Health: \(error)").foregroundStyle(.red)
                } else {
                    Text("Noch keine Daten. Öffne zuerst den Tab \"Heute\".")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
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
            // Liest nur Health neu. Einen neuen Plan holt erst der Tab "Heute" (kostet einen Claude-Aufruf).
            .refreshable { await loader.refreshIfNeeded() }
        }
        .task { await loader.refreshIfNeeded() }
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
