import SwiftUI
import SwimInstructorCore

/// Plan-Tab, getrennt in zwei Teile: der Wochenplan (eine Kalenderwoche mit den geplanten Tagen, null bis zwei Einheiten
/// je Tag über alle Sportarten, jeden Tag beim ersten Öffnen neu auf Zustand, Training und Gesamtplan abgestimmt) und der
/// Gesamtplan bis zum Ziel mit Fortschreibung und Feedback. Einheiten gibt es nur für die nächsten sieben Tage; spätere
/// Wochen zeigen die Vorgabe des Gesamtplans und den Wochenraster. Die Schritte entstehen am Tag selbst im Tab Heute.
struct WeekView: View {
    private enum Part: Hashable {
        case week, macro
    }

    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var macroLoader: MultiSportMacroLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @EnvironmentObject private var settings: BackendSettings

    @State private var part = Part.week
    @State private var wish = ""
    @State private var editedDay: EditedDay?

    private let progress = MultiSportWeekProgressCalculator()
    private let weekCalendar = WeekCalendar()
    private let registry = SportRegistry.standard
    private let scheduleStore = UserDefaultsWeeklyScheduleStore()
    private let goalStore = UserDefaultsTrainingGoalStore()

    private var weekStart: String { weekLoader.selectedWeekStart }
    private var weekEnd: String { weekCalendar.addingDays(6, to: weekStart) ?? weekStart }
    private var plan: WeekPlanV2? { weekLoader.selectedWeek }
    private var macroWeek: MacroWeekV2? { macroLoader.plan?.week(starting: weekStart) }

    /// Die Woche liegt ganz nach den geplanten sieben Tagen: Es gibt nur die Vorgabe des Gesamtplans.
    private var isPreviewWeek: Bool { weekLoader.isBeyondWindow(weekStart) }

    /// Die Woche enthält Tage der nächsten sieben Tage: Hier lässt sich neu planen.
    private var overlapsWindow: Bool { weekStart <= weekLoader.windowEnd && weekEnd >= weekLoader.todayKey }

    private var statuses: [MultiSportDayStatus] {
        progress.statuses(plan: plan, weekStart: weekStart, workouts: todayLoader.reading?.allWorkouts ?? [], now: Date())
    }

    var body: some View {
        NavigationStack {
            Group {
                switch part {
                case .week:
                    weekList
                case .macro:
                    List {
                        MacroPlanSections { start in
                            // Eine Woche aus dem Gesamtplan im Wochenplan öffnen.
                            if weekLoader.selectWeek(containing: start) { part = .week }
                        }
                    }
                    .swipeClosesKeyboard()
                }
            }
            .navigationTitle(part == .week ? "Wochenplan" : "Gesamtplan")
            .navigationBarTitleDisplayMode(.inline)
            .settingsToolbar()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Ansicht", selection: $part) {
                        Text("Woche").tag(Part.week)
                        Text("Gesamtplan").tag(Part.macro)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if part == .week {
                        Button {
                            weekLoader.shiftSelectedWeek(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!weekLoader.canShiftSelectedWeek(by: -1))
                        .accessibilityLabel("Vorige Woche")
                        Button {
                            weekLoader.shiftSelectedWeek(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!weekLoader.canShiftSelectedWeek(by: 1))
                        .accessibilityLabel("Nächste Woche")
                    }
                }
            }
            // Liest Health neu und stimmt die Tage einmal am Tag ab. Einen neuen Tagesplan holt nur der Tab Heute.
            .refreshable { await todayLoader.refreshIfNeeded() }
            .sheet(item: $editedDay) { item in
                DayEditSheet(date: item.date)
            }
        }
        .task {
            if todayLoader.reading == nil { await todayLoader.refreshIfNeeded() }
        }
    }

    private var weekList: some View {
        List {
            weekHeaderSection
            if let macroWeek {
                macroTargetSection(macroWeek)
            }
            if let plan, !plan.rationale.isEmpty {
                overviewSection(plan)
            }
            daysSection
            if overlapsWindow {
                planSection
            }
        }
        .swipeClosesKeyboard()
    }

    // MARK: - Überblick

    private var rangeText: String {
        let dates = weekCalendar.dates(inWeekStarting: weekStart)
        guard let first = dates.first, let last = dates.last else { return weekStart }
        return "\(PlanFormatting.shortGermanDate(first)) – \(PlanFormatting.shortGermanDate(last))"
    }

    private var weekTitle: String {
        if weekStart == weekLoader.currentWeekStart { return "Diese Woche, \(rangeText)" }
        if weekStart == weekCalendar.addingDays(7, to: weekLoader.currentWeekStart) { return "Nächste Woche, \(rangeText)" }
        return "Woche \(rangeText)"
    }

