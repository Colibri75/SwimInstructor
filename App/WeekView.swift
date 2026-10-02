import SwiftUI
import SwimInstructorCore

/// Plan: oben der Gesamtplan bis zum Ziel, darunter die nächsten sieben Tage (jeden Tag beim ersten Öffnen
/// neu auf Zustand, Stand und Vorwoche abgestimmt) mit Änderungen des Athleten. Der Plan der Tage ist ein
/// Gerüst (Typ, Umfang, Schwerpunkt je Tag), die Abschnitte entstehen am Tag selbst im Tab Heute.
struct WeekView: View {
    @EnvironmentObject private var weekLoader: WeekPlanLoader
    @EnvironmentObject private var macroLoader: MacroPlanLoader
    @EnvironmentObject private var todayLoader: TodayPlanLoader
    @EnvironmentObject private var settings: BackendSettings

    @State private var wish = ""
    @State private var editedDay: EditedDay?

    private let progress = WeekProgressCalculator()
    private let weekCalendar = WeekCalendar()

    private var weekStart: String { weekLoader.selectedWeekStart }
    private var plan: WeekPlan? { weekLoader.selectedWeek }

    private var statuses: [WeekDayStatus] {
        progress.statuses(plan: plan, weekStart: weekStart, workouts: todayLoader.reading?.workouts ?? [], now: Date())
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
                // Der Gesamtplan steht ganz unten: Zuerst zählt, was in den nächsten Tagen ansteht.
                macroSection
            }
            .navigationTitle("Plan")
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
            // Liest nur Health neu. Einen neuen Plan holt nur der Knopf unten (das kostet einen Claude-Aufruf).
            .refreshable { await todayLoader.refreshIfNeeded() }
            .sheet(item: $editedDay) { item in
                DayEditSheet(date: item.date)
            }
        }
        .task {
            if todayLoader.reading == nil { await todayLoader.refreshIfNeeded() }
        }
    }

    // MARK: - Gesamtplan

    private var macroSection: some View {
        Section {
            if let macro = macroLoader.plan {
                MacroSummary(plan: macro, currentWeek: macroLoader.currentWeek, weeksLeft: macroLoader.weeksUntilGoal, currentWeekStart: macroLoader.currentWeekStart)
                if !macroLoader.isCurrent {
                    Label("Das Ziel hat sich geändert oder der Plan ist abgelaufen. Berechne ihn neu.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Noch kein Gesamtplan. Er legt die Wochen bis zu deinem Ziel fest, die nächsten sieben Tage richten sich danach.")
                    .foregroundStyle(.secondary)
            }
            Button {
                guard let snapshot = todayLoader.reading?.snapshot else { return }
                Task { await macroLoader.regenerate(snapshot: snapshot) }
            } label: {
                if macroLoader.isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Claude plant bis zum Ziel …")
                    }
                } else {
                    Text(macroLoader.plan == nil ? "Gesamtplan erstellen" : "Gesamtplan neu berechnen")
                }
            }
            .disabled(macroLoader.isLoading || todayLoader.reading == nil || !settings.hasToken)
            if let error = macroLoader.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Gesamtplan bis zum Ziel")
        } footer: {
            Text("Der Gesamtplan wird beim Start und bei einer Zieländerung erstellt. Neu berechnen lohnt sich, wenn sich dein Stand stark geändert hat (Pause, Krankheit, Fortschritt).")
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
                LabeledContent("Geplant") { Text(PlanFormatting.meters(summary.plannedMeters)) }
            }
            LabeledContent("Geschwommen") { Text(PlanFormatting.meters(summary.swumMeters)) }
            if plan != nil {
                LabeledContent("Einheiten") {
                    Text("\(summary.sessionsDone) von \(summary.sessionsDue) fällige, \(summary.sessionsPlanned) geplant")
                }
            }
        } header: {
            Text(weekStart == weekLoader.currentWeekStart ? "Diese Woche, \(rangeText)" : "Woche \(rangeText)")
        }
    }

    private func overviewSection(_ plan: WeekPlan) -> some View {
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
            if !plan.adjustments.isEmpty {
                DisclosureGroup("Zur Sicherheit angepasst (\(plan.adjustments.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.adjustments, id: \.self) { adjustment in
                            Text(adjustment)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
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
                Text("Tippe auf einen Tag, um ihn anzupassen: Umfang ändern, mit einem anderen Tag tauschen oder \"keine Zeit\" markieren.")
            }
        }
    }

    // MARK: - Planen

    @ViewBuilder
    private var planSection: some View {
        Section {
            TextField("Wunsch für die nächsten Tage (optional)", text: $wish, axis: .vertical)
                .lineLimit(1...4)
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
            Text("Die App plant die nächsten sieben Tage jeden Tag beim ersten Öffnen neu und stimmt sie auf deinen Zustand, deinen Trainingsstand, die Vorwoche und den Gesamtplan ab. \"Keine Zeit\" bleibt dabei erhalten, andere Änderungen von Hand gelten bis zur nächsten Anpassung. Die genauen Abschnitte mit Equipment entstehen am Tag selbst im Tab Heute.")
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
    let status: WeekDayStatus
    let isToday: Bool

    private let weekCalendar = WeekCalendar()

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

            VStack(alignment: .leading, spacing: 2) {
                if let day = status.plan {
                    Text(title(day))
                        .font(.subheadline.weight(.semibold))
                    Text(day.focus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nicht geplant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if status.actualMeters > 0 || status.workoutCount > 0 {
                    Text(swum)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Label(PlanFormatting.stateText(status.state), systemImage: WeekStateStyle.symbol(status.state))
                .labelStyle(.iconOnly)
                .foregroundStyle(WeekStateStyle.color(status.state))
                .accessibilityLabel(PlanFormatting.stateText(status.state))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func title(_ day: WeekDayPlan) -> String {
        if day.isRestDay { return day.isUnavailable ? "Keine Zeit" : "Ruhetag" }
        return "\(PlanFormatting.sessionType(day.sessionType)) · \(PlanFormatting.meters(day.targetDistanceMeters)) · \(PlanFormatting.intensity(day.intensity))"
    }

    private var swum: String {
        let count = status.workoutCount == 1 ? "1 Einheit" : "\(status.workoutCount) Einheiten"
        return status.actualMeters > 0
            ? "Geschwommen: \(PlanFormatting.meters(Int(status.actualMeters))) (\(count))"
            : "Geschwommen: \(count), ohne Streckenangabe"
    }
}

private enum WeekStateStyle {
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

// MARK: - Tag anpassen

private struct DayEditSheet: View {
    let date: String

    @EnvironmentObject private var weekLoader: WeekPlanLoader
    @EnvironmentObject private var todayLoader: TodayPlanLoader
    @Environment(\.dismiss) private var dismiss

    private let progress = WeekProgressCalculator()
    private let weekCalendar = WeekCalendar()

    private var status: WeekDayStatus? {
        progress.statuses(
            plan: weekLoader.selectedWeek,
            weekStart: weekLoader.selectedWeekStart,
            workouts: todayLoader.reading?.workouts ?? [],
            now: Date()
        ).first { $0.date == date }
    }

    private var editableDates: [String] {
        weekCalendar.dates(inWeekStarting: weekLoader.selectedWeekStart).filter { weekLoader.isEditable($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let status {
                    plannedSection(status)
                    if status.actualMeters > 0 || status.workoutCount > 0 {
                        Section("Geschwommen") {
                            Text(status.actualMeters > 0
                                 ? "\(PlanFormatting.meters(Int(status.actualMeters))) in \(status.workoutCount) Einheit(en)"
                                 : "\(status.workoutCount) Einheit(en), ohne Streckenangabe")
                        }
                    }
                    if weekLoader.isEditable(date) {
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
        .presentationDetents([.medium, .large])
    }

    // MARK: Geplant

    private func plannedSection(_ status: WeekDayStatus) -> some View {
        Section("Geplant") {
            if let day = status.plan {
                if day.isRestDay {
                    Text(day.isUnavailable ? "Keine Zeit" : "Ruhetag")
                } else {
                    LabeledContent("Einheit") { Text(PlanFormatting.sessionType(day.sessionType)) }
                    LabeledContent("Umfang") { Text(PlanFormatting.meters(day.targetDistanceMeters)) }
                    LabeledContent("Dauer") { Text("ca. \(day.estimatedDurationMinutes) min") }
                    LabeledContent("Intensität") { Text(PlanFormatting.intensity(day.intensity)) }
                }
                if !day.focus.isEmpty, !day.isRestDay {
                    Text(day.focus)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            Label(PlanFormatting.stateText(status.state), systemImage: WeekStateStyle.symbol(status.state))
                .font(.footnote)
                .foregroundStyle(WeekStateStyle.color(status.state))
        }
    }

    // MARK: Anpassen (heute und später)

    @ViewBuilder
    private func editSection(_ status: WeekDayStatus) -> some View {
        let day = status.plan
        let unavailable = day?.isUnavailable == true
        Section {
            if !unavailable {
                Stepper(
                    value: Binding(
                        get: { day?.targetDistanceMeters ?? 0 },
                        set: { weekLoader.setDistance(date, meters: $0) }
                    ),
                    in: 0...WeekPlanEditor.maxDistanceMeters,
                    step: 100
                ) {
                    Text("Umfang: \(PlanFormatting.meters(day?.targetDistanceMeters ?? 0))")
                }
            }
            if unavailable {
                Button("Doch wieder Zeit") { weekLoader.clearUnavailable(date) }
            } else {
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
            Text("Anpassen")
        } footer: {
            Text(date == weekLoader.todayKey
                 ? "Die Einheit selbst steht im Tab Heute. Nach einer Änderung dort \"Plan neu erstellen\" tippen, damit sie zur neuen Vorgabe passt."
                 : "Nach Änderungen kannst du im Wochen-Tab den Rest der Woche neu planen lassen.")
        }
    }

    @ViewBuilder
    private var swapMenu: some View {
        let others = editableDates.filter { other in
            other != date && weekLoader.selectedWeek?.day(on: other)?.isUnavailable != true
        }
        if !others.isEmpty {
            Menu("Mit anderem Tag tauschen") {
                ForEach(others, id: \.self) { other in
                    Button("\(weekCalendar.weekdayName(other)), \(PlanFormatting.shortGermanDate(other)): \(PlanFormatting.daySummary(weekLoader.selectedWeek?.day(on: other)))") {
                        weekLoader.swapDays(date, other)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: Nachholen (vergangene Tage)

    @ViewBuilder
    private func catchUpSection(_ status: WeekDayStatus) -> some View {
        if let day = status.plan, !day.isRestDay, status.state == .missed || status.state == .shorter {
            let restDays = editableDates.filter { other in
                guard let candidate = weekLoader.selectedWeek?.day(on: other) else { return false }
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
                Text("Das Verpasste landet auf dem gewählten Ruhetag. Wer lieber neu planen will, nutzt im Wochen-Tab \"Rest der Woche neu planen\": Claude berücksichtigt, was du schon geschwommen hast.")
            }
        }
    }
}

// MARK: - Gesamtplan

/// Der Gesamtplan auf einen Blick: Ziel, Stand, aktuelle Woche und alle Wochen bis zum Zieltag.
private struct MacroSummary: View {
    let plan: MacroPlan
    let currentWeek: MacroWeek?
    let weeksLeft: Int
    let currentWeekStart: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ziel am \(PlanFormatting.germanDate(plan.goalDay)), noch \(weeksLeft) Wochen")
                .font(.headline)
            if let currentWeek {
                Text("Diese Woche: \(PlanFormatting.macroPhase(currentWeek.phase)), etwa \(PlanFormatting.meters(currentWeek.targetMeters)) in \(currentWeek.sessions) Einheiten\(currentWeek.deload ? " (Entlastung)" : "")")
                    .font(.subheadline)
                if !currentWeek.focus.isEmpty {
                    Text(currentWeek.focus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Höhepunkt: \(PlanFormatting.meters(plan.peakMeters)) pro Woche")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(plan.rationale)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        DisclosureGroup("Alle Wochen (\(plan.weeks.count))") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.weeks) { week in
                    MacroWeekRow(week: week, isCurrent: week.weekStart == currentWeekStart)
                }
            }
            .padding(.top, 4)
        }
        if !plan.adjustments.isEmpty {
            DisclosureGroup("Zur Sicherheit angepasst (\(plan.adjustments.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.adjustments, id: \.self) { adjustment in
                        Text(adjustment)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private struct MacroWeekRow: View {
    let week: MacroWeek
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(PlanFormatting.shortGermanDate(week.weekStart))
                .font(.caption.monospacedDigit().weight(isCurrent ? .bold : .regular))
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(PlanFormatting.macroPhase(week.phase)) · \(PlanFormatting.meters(week.targetMeters))\(week.deload ? " · Entlastung" : "")")
                    .font(.caption.weight(isCurrent ? .bold : .regular))
                if !week.focus.isEmpty {
                    Text(week.focus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
    }
}
