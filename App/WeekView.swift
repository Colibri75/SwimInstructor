import SwiftUI
import SwimInstructorCore

/// Plan: die nächsten sieben Tage mit null bis zwei Einheiten je Tag über alle Sportarten (jeden Tag beim ersten Öffnen
/// neu auf Zustand, Training und Gesamtplan abgestimmt) mit Änderungen des Athleten, darunter der Gesamtplan bis zum Ziel
/// mit dem Feedback dazu. Die Tage sind ein Gerüst (Sportart, Art, Umfang, Schwerpunkt), die Schritte entstehen am Tag
/// selbst im Tab Heute.
struct WeekView: View {
    @EnvironmentObject private var weekLoader: MultiSportWeekLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @EnvironmentObject private var settings: BackendSettings

    @State private var wish = ""
    @State private var editedDay: EditedDay?

    private let progress = MultiSportWeekProgressCalculator()
    private let weekCalendar = WeekCalendar()
    private let registry = SportRegistry.standard

    private var weekStart: String { weekLoader.selectedWeekStart }
    private var plan: WeekPlanV2? { weekLoader.selectedWeek }

    private var statuses: [MultiSportDayStatus] {
        progress.statuses(plan: plan, weekStart: weekStart, workouts: todayLoader.reading?.allWorkouts ?? [], now: Date())
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if let plan, !plan.rationale.isEmpty {
                    overviewSection(plan)
                }
                daysSection
                planSection
                // Der Gesamtplan steht unten: Zuerst zählt, was in den nächsten Tagen ansteht.
                MacroPlanSections()
            }
            .navigationTitle("Plan")
            .swipeClosesKeyboard()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        weekLoader.shiftSelectedWeek(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Vorige Woche")
                    Button {
                        weekLoader.shiftSelectedWeek(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Nächste Woche")
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

    // MARK: - Überblick

    private var rangeText: String {
        let dates = weekCalendar.dates(inWeekStarting: weekStart)
        guard let first = dates.first, let last = dates.last else { return weekStart }
        return "\(PlanFormatting.shortGermanDate(first)) – \(PlanFormatting.shortGermanDate(last))"
    }

    private var summarySection: some View {
        Section {
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
        } header: {
            Text(weekStart == weekLoader.currentWeekStart ? "Diese Woche, \(rangeText)" : "Woche \(rangeText)")
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
            ForEach(statuses) { status in
                Button {
                    editedDay = EditedDay(date: status.date)
                } label: {
                    WeekDayRow(status: status, isToday: status.date == weekLoader.todayKey)
                }
                .buttonStyle(.plain)
                .listRowBackground(status.date == weekLoader.todayKey ? Color.accentColor.opacity(0.1) : nil)
            }
        } header: {
            Text("Tage")
        } footer: {
            if plan != nil {
                Text("Tippe auf einen Tag, um ihn anzupassen: Umfang ändern, Sportart tauschen, eine Einheit dazunehmen, mit einem anderen Tag tauschen oder \"keine Zeit\" markieren.")
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
                        ProgressView()
                        Text("Claude plant die nächsten Tage …")
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