    /// Geplant gegen trainiert; für eine Woche ganz in der Zukunft ohne Plan nur der Hinweis, wann sie geplant wird.
    private var weekHeaderSection: some View {
        Section {
            if plan == nil && weekStart > weekLoader.currentWeekStart {
                Text(previewText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let summary = progress.summary(of: statuses)
                if plan != nil {
                    LabeledContent("Geplant") { Text(PlanV2Formatting.duration(minutes: summary.plannedMinutes)) }
                }
                LabeledContent("Trainiert") { Text(PlanV2Formatting.duration(minutes: summary.actualMinutes)) }
                ForEach(summary.sports) { total in
                    LabeledContent {
                        Text(PlanV2Formatting.comparison(planned: total.planned, actual: total.actual, unit: total.unit))
                            .monospacedDigit()
                    } label: {
                        Label(registry.displayName(for: total.sport), systemImage: registry.symbolName(for: total.sport))
                    }
                }
                if plan != nil {
                    LabeledContent("Einheiten") {
                        Text("\(summary.sessionsDone) von \(summary.sessionsDue) fälligen, \(summary.sessionsPlanned) geplant")
                    }
                }
            }
        } header: {
            Text(weekTitle)
        }
    }

    /// Ab wann die Einheiten der Woche feststehen: Die App plant immer die nächsten sieben Tage.
    private var previewText: String {
        let plannedFrom = weekCalendar.addingDays(-(MultiSportWeekLoader.windowDays - 1), to: weekStart) ?? weekStart
        let when = PlanFormatting.germanDate(plannedFrom)
        if macroWeek != nil {
            return "Die einzelnen Einheiten plant die App immer für die nächsten sieben Tage, für diese Woche ab \(when). Bis dahin siehst du hier die Vorgabe aus dem Gesamtplan und deinen Wochenraster."
        }
        return "Die einzelnen Einheiten plant die App immer für die nächsten sieben Tage, für diese Woche ab \(when). Für diese Woche gibt es noch keine Vorgabe aus dem Gesamtplan."
    }

    /// Was der Gesamtplan für die Woche vorgibt: Phase, Umfang je Sportart, Tests und Schwerpunkt.
    private func macroTargetSection(_ week: MacroWeekV2) -> some View {
        Section("Vorgabe aus dem Gesamtplan") {
            Text("\(PlanFormatting.macroPhase(week.phase)), etwa \(PlanV2Formatting.duration(minutes: week.totalMinutes))\(week.deload ? " (Entlastung)" : "")")
                .font(.subheadline.weight(.semibold))
            ForEach(week.sports, id: \.sport) { volume in
                Label(PlanV2Formatting.macroVolume(volume, registry: registry), systemImage: registry.symbolName(for: volume.sport))
            }
            ForEach(week.tests, id: \.testID) { test in
                Label("Test: \(test.displayName)", systemImage: "stopwatch")
                    .foregroundStyle(.tint)
            }
            if !week.focus.isEmpty {
                Text(week.focus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func overviewSection(_ plan: WeekPlanV2) -> some View {
        Section("Überblick") {
            Text(plan.rationale)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let wish = plan.wishes, !wish.isEmpty {
                Label("Dein Wunsch: \(wish)", systemImage: "text.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AdjustmentsDisclosure(adjustments: plan.adjustments)
        }
    }

    // MARK: - Tage

    private var daysSection: some View {
        Section {
            let schedule = scheduleStore.schedule(for: goalStore.goal())
            ForEach(statuses) { status in
                if status.day == nil && weekLoader.isBeyondWindow(status.date) {
                    // Noch nicht geplant: was der Wochenraster für den Tag vorsieht.
                    WeekDayPreviewRow(date: status.date, scheduled: schedule.day(on: status.date, weekCalendar: weekCalendar))
                } else {
                    Button {
                        editedDay = EditedDay(date: status.date)
                    } label: {
                        WeekDayRow(status: status, isToday: status.date == weekLoader.todayKey)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(status.date == weekLoader.todayKey ? Color.accentColor.opacity(0.1) : nil)
                }
            }
        } header: {
            Text("Tage")
        } footer: {
            if plan != nil {
                Text("Tippe auf einen geplanten Tag, um ihn anzupassen: Umfang ändern, Sportart tauschen, eine Einheit dazunehmen, mit einem anderen Tag tauschen oder \"keine Zeit\" markieren.")
            } else if isPreviewWeek {
                Text("Die Tage zeigen deinen Wochenraster. Ändern kannst du ihn in den Einstellungen.")
            }
        }
    }

    // MARK: - Planen

    @ViewBuilder
    private var planSection: some View {
        Section {
            TextField("Wunsch für die nächsten Tage (optional)", text: $wish, axis: .vertical)
                .lineLimit(1...4)
                .returnClosesKeyboard(text: $wish)
                .onChange(of: wish) { _, text in
                    if text.count > DailyWish.maxLength {
                        wish = String(text.prefix(DailyWish.maxLength))
                    }
                }
            Button {
                Task { await weekLoader.planNextDays(wishes: wish) }
            } label: {
                if weekLoader.isLoading {
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Dein Coach plant die nächsten Tage …")
                    }
                } else {
                    Text("Nächste 7 Tage neu planen")
                }
            }
            .disabled(weekLoader.isLoading || !settings.hasToken)
            if !settings.hasToken || weekLoader.needsConfiguration {
                Text("Noch kein Server-Token hinterlegt. Trage es im Tab Heute unter dem Zahnrad ein.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error = weekLoader.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Planen")
        } footer: {
            Text("Die App plant die nächsten sieben Tage jeden Tag beim ersten Öffnen neu und stimmt sie auf deinen Zustand, dein Training der letzten Tage und den Gesamtplan ab. \"Keine Zeit\" bleibt dabei erhalten, andere Änderungen von Hand gelten bis zur nächsten Anpassung. Die genauen Schritte mit Equipment entstehen am Tag selbst im Tab Heute.")
        }
    }
}

/// Der Tag, den das Anpassen-Blatt zeigt.
private struct EditedDay: Identifiable {
    let date: String
    var id: String { date }
}

// MARK: - Zeile

/// Ein Tag nach den geplanten sieben Tagen: nur was der Wochenraster vorsieht.
private struct WeekDayPreviewRow: View {
    let date: String
    let scheduled: WeeklySchedule.Day?

    private let weekCalendar = WeekCalendar()
    private let registry = SportRegistry.standard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(weekCalendar.weekdayShort(date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(date.suffix(2)))
                    .font(.title3.monospacedDigit())
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                if let scheduled, scheduled.trains {
                    Text("Training, bis \(PlanV2Formatting.duration(minutes: Double(scheduled.maxMinutes)))")
                        .font(.subheadline)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Ruhetag laut Wochenraster")
                        .font(.subheadline)
                }
                Text("Einheiten folgen sieben Tage vorher")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }

    /// "Abends, Laufen": Tageszeit und feste Sportart, soweit eingestellt.
    private var detail: String? {
        let parts = [scheduled?.timeOfDay?.title, scheduled?.sport.map { registry.displayName(for: $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

private struct WeekDayRow: View {
    let status: MultiSportDayStatus
    let isToday: Bool

    private let weekCalendar = WeekCalendar()
    private let registry = SportRegistry.standard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(weekCalendar.weekdayShort(status.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                Text(String(status.date.suffix(2)))
                    .font(.title3.monospacedDigit())
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                if let day = status.day {
                    if day.isUnavailable || day.isRestDay {
                        Text(day.isUnavailable ? "Keine Zeit" : "Ruhetag")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        ForEach(Array(day.sessions.enumerated()), id: \.offset) { _, session in
                            PlannedSessionLine(session: session)
                        }
                        if !day.focus.isEmpty {
                            Text(day.focus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("Nicht geplant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if status.workoutCount > 0 {
                    Text(done)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: WeekStateStyle.symbol(status.state))
                .foregroundStyle(WeekStateStyle.color(status.state))
                .accessibilityLabel(PlanV2Formatting.stateText(status.state))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Gemacht: Schwimmen 1.200 m, Laufen 35 min".
    private var done: String {
        let parts = status.comparisons.filter { $0.workoutCount > 0 }.map {
            "\(registry.displayName(for: $0.sport)) \(PlanV2Formatting.amount($0.actual, unit: $0.unit))"
        }
        return "Gemacht: \(parts.joined(separator: ", "))"
    }
}

enum WeekStateStyle {
    static func symbol(_ state: WeekDayState) -> String {
        switch state {
        case .followed, .restKept: return "checkmark.circle.fill"
        case .shorter, .longer: return "arrow.up.arrow.down.circle"
        case .restBroken: return "exclamationmark.circle"
        case .missed: return "xmark.circle"
        case .today: return "circle.dashed"
        case .upcoming: return "circle"
        case .skipped: return "moon.zzz"
        case .unplanned: return "minus.circle"
        }
    }

    static func color(_ state: WeekDayState) -> Color {
        switch state {
        case .followed, .restKept: return .green
        case .shorter, .longer, .restBroken: return .orange
        case .missed: return .red
        case .today: return .accentColor
        case .upcoming, .skipped, .unplanned: return .secondary
        }
    }
}
