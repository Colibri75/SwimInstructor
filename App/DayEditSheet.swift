import SwiftUI
import SwimInstructorCore

/// Ein Tag im Plan-Tab: der konkrete Trainingsplan mit allen Schritten (heute der Tagesplan, vorher der aus dem Verlauf,
/// später eine Vorschau auf Knopfdruck), dazu anpassen: je Einheit Umfang und Sportart ändern oder sie entfernen, eine
/// Einheit dazunehmen, Ruhetag, "keine Zeit", mit einem anderen Tag tauschen. Vergangene Tage lassen sich auf einen
/// freien Ruhetag nachholen.
struct DayEditSheet: View {
    let date: String

    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @Environment(\.dismiss) private var dismiss

    private let progress = MultiSportWeekProgressCalculator()
    private let weekCalendar = WeekCalendar()
    private let registry = SportRegistry.standard

    private var weekStart: String {
        weekCalendar.date(from: date).map { weekCalendar.weekStart(containing: $0) } ?? weekLoader.selectedWeekStart
    }

    private var week: WeekPlanV2? { weekLoader.week(starting: weekStart) }

    private var status: MultiSportDayStatus? {
        progress.statuses(plan: week, weekStart: weekStart, workouts: todayLoader.reading?.allWorkouts ?? [], now: Date())
            .first { $0.date == date }
    }

    /// Andere Tage derselben Woche, die sich noch ändern lassen.
    private var editableDates: [String] {
        weekCalendar.dates(inWeekStarting: weekStart).filter { weekLoader.isEditable($0) && $0 != date }
    }

