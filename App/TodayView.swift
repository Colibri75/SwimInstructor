import SwiftUI
import SwimInstructorCore

/// Heute-Bildschirm: was der Plan der nächsten sieben Tage für heute vorsieht, darunter je Einheit eine Karte mit allen
/// Schritten, dazu der Wunsch für heute.
struct TodayView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var settings: BackendSettings
    @EnvironmentObject private var testResultInbox: WatchTestResultInbox
    @EnvironmentObject private var feedbackBook: SessionFeedbackBook
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false
    @State private var wishDraft = ""
    @State private var resultTest: TestResultTarget?
    @State private var feedbackWorkout: Workout?

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
                watchResultSection
                adaptationSection
                feedbackSection
                weekTodaySection
                planSection
                extrasSections
                wishSection
            }
            .navigationTitle("Heute")
            .swipeClosesKeyboard()
            .settingsToolbar(isPresented: $showsSettings)
            .refreshable { await loader.refresh() }
            .sheet(item: $resultTest) { target in
                TestResultSheet(sport: target.sport, testID: target.testID, watchResult: target.watchResult)
            }
            .sheet(item: $feedbackWorkout) { workout in
                SessionFeedbackSheet(workout: workout) { feedback in
                    feedbackBook.record(feedback)
                    // Beschwerden oder eine sehr harte Einheit: Die sieben Tage und heute passen sich sofort an.
                    Task { await loader.refreshIfNeeded() }
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
                        WeekExtrasLine(extras: entry.extras)
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

    /// Groß und mittig: Das Planen dauert bis zu einer Minute, die Schmiede zeigt, dass gearbeitet wird.
    private func forgeRow(_ text: String) -> some View {
        VStack(spacing: 10) {
            ForgeAnimation(size: 72)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Der gespeicherte Tagesplan, solange er zum Wochenplan passt oder kein neuer unterwegs ist. Während der Coach den
    /// Plan nach einer Änderung im Plan-Tab anpasst, verschwindet der alte, damit nichts Widersprüchliches zu sehen ist.
    private var shownResponse: DayPlanV2Response? {
        guard let response = loader.response else { return nil }
        return loader.matchesTodayTarget || !loader.isLoadingPlan ? response : nil
    }

    @ViewBuilder
    private var planSection: some View {
        Section {
            if loader.isPreparing {
                forgeRow("Dein Coach passt deinen Plan für die nächsten Tage an …")
            }
            if loader.isLoadingPlan {
                forgeRow(loader.response != nil && !loader.matchesTodayTarget ? "Dein Coach passt den Plan an deine Änderung an …" : "Dein Coach schreibt deinen Plan …")
            }
            if let response = shownResponse {
                DayPlanHeaderView(response: response)
                if !loader.matchesTodayTarget && response.date == loader.todayKey {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            response.source == .fallback
                                ? "Ersatzplan: Dein Coach war nicht erreichbar, der Plan passt vielleicht nicht zum Wochenplan."
                                : "Der Plan für heute wurde im Plan-Tab geändert.",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Button("Jetzt anpassen") {
                            Task { await loader.syncWithTodayTarget() }
                        }
                        .disabled(loader.isLoading)
                    }
                }
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
        if let response = shownResponse {
            ForEach(Array(response.plan.sessions.enumerated()), id: \.offset) { index, session in
                Section {
                    SessionCardView(
                        session: session,
                        previousSport: index > 0 ? response.plan.sessions[index - 1].sport : nil,
                        onEnterResult: resultAction(for: session)
                    )
                } header: {
                    if response.plan.sessions.count > 1 {
                        Text("Einheit \(index + 1) von \(response.plan.sessions.count)")
                    }
                }
            }
        }
    }

    /// Kraft- und Mobilitätsblöcke des Tages, je ein eigener Abschnitt nach den Einheiten.
    @ViewBuilder
    private var extrasSections: some View {
        if let response = shownResponse {
            ForEach(Array(response.plan.extras.enumerated()), id: \.offset) { _, extra in
                Section {
                    ExtraCardView(extra: extra)
                } header: {
                    Text("Ergänzung")
                }
            }
        }
    }

    /// Nach einer Anpassung außer der Reihe: warum der Plan anders aussieht.
    @ViewBuilder
    private var adaptationSection: some View {
        if let signal = weekLoader.lastAdaptation, let notice = PlanV2Formatting.adaptationNotice(signal.reason) {
            Section {
                Label(notice, systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Einheiten von gestern und heute ohne Rückmeldung: Ein Tipp öffnet "Wie war's?".
    @ViewBuilder
    private var feedbackSection: some View {
        let pending = feedbackBook.pending(workouts: loader.reading?.allWorkouts ?? [], now: Date())
        if !pending.isEmpty {
            Section {
                ForEach(pending) { workout in
                    Button {
                        feedbackWorkout = workout
                    } label: {
                        HStack {
                            Image(systemName: SportRegistry.standard.symbolName(for: workout.sport))
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SportRegistry.standard.displayName(for: workout.sport))
                                Text(workout.startDate.formatted(.dateTime.weekday(.wide).hour().minute()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Wie war's?")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            } header: {
                Text("Rückmeldung")
            } footer: {
                Text("Anstrengung und Beschwerden: Der Plan der nächsten Tage richtet sich von selbst danach.")
            }
        }
    }

    /// Ein Testergebnis von der Watch, das auf Bestätigung wartet.
    @ViewBuilder
    private var watchResultSection: some View {
        if let result = testResultInbox.next {
            let registry = SportRegistry.standard
            let test = registry.module(for: result.sport)?.performanceTests.first { $0.id == result.testID }
            Section {
                Button {
                    resultTest = TestResultTarget(sport: result.sport, testID: result.testID, watchResult: result)
                } label: {
                    Label("\(test?.displayName ?? "Test") vom \(result.measuredAt.formatted(date: .abbreviated, time: .omitted)) ansehen", systemImage: "applewatch")
                }
            } header: {
                Text("Testergebnis von der Watch")
            } footer: {
                Text("Erst nach deiner Bestätigung richten sich Zonen und Tempo im Plan nach dem neuen Wert.")
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
                .returnClosesKeyboard(text: $wishDraft)
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
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Dein Coach schreibt …")
                    }
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
            Text("Gilt nur für heute. Dein Coach berücksichtigt ihn, soweit er in die Sicherheitsgrenzen passt (Umfang, Intensität, Ruhetag). Er wird beim Tippen gespeichert, Ziehen zum Aktualisieren nutzt ihn ebenfalls. Steht er nach dem Erstellen über dem Plan, ist er beim Server angekommen.")
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
    /// Das Ergebnis von der Watch, `nil` beim Eintragen von Hand.
    var watchResult: WatchTestResult?

    var id: String { "\(sport.rawValue)|\(testID)|\(watchResult?.id.uuidString ?? "-")" }
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
            if session.brick {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Koppeltraining")
            }
            if session.indoor {
                Image(systemName: "house")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Drinnen")
            }
            if session.openWater {
                Image(systemName: "water.waves")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Freiwasser")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
