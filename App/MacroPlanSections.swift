import Charts
import SwiftUI
import SwimInstructorCore

/// Der Gesamtplan bis zum Ziel im Plan-Tab: Überblick je Sportart, alle Wochen (antippen öffnet die Woche im
/// Wochenplan), das Leistungsprofil, Testtermine, die Fortschreibung mit Plan gegen Ist und darunter das Feedback mit der Liste der Änderungen
/// und dem Verlauf der Runden.
struct MacroPlanSections: View {
    /// Die angezeigten Bereiche in ihrer Reihenfolge (`LayoutScreen.macro`).
    let sections: [String]
    /// Öffnet die Woche (Montag) im Wochenplan.
    let onSelectWeek: (String) -> Void

    @EnvironmentObject private var macroLoader: MultiSportMacroLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @EnvironmentObject private var settings: BackendSettings

    @State private var feedback = ""
    /// Der letzte Fehler kam aus dem Feedback (nicht aus dem Neuberechnen): Er steht dann beim Feedback-Feld.
    @State private var errorFromFeedback = false
    @State private var confirmsRegenerate = false

    init(sections: [String] = LayoutScreen.macro.sections.map(\.id), onSelectWeek: @escaping (String) -> Void) {
        self.sections = sections
        self.onSelectWeek = onSelectWeek
    }

    var body: some View {
        ForEach(sections, id: \.self) { section in
            switch section {
            case "racePlan":
                RacePlanLinkSection()
            case "overview":
                overviewSection
            case "weeks":
                if let plan = macroLoader.plan {
                    weeksSection(plan)
                }
            case "profile":
                profileSection
            case "review":
                if let plan = macroLoader.plan {
                    reviewSection(plan)
                }
            case "feedback":
                if let plan = macroLoader.plan {
                    feedbackSection(plan)
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Leistungsprofil

    /// Die Werte, nach denen Zonen, Tempo und Tests im Gesamtplan entstehen.
    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileView()
            } label: {
                Label("Leistungswerte und Tests", systemImage: "gauge.with.dots.needle.67percent")
            }
        } header: {
            Text("Leistungsprofil")
        } footer: {
            Text("Danach richten sich Zonen und Tempo im Plan. Hier trägst du Werte von Hand oder nach einem Test ein und stellst ein, ob und wie oft die App Tests einplant.")
        }
    }

    // MARK: - Wochen

    /// Alle Wochen bis zum Ziel, je eine Zeile; antippen zeigt die Woche mit ihren Tagen im Wochenplan.
    private func weeksSection(_ plan: MacroPlanV2) -> some View {
        Section {
            ForEach(plan.weeks) { week in
                Button {
                    onSelectWeek(week.weekStart)
                } label: {
                    MacroWeekRow(week: week, isCurrent: week.weekStart == macroLoader.currentWeekStart)
                }
                .buttonStyle(.plain)
                .listRowBackground(week.weekStart == macroLoader.currentWeekStart ? Theme.highlightedCard : Theme.card)
            }
        } header: {
            Text("Wochen bis zum Ziel (\(plan.weeks.count))")
        } footer: {
            Text("Tippe auf eine Woche, um sie im Wochenplan zu sehen. Einzelne Einheiten gibt es für die nächsten 14 Tage, spätere Wochen zeigen die Vorgabe von hier.")
        }
    }

    /// Die letzte Fortschreibung: Anlass, Bilanz und Änderungen.
private struct ReviewView: View {
    let review: MacroReview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.reason.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(review.reviewedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !review.summary.isEmpty {
                Text(review.summary)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(review.changes, id: \.self) { change in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(change)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
            }
            AdjustmentsDisclosure(adjustments: review.adjustments)
        }
        .padding(.vertical, 2)
    }
}

/// Eine vergangene Woche: je Sportart trainiert gegen geplant, mit Prozent.
private struct ActualWeekRow: View {
    let planned: MacroWeekV2
    let actual: MacroActualWeek

    private let registry = SportRegistry.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Woche ab \(PlanFormatting.shortGermanDate(planned.weekStart))")
                .font(.caption.weight(.semibold))
            ForEach(planned.sports, id: \.sport) { volume in
                line(volume)
            }
        }
    }

