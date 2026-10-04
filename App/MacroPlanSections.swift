import Charts
import SwiftUI
import SwimInstructorCore

/// Der Gesamtplan bis zum Ziel im Plan-Tab: Überblick je Sportart, alle Wochen, Testtermine und darunter das Feedback mit
/// der Liste der Änderungen und dem Verlauf der Runden.
struct MacroPlanSections: View {
    @EnvironmentObject private var macroLoader: MultiSportMacroLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @EnvironmentObject private var settings: BackendSettings

    @State private var feedback = ""
    /// Der letzte Fehler kam aus dem Feedback (nicht aus dem Neuberechnen): Er steht dann beim Feedback-Feld.
    @State private var errorFromFeedback = false

    var body: some View {
        overviewSection
        if let plan = macroLoader.plan {
            feedbackSection(plan)
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
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Noch kein Gesamtplan. Er legt die Wochen bis zu deinem Ziel für alle Sportarten fest, die nächsten sieben Tage richten sich danach.")
                    .foregroundStyle(.secondary)
            }
            Button {
                guard let snapshot = todayLoader.reading?.snapshot else { return }
                errorFromFeedback = false
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
            .disabled(macroLoader.isLoading || macroLoader.isRevising || todayLoader.reading == nil || !settings.hasToken)
            if let error = macroLoader.error, !errorFromFeedback {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Gesamtplan bis zum Ziel")
        } footer: {
            Text("Der Gesamtplan entsteht beim Start und bei einer Zieländerung. Neu berechnen beginnt von vorn und verwirft die Feedback-Runden; für einzelne Wünsche ist das Feedback darunter gedacht.")
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
                        // Die nächsten sieben Tage an den neuen Gesamtplan anpassen (einmal je Fassung).
                        await todayLoader.refreshIfNeeded()
                    }
                }
            } label: {
                if macroLoader.isRevising {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Claude überarbeitet den Gesamtplan …")
                    }
                } else {
                    Text("Gesamtplan anpassen")
                }
            }
            .disabled(
                feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || macroLoader.isRevising || macroLoader.isLoading || todayLoader.reading == nil || !settings.hasToken
            )
            if let error = macroLoader.error, errorFromFeedback {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
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
            Text("Schreib, was am Gesamtplan anders sein soll. Claude überarbeitet ihn und listet, was sich ändert; die Sicherheitsgrenzen gelten weiter. Die nächsten sieben Tage passen sich danach an. Jede Runde ist ein größerer Claude-Aufruf.")
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
                Text("Claude hat nichts geändert.")
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

/// Der Gesamtplan auf einen Blick: Ziel, laufende Woche je Sportart, Wochenstunden je Sportart bis zum Zieltag, alle
/// Wochen und Testtermine.
private struct MacroOverview: View {
    let plan: MacroPlanV2
    let currentWeek: MacroWeekV2?
    let weeksLeft: Int
    let currentWeekStart: String

    private let registry = SportRegistry.standard

    var body: some View {
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
        DisclosureGroup("Alle Wochen (\(plan.weeks.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.weeks) { week in
                    MacroWeekRow(week: week, isCurrent: week.weekStart == currentWeekStart)
                }
            }
            .padding(.top, 4)
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(PlanFormatting.shortGermanDate(week.weekStart))
                .font(.caption.monospacedDigit().weight(isCurrent ? .bold : .regular))
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(PlanFormatting.macroPhase(week.phase)) · \(PlanV2Formatting.duration(minutes: week.totalMinutes))\(week.deload ? " · Entlastung" : "")")
                    .font(.caption.weight(isCurrent ? .bold : .regular))
                Text(week.sports.map { "\(registry.displayName(for: $0.sport)) \(PlanV2Formatting.amount($0.amount, unit: $0.unit))" }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !week.tests.isEmpty {
                    Text("Test: \(week.tests.map(\.displayName).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
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
