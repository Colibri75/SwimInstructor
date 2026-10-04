import SwiftUI
import SwimInstructorCore

/// Heute-Bildschirm: was der Plan der nächsten sieben Tage für heute vorsieht, darunter je Einheit eine Karte mit allen
/// Schritten, dazu der Wunsch für heute.
struct TodayView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var settings: BackendSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false
    @State private var wishDraft = ""
    @State private var resultTest: TestResultTarget?

    private let onShowWeek: () -> Void
    private let progress = MultiSportWeekProgressCalculator()

    /// - Parameter onShowWeek: wechselt in den Tab "Plan" (für den Hinweis ohne Eintrag für heute).
    init(onShowWeek: @escaping () -> Void = {}) {
        self.onShowWeek = onShowWeek
    }

    /// Stand von heute gegen den Plan, aus Health und dem gespeicherten Plan der Woche.
    private var todayStatus: MultiSportDayStatus? {
        progress.statuses(
            plan: weekLoader.week(starting: weekLoader.currentWeekStart),
            weekStart: weekLoader.currentWeekStart,
            workouts: loader.reading?.allWorkouts ?? [],
            now: Date()
        ).first { $0.date == weekLoader.todayKey }
    }

    var body: some View {
        NavigationStack {
            List {
                weekTodaySection
                planSection
                wishSection
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
            .sheet(item: $resultTest) { target in
                TestResultSheet(sport: target.sport, testID: target.testID)
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

    // MARK: - Heute im Plan

    /// Was der Plan der sieben Tage für heute vorgibt. Die Einheiten mit allen Schritten stehen darunter.
    @ViewBuilder
    private var weekTodaySection: some View {
        Section {
            if let entry = weekLoader.todayEntry {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.isUnavailable ? "Keine Zeit" : (entry.isRestDay ? "Ruhetag" : "Heute im Plan"))
                            .font(.headline)
                        Spacer()
                        if let state = todayStatus?.state {
                            Text(PlanV2Formatting.stateText(state))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !entry.isUnavailable {
                        ForEach(Array(entry.sessions.enumerated()), id: \.offset) { _, session in
                            PlannedSessionLine(session: session)
                        }
                    }
                    if !entry.focus.isEmpty, !entry.isRestDay, !entry.isUnavailable {
                        Text(entry.focus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Für heute gibt es keinen Eintrag im Plan.")
                    Button("Zum Plan") { onShowWeek() }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Tagesplan

    @ViewBuilder
    private var planSection: some View {
        Section {
            if loader.isPreparing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Claude passt deinen Plan für die nächsten Tage an …")
                        .foregroundStyle(.secondary)
                }
            }
            if loader.isLoadingPlan {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Claude schreibt deinen Plan …")
                        .foregroundStyle(.secondary)
                }
            }
            if let response = loader.response {
                DayPlanHeaderView(response: response)
            } else if !loader.isLoadingPlan {
                emptyPlanRow
            }
            if let error = loader.planError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Dein Plan, \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
        }
        // Eine Karte je Einheit, damit Schwimmen und Laufen am selben Tag getrennt lesbar bleiben.
        if let response = loader.response {
            ForEach(Array(response.plan.sessions.enumerated()), id: \.offset) { index, session in
                Section {
                    SessionCardView(session: session, onEnterResult: resultAction(for: session))
                } header: {
                    if response.plan.sessions.count > 1 {
                        Text("Einheit \(index + 1) von \(response.plan.sessions.count)")
                    }
                }
            }
        }
    }

    /// Nur ein Test mit Vollbelastung hat ein Ergebnis, das ins Profil gehört.
    private func resultAction(for session: DaySession) -> (() -> Void)? {
        guard let test = session.test, test.maximalEffort else { return nil }
        return { resultTest = TestResultTarget(sport: session.sport, testID: test.id) }
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
            TextField("z. B. Heute lieber Rad statt Laufen, die Wade zwickt", text: $wishDraft, axis: .vertical)
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
            .disabled(loader.isLoading || !settings.hasToken)
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
}

/// Der Test, für den das Ergebnis-Blatt offen ist.
struct TestResultTarget: Identifiable {
    let sport: SportID
    let testID: String
    var id: String { "\(sport.rawValue)|\(testID)" }
}

/// Eine geplante Einheit in einer Zeile: Symbol, Sportart, Umfang, Art und Intensität.
struct PlannedSessionLine: View {
    let session: WeekSession

    private let registry = SportRegistry.standard

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: registry.symbolName(for: session.sport))
                .frame(width: 22)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(PlanV2Formatting.sessionTitle(sport: session.sport, amount: session.amount, unit: session.unit, registry: registry))
                .font(.subheadline.weight(.semibold))
            Text(session.test.map { "Test: \($0.displayName)" } ?? "\(PlanFormatting.sessionType(session.sessionType)), \(PlanFormatting.intensity(session.intensity))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
