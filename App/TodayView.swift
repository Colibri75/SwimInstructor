import SwiftUI
import SwimInstructorCore

/// Tab "Aktuell": was der Plan der nächsten 14 Tage für heute vorsieht, darunter je Einheit eine Karte mit allen
/// Schritten, dazu der Wunsch für heute. Ist das Training von heute erledigt, steht hier der Plan für morgen (die Vorschau,
/// die morgen der Tagesplan wird); heute bleibt per Umschalter erreichbar.
struct TodayView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var settings: BackendSettings
    @EnvironmentObject private var testResultInbox: WatchTestResultInbox
    @EnvironmentObject private var feedbackBook: SessionFeedbackBook
    @EnvironmentObject private var layouts: ScreenLayouts
    @EnvironmentObject private var coach: BackgroundCoach
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false
    @State private var wishDraft = ""
    @State private var resultTest: TestResultTarget?
    @State private var feedbackWorkout: Workout?
    /// Nach erledigtem Training trotzdem heute zeigen.
    @State private var showsToday = false

    private let onShowWeek: () -> Void
    private let progress = MultiSportWeekProgressCalculator()
    private let weekCalendar = WeekCalendar()

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

    /// Alles, was heute geplant war, ist gemacht.
    private var todayDone: Bool { todayStatus?.isTrainingDone == true }

    private var showsTomorrow: Bool { todayDone && !showsToday }

    private var tomorrowKey: String { weekCalendar.addingDays(1, to: weekLoader.todayKey) ?? weekLoader.todayKey }

    /// Der Tag, den der Tab gerade zeigt.
    private var shownDate: String { showsTomorrow ? tomorrowKey : weekLoader.todayKey }

    var body: some View {
        NavigationStack {
            List {
                // Reihenfolge und Auswahl der Bereiche: "Bereiche anpassen" unten in der Liste.
                ForEach(layouts.visible(.today)) { section in
                    todaySection(section.id)
                }
                CustomizeSectionsRow(screen: .today)
            }
            .themedList()
            .navigationTitle("Aktuell")
            .swipeClosesKeyboard()
            .settingsToolbar(isPresented: $showsSettings)
            .refreshable { await loader.pullToRefresh() }
            .sheet(item: $resultTest) { target in
                TestResultSheet(sport: target.sport, testID: target.testID, watchResult: target.watchResult)
            }
            .sheet(item: $feedbackWorkout) { workout in
                SessionFeedbackSheet(workout: workout) { feedback in
                    feedbackBook.record(feedback)
                    // Beschwerden oder eine sehr harte Einheit: Die nächsten 14 Tage und heute passen sich sofort an.
                    Task { await loader.refreshIfNeeded() }
                }
            }
        }
        .task {
            coach.requestPermission()
            await loader.refreshIfNeeded()
        }
        // Training erledigt: den Plan für morgen gleich holen (einmal je Vorgabe, er wird morgen der Tagesplan).
        .task(id: tomorrowPreviewKey) { await loadTomorrowIfNeeded() }
        .onChange(of: todayDone) { _, done in
            if done { showsToday = false }
            coach.updateGlance()
        }
        // Widget und Sperrbildschirm zeigen, was hier steht.
        .onChange(of: loader.response) { _, _ in coach.updateGlance() }
        .onChange(of: loader.previews) { _, _ in coach.updateGlance() }
        .onChange(of: scenePhase) { _, phase in
            // Über Nacht offen gelassen: beim Zurückkommen den Plan für den neuen Tag holen.
            if phase == .active {
                Task { await loader.refreshIfNeeded() }
            }
        }
    }

    /// Ein Bereich des Tabs. Nach erledigtem Training steht statt des Tagesplans der für morgen, ohne Wunsch-Feld.
    @ViewBuilder
    private func todaySection(_ id: String) -> some View {
        switch id {
        case "watchResult":
            watchResultSection
                .cardRows()
        case "adaptation":
            adaptationSection
                .cardRows()
        case "feedback":
            feedbackSection
                .cardRows()
        case "done":
            doneSection
                .cardRows()
        case "dayCard":
            // Die Tageskarte hat ihren eigenen Grund (Nacht).
            weekTodaySection
        case "plan":
            Group {
                if showsTomorrow {
                    tomorrowSections
                } else {
                    planSection
                    extrasSections
                }
            }
            .cardRows()
        case "wish":
            if !showsTomorrow {
                wishSection
                    .cardRows()
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Heute erledigt

    /// Nach erledigtem Training: Umschalter zwischen dem Plan für morgen und dem von heute.
    @ViewBuilder
    private var doneSection: some View {
        if todayDone {
            Section {
                HStack(spacing: 14) {
                    SparkPeak(size: 48, peakColor: .primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Heute erledigt")
                            .font(.title3.weight(.heavy))
                        if let summary = todaySummary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                Picker("Tag", selection: $showsToday) {
                    Text("Heute").tag(true)
                    Text("Morgen").tag(false)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(showsTomorrow ? "Dein Training für heute ist erledigt. Hier steht schon dein Plan für morgen." : "Dein Training für heute ist erledigt.")
            }
        }
    }

    // MARK: - Im Plan

    /// Was heute schon gemacht ist, kurz: "Schwimmen 850 m · Laufen 30 min".
    private var todaySummary: String? {
        let done = todayStatus?.comparisons.filter { $0.workoutCount > 0 } ?? []
        guard !done.isEmpty else { return nil }
        return done.map { "\(SportRegistry.standard.displayName(for: $0.sport)) \(PlanV2Formatting.amount($0.actual, unit: $0.unit))" }
            .joined(separator: " · ")
    }

    /// Die Tageskarte in Nacht, wie das Logo (auch im hellen Modus): Tag, Stand, Einheiten groß, Schwerpunkt, dahinter
    /// der Gipfel als Wasserzeichen. Die Einheiten mit allen Schritten stehen darunter.
    @ViewBuilder
    private var weekTodaySection: some View {
        Section {
            if let entry = weekLoader.day(on: shownDate) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("\(weekCalendar.weekdayName(shownDate)), \(PlanFormatting.shortGermanDate(shownDate))".uppercased())
                            .font(.footnote.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(Theme.nightSecondary)
                        Spacer()
                        statusBadge(entry)
                    }
                    if entry.isUnavailable || entry.isRestDay || entry.sessions.isEmpty {
                        Text(entry.isUnavailable ? "Keine Zeit" : "Ruhetag")
                            .font(.title.weight(.heavy))
                    } else {
                        ForEach(Array(entry.sessions.enumerated()), id: \.offset) { _, session in
                            HeroSessionLine(session: session)
                        }
                        WeekExtrasLine(extras: entry.extras)
                    }
                    if !entry.focus.isEmpty, !entry.isRestDay, !entry.isUnavailable {
                        Text(entry.focus)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .listRowBackground(
                    ZStack(alignment: .bottomTrailing) {
                        Theme.night
                        PeakShape()
                            .stroke(.white.opacity(0.1), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                            .frame(width: 150, height: 86)
                            .offset(x: 14, y: 16)
                    }
                    .clipped()
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(showsTomorrow ? "Für morgen gibt es keinen Eintrag im Plan." : "Für heute gibt es keinen Eintrag im Plan.")
                    Button("Zum Plan") { onShowWeek() }
                }
                .padding(.vertical, 2)
                .cardRows()
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
                if loader.hasFreshPlanForToday {
                    // Heute steht schon (Vorschau von gestern): nur ein kleiner Hinweis, der Plan bleibt lesbar.
                    Label("Dein Coach stimmt die nächsten Tage ab …", systemImage: "hammer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    forgeRow("Dein Coach passt deinen Plan für die nächsten Tage an …")
                }
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

    /// Stand des Tages als Abzeichen: offen in Glut, erledigt in Funke, morgen "Vorschau".
    @ViewBuilder
    private func statusBadge(_ entry: PlannedDay) -> some View {
        if showsTomorrow {
            badge("morgen", fill: Theme.nightSecondary.opacity(0.25), foreground: .white)
        } else if todayDone {
            badge("erledigt", fill: Theme.spark, foreground: Theme.onBright)
        } else if !entry.isRestDay, !entry.isUnavailable, let state = todayStatus?.state {
            badge(PlanV2Formatting.stateText(state), fill: Theme.ember, foreground: Theme.onBright)
        }
    }

    private func badge(_ label: String, fill: Color, foreground: Color) -> some View {
        Text(label)
            .font(.caption.weight(.heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }

    // MARK: - Morgen

    /// Ändert sich, wenn ein Plan für morgen fällig wird: Training erledigt, Vorgabe für morgen geändert, Health gelesen.
    private var tomorrowPreviewKey: String {
        guard showsTomorrow else { return "" }
        let date = tomorrowKey
        return "\(date)|\(loader.canPreview(date))|\(loader.dayPlan(on: date) != nil)|\(loader.reading != nil)"
    }

    /// Holt die Vorschau für morgen, wenn es Einheiten gibt und noch keine passende da ist. Nach einem Fehler nur auf Tipp.
    private func loadTomorrowIfNeeded() async {
        let date = tomorrowKey
        guard showsTomorrow, loader.dayPlan(on: date) == nil, loader.canPreview(date), loader.previewError?.date != date else { return }
        await loader.loadPreview(for: date)
    }

    /// Der Plan für morgen: die Vorschau mit allen Schritten. Morgen wird sie der Tagesplan, solange die Vorgabe gleich bleibt.
    @ViewBuilder
    private var tomorrowSections: some View {
        let date = tomorrowKey
        let preview = loader.dayPlan(on: date)
        Section {
            if loader.loadingPreviewDate == date {
                forgeRow("Dein Coach schreibt deinen Plan für morgen …")
            } else if let preview {
                DayPlanHeaderView(response: preview)
            } else if loader.canPreview(date) {
                Button {
                    Task { await loader.loadPreview(for: date) }
                } label: {
                    Label("Plan für morgen holen", systemImage: "list.bullet.rectangle")
                }
                .disabled(loader.loadingPreviewDate != nil || loader.reading == nil)
            } else if let entry = weekLoader.day(on: date), entry.isRestDay || entry.isUnavailable {
                Text("Morgen ist kein Training geplant. Erhol dich gut.")
                    .foregroundStyle(.secondary)
            }
            if let error = loader.previewError, error.date == date {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Dein Plan, \(weekCalendar.weekdayName(date)), \(PlanFormatting.shortGermanDate(date))")
        } footer: {
            Text("Vorschau. Morgen wird sie dein Tagesplan, solange du den Tag nicht im Plan-Tab änderst.")
        }
        if let preview {
            ForEach(Array(preview.plan.sessions.enumerated()), id: \.offset) { index, session in
                Section {
                    SessionCardView(session: session, previousSport: index > 0 ? preview.plan.sessions[index - 1].sport : nil)
                } header: {
                    if preview.plan.sessions.count > 1 {
                        Text("Einheit \(index + 1) von \(preview.plan.sessions.count)")
                    }
                }
            }
            ForEach(Array(preview.plan.extras.enumerated()), id: \.offset) { _, extra in
                Section {
                    ExtraCardView(extra: extra)
                } header: {
                    Text("Ergänzung")
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
                    .buttonStyle(.ember)
            }
            .padding(.vertical, 4)
        } else if loader.healthError != nil {
            Text("Ohne Health-Daten kann kein Plan erstellt werden.")
                .foregroundStyle(.secondary)
        } else {
            Text("Noch kein Plan. Unten kannst du ihn neu erstellen lassen.")
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
                    // Sofort speichern: Jede Plananfrage des Tages nutzt den gespeicherten Wunsch, auch wenn
                    // der Knopf nicht getippt wurde.
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
            .buttonStyle(.ember)
            .disabled(loader.isLoading || !settings.hasToken)
        } header: {
            Text("Dein Wunsch für heute")
        } footer: {
            Text("Gilt nur für heute. Dein Coach berücksichtigt ihn, soweit er in die Sicherheitsgrenzen passt (Umfang, Intensität, Ruhetag). Er wird beim Tippen gespeichert und gilt für jeden neuen Plan des Tages. Steht er nach dem Erstellen über dem Plan, ist er beim Server angekommen.")
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

/// Eine geplante Einheit groß auf der Tageskarte: Symbol in der Farbe der Sportart, Sportart und Umfang, darunter Art
/// und Intensität.
private struct HeroSessionLine: View {
    let session: WeekSession

    private let registry = SportRegistry.standard

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: registry.symbolName(for: session.sport))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.sport(session.sport))
                .frame(width: 52, height: 52)
                .background(Theme.sport(session.sport).opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanV2Formatting.sessionTitle(sport: session.sport, amount: session.amount, unit: session.unit, registry: registry))
                    .font(.title2.weight(.heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.nightSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [session.test.map { "Test: \($0.displayName)" } ?? "\(PlanFormatting.sessionType(session.sessionType)), \(PlanFormatting.intensity(session.intensity))"]
        if session.brick { parts.append("Koppeltraining") }
        if session.indoor { parts.append("drinnen") }
        if session.openWater { parts.append("Freiwasser") }
        return parts.joined(separator: " · ")
    }
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