    private func line(_ volume: MacroSportVolume) -> some View {
        let done = actual.amount(of: volume.sport)
        let percent = MacroActualCalculator.percent(planned: volume.amount, actual: done)
        let suffix = percent.map { " (\($0) %)" } ?? ""
        let isWeak = (percent ?? 100) < MacroActualCalculator.lowCompliancePercent
        return Text("\(registry.displayName(for: volume.sport)): \(PlanV2Formatting.amount(done, unit: volume.unit)) von \(PlanV2Formatting.amount(volume.amount, unit: volume.unit))\(suffix)")
            .font(.caption2)
            .foregroundStyle(isWeak ? Theme.caution : Color.secondary)
    }
}

// MARK: - Überblick

    private var overviewSection: some View {
        Section {
            if let plan = macroLoader.plan {
                MacroOverview(
                    plan: plan,
                    currentWeek: macroLoader.currentWeek,
                    weeksLeft: macroLoader.weeksUntilGoal,
                    currentWeekStart: macroLoader.currentWeekStart
                )
                if !macroLoader.isCurrent {
                    Label("Das Ziel hat sich geändert oder der Plan ist abgelaufen. Berechne ihn neu.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.caution)
                }
            } else {
                Text("Noch kein Gesamtplan. Er legt die Wochen bis zu deinem Ziel für alle Sportarten fest, die nächsten 14 Tage richten sich danach.")
                    .foregroundStyle(.secondary)
            }
            // Ohne gültigen Plan direkt; einen gültigen Plan neu zu erstellen, fragt erst nach (Feedback beginnt von vorn).
            Button {
                if macroLoader.plan != nil && macroLoader.isCurrent {
                    confirmsRegenerate = true
                } else {
                    regenerate()
                }
            } label: {
                if macroLoader.isLoading {
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Dein Coach plant bis zum Ziel …")
                    }
                } else if macroLoader.plan != nil && macroLoader.isCurrent {
                    Label("Gesamtplan neu erstellen", systemImage: "arrow.clockwise")
                } else {
                    Text("Gesamtplan erstellen")
                }
            }
            .disabled(isBusy || todayLoader.reading == nil || !settings.hasToken)
            .confirmationDialog("Gesamtplan neu erstellen?", isPresented: $confirmsRegenerate, titleVisibility: .visible) {
                Button("Neu erstellen") { regenerate() }
            } message: {
                Text("Dein Coach plant alle Wochen bis zum Ziel neu, mit deinem aktuellen Stand. Die laufende Woche bleibt, die Feedback-Runden beginnen von vorn. Danach werden die nächsten 14 Tage angepasst; deine festgelegten Tage und heute bleiben.")
            }
            if let error = macroLoader.error, !errorFromFeedback {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
            }
        } header: {
            Text("Gesamtplan bis zum Ziel")
        } footer: {
            Text("Der Gesamtplan entsteht beim Start und bei einem neuen Ziel. Danach schreibt die App ihn alle zwei Wochen mit deinem Ist fort; vergangene Wochen bleiben stehen. Mit \"Gesamtplan neu erstellen\" plant dein Coach ihn jederzeit von vorn.")
        }
    }

    /// Neu berechnen und danach die nächsten 14 Tage an den neuen Gesamtplan anpassen.
    private func regenerate() {
        guard let snapshot = todayLoader.reading?.snapshot else { return }
        errorFromFeedback = false
        Task {
            if await macroLoader.regenerate(snapshot: snapshot) {
                await todayLoader.refreshIfNeeded()
            }
        }
    }

    private var isBusy: Bool {
        macroLoader.isLoading || macroLoader.isRevising || macroLoader.isReviewing
    }

    // MARK: - Fortschreibung

    private func reviewSection(_ plan: MacroPlanV2) -> some View {
        let calculator = MacroActualCalculator()
        let actual = calculator.actualWeeks(macroLoader.reviewedPastWeekStarts, workouts: todayLoader.reading?.allWorkouts ?? [])
        let weak = calculator.lowComplianceSports(plan: plan, actual: actual, currentWeekStart: macroLoader.currentWeekStart)
        let reviewedThisWeek = plan.reviews.last?.weekStart == macroLoader.currentWeekStart
        return Section {
            if macroLoader.isReviewing {
                HStack(spacing: 12) {
                    ForgeAnimation()
                    Text("Dein Coach schreibt den Gesamtplan fort …")
                }
            }
            if let review = plan.reviews.last {
                ReviewView(review: review)
            }
            if let next = macroLoader.nextReviewWeekStart {
                LabeledContent("Nächste Fortschreibung", value: "Montag, \(PlanFormatting.germanDate(next))")
                    .font(.footnote)
            }
            if !weak.isEmpty, !reviewedThisWeek, macroLoader.isCurrent {
                lowComplianceBanner(weak)
            }
            if !actual.isEmpty {
                DisclosureGroup("Plan gegen Ist (\(actual.count) Wochen)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(actual, id: \.weekStart) { week in
                            if let planned = plan.week(starting: week.weekStart) {
                                ActualWeekRow(planned: planned, actual: week)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        } header: {
            Text("Fortschreibung")
        } footer: {
            Text("Alle zwei Wochen vergleicht dein Coach Plan und Ist und passt die Wochen ab der nächsten an. Die laufende Woche bleibt. Nach einer gemeldeten Pause (Einstellungen) passiert das sofort.")
        }
    }

    /// Zwei schwache Wochen: Die App schlägt die Fortschreibung vor, der Athlet bestätigt.
    private func lowComplianceBanner(_ weak: [SportID]) -> some View {
        let names = weak.map { SportRegistry.standard.displayName(for: $0) }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 8) {
            Label(
                "Zwei Wochen unter \(MacroActualCalculator.lowCompliancePercent) % des Plans: \(names). Soll die App den Gesamtplan jetzt an dein Ist anpassen?",
                systemImage: "chart.line.downtrend.xyaxis"
            )
            .font(.footnote)
            .foregroundStyle(Theme.caution)
            .fixedSize(horizontal: false, vertical: true)
            Button("Jetzt fortschreiben") {
                guard let reading = todayLoader.reading else { return }
                errorFromFeedback = false
                Task {
                    if await macroLoader.review(reason: .lowCompliance, snapshot: reading.snapshot, workouts: reading.allWorkouts) != nil {
                        await todayLoader.refreshIfNeeded()
                    }
                }
            }
            .disabled(isBusy || !settings.hasToken)
        }
    }

    // MARK: - Feedback

    private func feedbackSection(_ plan: MacroPlanV2) -> some View {
        Section {
            TextField("z. B. Weniger Laufen im Winter, dafür mehr Rad", text: $feedback, axis: .vertical)
                .lineLimit(2...6)
                .returnClosesKeyboard(text: $feedback)
                .onChange(of: feedback) { _, text in
                    if text.count > MacroRevisionRequest.maxFeedbackLength {
                        feedback = String(text.prefix(MacroRevisionRequest.maxFeedbackLength))
                    }
                }
            Button {
                guard let snapshot = todayLoader.reading?.snapshot else { return }
                errorFromFeedback = true
                Task {
                    if await macroLoader.revise(feedback: feedback, snapshot: snapshot) {
                        feedback = ""
                        // Die nächsten 14 Tage an den neuen Gesamtplan anpassen (einmal je Fassung).
                        await todayLoader.refreshIfNeeded()
                    }
                }
            } label: {
                if macroLoader.isRevising {
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Dein Coach überarbeitet den Gesamtplan …")
                    }
                } else {
                    Text("Gesamtplan anpassen")
                }
            }
            .disabled(
                feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !plan.canGiveFeedback || isBusy || todayLoader.reading == nil || !settings.hasToken
            )
            if !plan.canGiveFeedback {
                Text("Feedback gibt es einmal nach einem neuen Plan und einmal zu jeder Fortschreibung. Die nächste Gelegenheit kommt mit der nächsten Fortschreibung.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = macroLoader.error, errorFromFeedback {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
            }
            if let latest = plan.feedbackRounds.last {
                FeedbackRoundView(round: latest, title: "Zuletzt geändert")
            }
            if plan.feedbackRounds.count > 1 {
                DisclosureGroup("Frühere Runden (\(plan.feedbackRounds.count - 1))") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(plan.feedbackRounds.dropLast().reversed().enumerated()), id: \.offset) { _, round in
                            FeedbackRoundView(round: round, title: nil)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.footnote)
            }
        } header: {
            Text("Feedback zum Gesamtplan")
        } footer: {
            Text("Schreib, was am Gesamtplan anders sein soll. Dein Coach überarbeitet ihn und listet, was sich ändert; die Sicherheitsgrenzen gelten weiter. Die nächsten 14 Tage passen sich danach an.")
        }
    }
}

