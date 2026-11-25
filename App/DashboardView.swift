import SwiftUI
import SwimInstructorCore

/// Fortschritt auf einen Blick: Kacheln der Statistik (T6, frei wählbar), die Woche über alle Sportarten, dazu das Ziel.
struct DashboardView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var dashboard: StatisticDashboard
    @EnvironmentObject private var layouts: ScreenLayouts

    /// Die Kachel, deren Detail offen ist.
    @State private var openedTileID: UUID?

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
                    // Reihenfolge und Auswahl der Bereiche: "Bereiche anpassen" unten in der Liste.
                    ForEach(layouts.visible(.dashboard)) { section in
                        switch section.id {
                        case "statistics":
                            statisticsSection
                        case "week":
                            Section("Diese Woche") {
                                WeekStatsRows(
                                    summary: weekProgress.summary(of: weekStatuses),
                                    hasPlan: weekLoader.week(starting: weekLoader.currentWeekStart) != nil
                                )
                                RecoveryRow(reading: reading)
                            }
                            .cardRows()
                        case "goal":
                            GoalForecastSection(showsLink: true)
                                .cardRows()
                        default:
                            EmptyView()
                        }
                    }
                    CustomizeSectionsRow(screen: .dashboard, statisticInput: statisticInput)
                } else if loader.isLoadingHealth {
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Lese Health-Daten …").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if let error = loader.healthError {
                    Text("Health: \(error)").foregroundStyle(.red)
                } else {
                    Text("Noch keine Daten. Öffne zuerst den Tab \"Aktuell\".")
                        .foregroundStyle(.secondary)
                }
            }
            .themedList()
            .navigationTitle("Dashboard")
            .settingsToolbar()
            .navigationDestination(item: $openedTileID) { id in
                StatisticDetailView(dashboard: dashboard, tileID: id, input: statisticInput)
            }
            // Ziehen liest nur Health neu, der Plan bleibt.
            .refreshable { await loader.pullToRefresh() }
        }
        .task { await loader.refreshIfNeeded() }
    }

    /// Die Kacheln der Statistik. Hinzufügen, ändern und umsortieren unter "Bereiche anpassen".
    private var statisticsSection: some View {
        Section {
            if dashboard.tiles.isEmpty {
                Text("Keine Kacheln. Unter \"Bereiche anpassen\" fügst du welche hinzu.")
                    .foregroundStyle(.secondary)
                    .cardRows()
            }
            StatisticTileRows(dashboard: dashboard, input: statisticInput) { tile in
                openedTileID = tile.id
            }
        } header: {
            Text("Statistik")
        } footer: {
            Text("Tippen: Details mit allen Werten. Kacheln hinzufügen, ändern, entfernen und sortieren: \"Bereiche anpassen\" unten.")
        }
    }
}