    var body: some View {
        NavigationStack {
            List {
                if let status {
                    plannedSection(status)
                    trainingPlanSections(status)
                    if status.workoutCount > 0 {
                        doneSection(status)
                    }
                    if weekLoader.isEditable(date) {
                        if let day = status.day, !day.isUnavailable {
                            ForEach(Array(day.sessions.enumerated()), id: \.offset) { index, session in
                                sessionSection(index: index, session: session, count: day.sessions.count)
                            }
                        }
                        editSection(status)
                    } else {
                        catchUpSection(status)
                    }
                }
            }
            .navigationTitle("\(weekCalendar.weekdayName(date)), \(PlanFormatting.shortGermanDate(date))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Geplant

    private func plannedSection(_ status: MultiSportDayStatus) -> some View {
        Section("Geplant") {
            if let day = status.day {
                if day.isUnavailable || day.isRestDay {
                    Text(day.isUnavailable ? "Keine Zeit" : "Ruhetag")
                } else {
                    ForEach(Array(day.sessions.enumerated()), id: \.offset) { _, session in
                        PlannedSessionLine(session: session)
                    }
                    LabeledContent("Dauer") { Text("ca. \(PlanV2Formatting.duration(minutes: day.totalMinutes))") }
                    if !day.focus.isEmpty {
                        Text(day.focus)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if day.isEdited {
                    Label("von dir angepasst", systemImage: "pencil")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Für diesen Tag gibt es keinen Plan.")
                    .foregroundStyle(.secondary)
            }
            Label(PlanV2Formatting.stateText(status.state), systemImage: WeekStateStyle.symbol(status.state))
                .font(.footnote)
                .foregroundStyle(WeekStateStyle.color(status.state))
        }
    }

    // MARK: Konkreter Trainingsplan

    @ViewBuilder
    private func trainingPlanSections(_ status: MultiSportDayStatus) -> some View {
        if let response = todayLoader.dayPlan(on: date) {
            let plan = response.plan
            if plan.isRestDay {
                Section("Trainingsplan") {
                    Text(plan.rationale.isEmpty ? "Ruhetag" : plan.rationale)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section {
                    if !plan.rationale.isEmpty {
                        Text(plan.rationale)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Trainingsplan")
                } footer: {
                    Text(trainingPlanFooter(response))
                }
                ForEach(Array(plan.sessions.enumerated()), id: \.offset) { index, session in
                    Section {
                        SessionCardView(session: session, previousSport: index > 0 ? plan.sessions[index - 1].sport : nil)
                    }
                }
                if !plan.extras.isEmpty {
                    Section {
                        ForEach(Array(plan.extras.enumerated()), id: \.offset) { _, extra in
                            ExtraCardView(extra: extra)
                        }
                    }
                }
                if !plan.coachNotes.isEmpty {
                    Section("Hinweise") {
                        ForEach(plan.coachNotes, id: \.self) { note in
                            Text(note)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } else if todayLoader.canPreview(date) {
            Section {
                Button {
                    Task { await todayLoader.loadPreview(for: date) }
                } label: {
                    if todayLoader.loadingPreviewDate == date {
                        HStack(spacing: 12) {
                            ForgeAnimation()
                            Text("Dein Coach schreibt den Plan für diesen Tag …")
                        }
                    } else {
                        Label("Trainingsplan anzeigen", systemImage: "list.bullet.rectangle")
                    }
                }
                .disabled(todayLoader.loadingPreviewDate != nil || todayLoader.reading == nil)
                if let error = todayLoader.previewError, error.date == date {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Trainingsplan")
            } footer: {
                Text("Die Einheiten mit allen Schritten, Zielen und Equipment. Am Tag selbst stimmt dein Coach den Plan noch einmal auf deinen Zustand ab.")
            }
        } else if date == weekLoader.todayKey, status.day?.isRestDay == false {
            Section("Trainingsplan") {
                Text("Der Plan für heute entsteht im Tab Heute.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trainingPlanFooter(_ response: DayPlanV2Response) -> String {
        if date > weekLoader.todayKey {
            return "Vorschau. Am Tag selbst stimmt dein Coach den Plan noch einmal auf deinen Zustand ab; nach einer Änderung an diesem Tag lässt sich die Vorschau neu holen."
        }
        if date < weekLoader.todayKey { return "So war der Tag geplant." }
        return "Der Plan von heute, wie im Tab Heute."
    }

    private func doneSection(_ status: MultiSportDayStatus) -> some View {
        Section("Gemacht") {
            ForEach(status.comparisons.filter { $0.workoutCount > 0 }) { comparison in
                LabeledContent {
                    Text(PlanV2Formatting.comparison(planned: comparison.planned, actual: comparison.actual, unit: comparison.unit))
                        .monospacedDigit()
                } label: {
                    Label(registry.displayName(for: comparison.sport), systemImage: registry.symbolName(for: comparison.sport))
                }
            }
        }
    }

    // MARK: Einheit anpassen (heute und später)

    private func sessionSection(index: Int, session: WeekSession, count: Int) -> some View {
        Section {
            Stepper(
                value: Binding(
                    get: { session.amount },
                    set: { weekLoader.setAmount(date, session: index, amount: $0) }
                ),
                in: MultiSportWeekEditor.manualRange(for: session.unit),
                step: MultiSportWeekEditor.amountStep(for: session.unit)
            ) {
                Text("Umfang: \(PlanV2Formatting.amount(session.amount, unit: session.unit))")
            }
            LabeledContent("Art") {
                Text(session.test.map { "Test: \($0.displayName)" }
                     ?? "\(PlanFormatting.sessionType(session.sessionType)), \(PlanFormatting.intensity(session.intensity))")
            }
            if session.unit == .meters {
                LabeledContent("Dauer") { Text("ca. \(PlanV2Formatting.duration(minutes: session.minutes))") }
            }
            let others = registry.ids.filter { $0 != session.sport }
            if !others.isEmpty {
                Menu("Sportart tauschen") {
                    ForEach(others, id: \.self) { sport in
                        Button {
                            weekLoader.changeSport(date, session: index, to: sport)
                        } label: {
                            Label(registry.displayName(for: sport), systemImage: registry.symbolName(for: sport))
                        }
                    }
                }
            }
            Button("Einheit entfernen", role: .destructive) {
                weekLoader.removeSession(date, session: index)
            }
        } header: {
            Text(count > 1 ? "Einheit \(index + 1): \(registry.displayName(for: session.sport))" : registry.displayName(for: session.sport))
        } footer: {
            if !session.focus.isEmpty {
                Text(session.focus)
            }
        }
    }

    // MARK: Tag anpassen

    @ViewBuilder
    private func editSection(_ status: MultiSportDayStatus) -> some View {
        let day = status.day
        let unavailable = day?.isUnavailable == true
        Section {
            if unavailable {
                Button("Doch wieder Zeit") { weekLoader.clearUnavailable(date) }
            } else {
                if let day, day.sessions.count < MultiSportWeekEditor.maxSessionsPerDay {
                    Menu("Einheit dazunehmen") {
                        ForEach(registry.ids, id: \.self) { sport in
                            Button {
                                weekLoader.addSession(date, sport: sport)
                            } label: {
                                Label(registry.displayName(for: sport), systemImage: registry.symbolName(for: sport))
                            }
                        }
                    }
                }
                Button("Keine Zeit an diesem Tag") {
                    weekLoader.markUnavailable(date)
                    dismiss()
                }
                if let day, !day.isRestDay {
                    Button("Als Ruhetag setzen") {
                        weekLoader.setRest(date)
                        dismiss()
                    }
                }
                swapMenu
            }
        } header: {
            Text("Tag anpassen")
        } footer: {
            Text(date == weekLoader.todayKey
                 ? "Die Einheiten selbst stehen im Tab Heute. Nach einer Änderung dort \"Plan neu erstellen\" tippen, damit sie zur neuen Vorgabe passen."
                 : "Höchstens \(MultiSportWeekEditor.maxSessionsPerDay) Einheiten am Tag. Beim Tausch der Sportart rechnet die App den Umfang über die Dauer um.")
        }
    }

    @ViewBuilder
    private var swapMenu: some View {
        let others = editableDates.filter { week?.day(on: $0)?.isUnavailable != true }
        if !others.isEmpty {
            Menu("Mit anderem Tag tauschen") {
                ForEach(others, id: \.self) { other in
                    Button("\(weekCalendar.weekdayName(other)), \(PlanFormatting.shortGermanDate(other)): \(PlanV2Formatting.daySummary(week?.day(on: other)))") {
                        weekLoader.swapDays(date, other)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: Nachholen (vergangene Tage)

    @ViewBuilder
    private func catchUpSection(_ status: MultiSportDayStatus) -> some View {
        if let day = status.day, !day.isRestDay, status.state == .missed || status.state == .shorter {
            let restDays = editableDates.filter { other in
                guard let candidate = week?.day(on: other) else { return false }
                return candidate.isRestDay && !candidate.isUnavailable
            }
            Section {
                if restDays.isEmpty {
                    Text("Es gibt keinen freien Ruhetag mehr in dieser Woche.")
                        .foregroundStyle(.secondary)
                } else {
                    Menu("Auf einen Ruhetag verschieben") {
                        ForEach(restDays, id: \.self) { target in
                            Button("\(weekCalendar.weekdayName(target)), \(PlanFormatting.shortGermanDate(target))") {
                                weekLoader.moveToRestDay(from: date, to: target)
                                dismiss()
                            }
                        }
                    }
                }
            } header: {
                Text("Nachholen")
            } footer: {
                Text("Das Verpasste landet auf dem gewählten Ruhetag. Wer lieber neu planen will, nutzt im Plan-Tab \"Nächste 7 Tage neu planen\": Dein Coach berücksichtigt, was du schon trainiert hast.")
            }
        }
    }
}