/// Eine Feedback-Runde: was der Athlet geschrieben hat und was sich daraufhin geändert hat.
private struct FeedbackRoundView: View {
    let round: MacroFeedbackRound
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(round.revisedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label("„\(round.feedback)“", systemImage: "text.bubble")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if round.changes.isEmpty {
                Text("Dein Coach hat nichts geändert.")
                    .font(.footnote)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(round.changes, id: \.self) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(change)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.footnote)
                    }
                }
            }
            AdjustmentsDisclosure(adjustments: round.adjustments)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Überblick

/// Der Gesamtplan auf einen Blick: Ziel, laufende Woche je Sportart, Wochenstunden je Sportart bis zum Zieltag und
/// Testtermine.
private struct MacroOverview: View {
    let plan: MacroPlanV2
    let currentWeek: MacroWeekV2?
    let weeksLeft: Int
    let currentWeekStart: String

    private let registry = SportRegistry.standard

    var body: some View {
        MacroSummitView(profile: MacroSummitProfile(plan: plan, currentWeekStart: currentWeekStart), weeks: plan.weeks.count)
        VStack(alignment: .leading, spacing: 6) {
            Text("Ziel am \(PlanFormatting.germanDate(plan.goalDay)), noch \(weeksLeft) Wochen")
                .font(.headline)
            if let currentWeek {
                Text("Diese Woche: \(PlanFormatting.macroPhase(currentWeek.phase)), etwa \(PlanV2Formatting.duration(minutes: currentWeek.totalMinutes))\(currentWeek.deload ? " (Entlastung)" : "")")
                    .font(.subheadline)
                ForEach(currentWeek.sports, id: \.sport) { volume in
                    Label(PlanV2Formatting.macroVolume(volume, registry: registry), systemImage: registry.symbolName(for: volume.sport))
                        .font(.footnote)
                }
                ForEach(currentWeek.tests, id: \.testID) { test in
                    Label("Test: \(test.displayName)", systemImage: "stopwatch")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                }
                if !currentWeek.focus.isEmpty {
                    Text(currentWeek.focus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(plan.rationale)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        MacroChart(plan: plan, currentWeekStart: currentWeekStart)
        VStack(alignment: .leading, spacing: 3) {
            Text("Höhepunkt je Sportart")
                .font(.footnote.weight(.semibold))
            ForEach(plan.sports, id: \.self) { sport in
                Text("\(registry.displayName(for: sport)): \(PlanV2Formatting.amount(plan.peakAmount(of: sport), unit: unit(of: sport))) pro Woche")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if !plan.testSlots.isEmpty {
            DisclosureGroup("Testtermine (\(plan.testSlots.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plan.testSlots.enumerated()), id: \.offset) { _, slot in
                        Text("Woche ab \(PlanFormatting.shortGermanDate(slot.weekStart)): \(registry.displayName(for: slot.test.sport)), \(slot.test.displayName)")
                            .font(.footnote)
                    }
                }
                .padding(.top, 4)
            }
        }
        AdjustmentsDisclosure(adjustments: plan.adjustments)
    }

    private func unit(of sport: SportID) -> PlanUnit {
        plan.weeks.lazy.compactMap { $0.volume(of: sport)?.unit }.first ?? registry.module(for: sport)?.planUnit ?? .minutes
    }
}

/// Der Weg zum Ziel als Berg wie im Logo (`MacroSummitProfile`): der gegangene Teil in Glut, der Rest gepunktet, auf
/// dem Gipfel die Fahne des Ziels, darunter die Phasen als Farbband.
private struct MacroSummitView: View {
    let profile: MacroSummitProfile
    let weeks: Int

    private struct Run: Identifiable {
        let phase: MacroPhase
        let from: Double
        let to: Double
        var id: Double { from }
    }

    /// Aufeinanderfolgende Wochen derselben Phase als ein Abschnitt.
    private var runs: [Run] {
        var result: [Run] = []
        for segment in profile.segments {
            if let last = result.last, last.phase == segment.phase {
                result[result.count - 1] = Run(phase: last.phase, from: last.from, to: segment.toX)
            } else {
                result.append(Run(phase: segment.phase, from: segment.fromX, to: segment.toX))
            }
        }
        return result
    }

    private var accessibilityText: String {
        guard let index = profile.currentIndex else { return "Weg zum Ziel über \(weeks) Wochen" }
        return "Weg zum Ziel: Woche \(index + 1) von \(weeks)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let points = profile.points.map { position($0, in: geometry.size) }
                let walked = Array(points.prefix((profile.currentIndex ?? -1) + 1))
                ZStack {
                    path(points)
                        .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round, dash: [0.1, 14]))
                    if walked.count > 1 {
                        path(walked)
                            .stroke(Theme.ember, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }
                    if let summit = points.last {
                        SummitFlag()
                            .frame(width: 24, height: 30)
                            .position(x: summit.x + 9, y: summit.y - 17)
                    }
                    if let here = walked.last {
                        Circle()
                            .fill(Theme.ember)
                            .frame(width: 18, height: 18)
                            .overlay { Circle().stroke(Theme.card, lineWidth: 4) }
                            .position(here)
                    }
                }
            }
            .frame(height: 170)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    ForEach(runs) { run in
                        Capsule()
                            .fill(Theme.phase(run.phase))
                            .frame(width: max((run.to - run.from) * geometry.size.width - 3, 4), height: 8)
                            .offset(x: run.from * geometry.size.width)
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 12) {
                ForEach(runs) { run in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.phase(run.phase)).frame(width: 9, height: 9)
                        Text(PlanFormatting.macroPhase(run.phase))
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Raum oben für die Fahne, an den Seiten für die runden Enden.
    private func position(_ point: MacroSummitProfile.Point, in size: CGSize) -> CGPoint {
        let inset: CGFloat = 10
        let top: CGFloat = 36
        return CGPoint(
            x: inset + point.x * (size.width - 2 * inset - 18),
            y: size.height - inset - point.y * (size.height - inset - top)
        )
    }

    private func path(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }
}

/// Die Fahne auf dem Gipfel, in Funke.
private struct SummitFlag: View {
    var body: some View {
        Canvas { context, size in
            var pole = Path()
            pole.move(to: CGPoint(x: 2, y: size.height))
            pole.addLine(to: CGPoint(x: 2, y: 2))
            context.stroke(pole, with: .color(Theme.spark), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var flag = Path()
            flag.move(to: CGPoint(x: 2, y: 2))
            flag.addLine(to: CGPoint(x: size.width, y: size.height * 0.25))
            flag.addLine(to: CGPoint(x: 2, y: size.height * 0.5))
            flag.closeSubpath()
            context.fill(flag, with: .color(Theme.spark))
        }
        .accessibilityHidden(true)
    }
}

/// Wochenstunden je Sportart bis zum Zieltag, gestapelt.
private struct MacroChart: View {
    let plan: MacroPlanV2
    let currentWeekStart: String

    private struct Bar: Identifiable {
        let date: Date
        let sport: String
        let hours: Double
        let isCurrent: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(sport)" }
    }

    private var bars: [Bar] {
        let weekCalendar = WeekCalendar()
        let registry = SportRegistry.standard
        return plan.weeks.flatMap { week -> [Bar] in
            guard let date = weekCalendar.date(from: week.weekStart) else { return [] }
            return week.sports.map {
                Bar(date: date, sport: registry.displayName(for: $0.sport), hours: $0.minutes / 60, isCurrent: week.weekStart == currentWeekStart)
            }
        }
    }

    var body: some View {
        let data = bars
        if data.contains(where: { $0.hours > 0 }) {
            Chart(data) { bar in
                BarMark(
                    x: .value("Woche", bar.date, unit: .weekOfYear),
                    y: .value("Stunden", bar.hours)
                )
                .foregroundStyle(by: .value("Sportart", bar.sport))
                .opacity(bar.isCurrent ? 1 : 0.75)
            }
            .chartForegroundStyleScale(domain: plan.sports.map { SportRegistry.standard.displayName(for: $0) }, range: plan.sports.map { Theme.sport($0) })
            .chartYAxisLabel("Stunden")
            .frame(height: 160)
            .accessibilityLabel("Wochenstunden je Sportart bis zum Ziel")
        }
    }
}

private struct MacroWeekRow: View {
    let week: MacroWeekV2
    let isCurrent: Bool

    private let registry = SportRegistry.standard

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(isCurrent ? "Diese Woche" : "Ab \(PlanFormatting.shortGermanDate(week.weekStart))") · \(PlanFormatting.macroPhase(week.phase))\(week.deload ? " · Entlastung" : "")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrent ? Theme.accent : Color.primary)
                Text("Etwa \(PlanV2Formatting.duration(minutes: week.totalMinutes))")
                    .font(.subheadline)
                Text(week.sports.map { "\(registry.displayName(for: $0.sport)) \(PlanV2Formatting.amount($0.amount, unit: $0.unit))" }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !week.tests.isEmpty {
                    Text("Test: \(week.tests.map(\.displayName).joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
