import Charts
import SwiftUI
import SwimInstructorCore

/// Bin ich auf Kurs zum Ziel? Die Karte oben in "Aktuell" und der Bildschirm "Weg zum Ziel" dahinter. Beide rechnen mit
/// `GoalCourseEvaluator`, wie die Wochenbilanz als Mitteilung.
@MainActor
enum GoalCourseSource {
    /// Der Stand aus Gesamtplan und Health; `nil` ohne aktuellen Gesamtplan oder solange Health noch nicht gelesen ist.
    static func course(macroLoader: MultiSportMacroLoader, todayLoader: MultiSportTodayLoader, now: Date = Date()) -> GoalCourse? {
        guard let plan = macroLoader.plan, macroLoader.isCurrent, let reading = todayLoader.reading else { return nil }
        let calendar = Calendar.current
        let historyStart = calendar.date(byAdding: .day, value: -(SnapshotBuilder.workoutWindowDays - 1), to: calendar.startOfDay(for: now))
        return GoalCourseEvaluator(calendar: calendar).evaluate(
            plan: plan,
            workouts: reading.allWorkouts,
            now: now,
            pause: UserDefaultsPauseReportStore().report(),
            historyStart: historyStart
        )
    }

    /// Die letzte Fortschreibung mit Rat des Coaches, wenn sie höchstens vier Wochen her ist.
    static func adviceReview(of plan: MacroPlanV2, now: Date = Date()) -> MacroReview? {
        guard let review = plan.reviews.last,
              let advice = review.advice, !advice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              now.timeIntervalSince(review.reviewedAt) <= 28 * 86_400 else { return nil }
        return review
    }

    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLocale.current))
    }

    static func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.locale(AppLocale.current))
    }
}

// MARK: - Karte in "Aktuell"

/// Oben in "Aktuell": Ampel, ein Satz zum Stand, der Rat des Coaches, je Sportart Plan gegen Ist und die letzte
/// Änderung mit Grund. Antippen öffnet "Weg zum Ziel".
struct GoalCourseSection: View {
    @EnvironmentObject private var macroLoader: MultiSportMacroLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader

    var body: some View {
        if let plan = macroLoader.plan, let course = GoalCourseSource.course(macroLoader: macroLoader, todayLoader: todayLoader) {
            Section {
                NavigationLink {
                    GoalCourseView()
                } label: {
                    GoalCourseHeader(course: course, plan: plan, weeksUntilGoal: macroLoader.weeksUntilGoal, isOpenEnded: macroLoader.isOpenEnded)
                }
                if !course.sports.isEmpty {
                    GoalCourseSportRows(course: course)
                }
                if let review = plan.reviews.last, let change = review.changes.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Was sich zuletzt geändert hat")
                            .font(.subheadline.weight(.semibold))
                        Text(change)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: "\(review.reason.title), \(GoalCourseSource.date(review.reviewedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Auf Kurs zum Ziel?")
            }
        }
    }
}

/// Ampel mit Ziel, Satz zum Stand und Rat des Coaches.
struct GoalCourseHeader: View {
    let course: GoalCourse
    let plan: MacroPlanV2
    let weeksUntilGoal: Int
    let isOpenEnded: Bool

    @AppStorage(Theme.greenWeakKey) private var greenWeak = false

    private var symbol: String {
        switch course.status {
        case .onTrack: return "checkmark.circle.fill"
        case .trainMore: return "arrow.up.circle.fill"
        case .trainLess: return "arrow.down.circle.fill"
        case .noData: return "hourglass.circle.fill"
        }
    }

    private var color: Color {
        switch course.status {
        case .onTrack: return Theme.done(greenWeak: greenWeak)
        case .trainMore, .trainLess: return Theme.caution(greenWeak: greenWeak)
        case .noData: return .secondary
        }
    }

    private var goalLine: String {
        if isOpenEnded { return String(localized: "Fit werden und bleiben") }
        switch weeksUntilGoal {
        case 0: return String(localized: "Dein Zieltag ist da")
        case 1: return String(localized: "Noch 1 Woche bis zum Ziel")
        default: return String(localized: "Noch \(weeksUntilGoal) Wochen bis zum Ziel")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goalLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(course.status.title)
                        .font(.title3.weight(.bold))
                }
            }
            Text(course.sentence())
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let review = GoalCourseSource.adviceReview(of: plan), let advice = review.advice {
                VStack(alignment: .leading, spacing: 2) {
                    Text(advice)
                        .font(.subheadline)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Dein Coach, Fortschreibung vom \(GoalCourseSource.date(review.reviewedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 4)
    }
}

/// Je Sportart: trainiert von geplant in den bewerteten Wochen, mit Balken bis 120 % und Strich bei 100 %.
struct GoalCourseSportRows: View {
    let course: GoalCourse

    @AppStorage(Theme.greenWeakKey) private var greenWeak = false
    private let registry = SportRegistry.standard
    /// Der Balken reicht bis 120 %, der Strich steht bei 100 %.
    private let scale = Double(GoalCourseEvaluator.tooMuchPercent)

    private var periodTitle: String {
        course.weekStarts.count == 1
            ? String(localized: "Letzte Woche: trainiert von geplant")
            : String(localized: "Letzte \(course.weekStarts.count) Wochen: trainiert von geplant")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(periodTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(course.sports) { sport in
                row(sport)
            }
            Text("Der Strich markiert den Plan. Etwas darüber ist in Ordnung.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func row(_ sport: GoalCourse.SportCourse) -> some View {
        let percent = sport.percent ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(registry.displayName(for: sport.sport))
                Spacer()
                Text(GoalCourseSource.percent(percent))
                    .fontWeight(.semibold)
                    .foregroundStyle(percentColor(percent))
            }
            .font(.subheadline)
            CourseBar(fraction: min(Double(percent) / scale, 1), marker: 100 / scale, color: Theme.sport(sport.sport, greenWeak: greenWeak))
            Text("\(PlanV2Formatting.amount(sport.done, unit: sport.unit)) von \(PlanV2Formatting.amount(sport.planned, unit: sport.unit))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func percentColor(_ percent: Int) -> Color {
        if percent < GoalCourseEvaluator.onTrackPercent || percent > GoalCourseEvaluator.tooMuchPercent {
            return Theme.caution(greenWeak: greenWeak)
        }
        return Theme.done(greenWeak: greenWeak)
    }
}

private struct CourseBar: View {
    let fraction: Double
    let marker: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(geometry.size.width * fraction, 0))
                Rectangle()
                    .fill(Color.secondary)
                    .frame(width: 2, height: 14)
                    .offset(x: geometry.size.width * marker - 1)
            }
        }
        .frame(height: 8)
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Weg zum Ziel

/// Der Bildschirm hinter der Karte: Linie geplant gegen trainiert bis zum Zieltag, Zahlen, Rat des Coaches, je Sportart
/// und alle Anpassungen mit Grund.
struct GoalCourseView: View {
    @EnvironmentObject private var macroLoader: MultiSportMacroLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader

    var body: some View {
        List {
            if let plan = macroLoader.plan, let course = GoalCourseSource.course(macroLoader: macroLoader, todayLoader: todayLoader) {
                Section {
                    GoalCourseHeader(course: course, plan: plan, weeksUntilGoal: macroLoader.weeksUntilGoal, isOpenEnded: macroLoader.isOpenEnded)
                }
                .cardRows()
                chartSection(course)
                    .cardRows()
                numbersSection(course)
                    .cardRows()
                if !course.sports.isEmpty {
                    Section {
                        GoalCourseSportRows(course: course)
                    }
                    .cardRows()
                }
                if let review = plan.reviews.last {
                    coachSection(review)
                        .cardRows()
                }
                historySection(plan)
                    .cardRows()
            } else {
                Text("Sobald es einen Gesamtplan gibt und Health gelesen ist, siehst du hier, ob du auf Kurs bist.")
                    .foregroundStyle(.secondary)
                    .cardRows()
            }
        }
        .themedList()
        .navigationTitle("Weg zum Ziel")
    }

    private func chartSection(_ course: GoalCourse) -> some View {
        Section {
            GoalCourseChart(course: course)
                .frame(height: 200)
                .padding(.vertical, 4)
            HStack(spacing: 16) {
                legend(Text("Trainiert"), dashed: false, color: Theme.accent)
                legend(Text("Geplant"), dashed: true, color: .secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("Belastung je Woche")
        } footer: {
            Text("Minuten je Woche bis zum Zieltag. Die trainierte Linie endet in der laufenden Woche.")
        }
    }

    private func legend(_ label: Text, dashed: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.5))
                path.addLine(to: CGPoint(x: 16, y: 1.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, dash: dashed ? [4, 3] : []))
            .frame(width: 16, height: 3)
            label
        }
    }

    private func numbersSection(_ course: GoalCourse) -> some View {
        Section {
            if let percent = course.percent {
                LabeledContent("Umfang") {
                    Text(GoalCourseSource.percent(percent))
                }
                LabeledContent("Einheiten") {
                    Text(verbatim: "\(course.doneSessions) / \(course.plannedSessions)")
                }
            }
            if !macroLoader.isOpenEnded {
                LabeledContent("Bis zum Ziel") {
                    Text(PlanFormatting.shortGermanDate(macroLoader.plan?.goalDay ?? ""))
                }
            }
        } footer: {
            Text("Auf Kurs heißt: in den letzten abgeschlossenen Wochen (bis zu 4) mindestens 80 % vom Plan und keine Sportart unter 60 %. Über 120 % ist mehr als geplant. Die Woche, in der der Plan entstand, und Wochen mit gemeldeter Pause zählen nicht.")
        }
    }

    private func coachSection(_ review: MacroReview) -> some View {
        Section {
            if let advice = review.advice, !advice.isEmpty {
                Text(advice)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !review.summary.isEmpty {
                Text(review.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Was dein Coach rät")
        } footer: {
            Text("Fortschreibung vom \(GoalCourseSource.date(review.reviewedAt)). Dein Coach schreibt den Plan alle zwei Wochen fort.")
        }
    }

    /// Alle Anpassungen, neueste zuerst: Fortschreibungen mit Anlass und Feedback-Runden.
    private func historySection(_ plan: MacroPlanV2) -> some View {
        let entries = (plan.reviews.map { review in
            HistoryEntry(date: review.reviewedAt, title: review.reason.title, changes: review.changes)
        } + plan.feedbackRounds.map { round in
            HistoryEntry(date: round.revisedAt, title: String(localized: "Nach deinem Feedback"), changes: round.changes)
        }).sorted { $0.date > $1.date }

        return Section {
            if entries.isEmpty {
                Text("Noch keine Anpassung. Dein Coach schreibt den Plan alle zwei Wochen fort, nach einer gemeldeten Pause sofort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(GoalCourseSource.date(entry.date)) · \(entry.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(entry.changes, id: \.self) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "•")
                            Text(change)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.footnote)
                    }
                }
                .accessibilityElement(children: .combine)
                .padding(.vertical, 2)
            }
        } header: {
            Text("Anpassungen und warum")
        }
    }

    private struct HistoryEntry: Identifiable {
        let date: Date
        let title: String
        let changes: [String]

        var id: String { "\(date.timeIntervalSince1970)|\(title)" }
    }
}

/// Geplante Minuten je Woche (gestrichelt, mit Fläche) bis zum Zieltag, trainierte bis zur laufenden Woche, dazu
/// eine Markierung "heute".
private struct GoalCourseChart: View {
    let course: GoalCourse

    private let weekCalendar = WeekCalendar()

    private struct Point: Identifiable {
        let date: Date
        let planned: Double
        let done: Double?
        let isCurrent: Bool

        var id: Date { date }
    }

    private var points: [Point] {
        course.weeks.compactMap { week in
            weekCalendar.date(from: week.weekStart).map { date in
                Point(date: date, planned: week.plannedMinutes, done: week.doneMinutes, isCurrent: week.isCurrent)
            }
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Woche", point.date), y: .value("Minuten", point.planned))
                    .foregroundStyle(Theme.track.opacity(0.6))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Woche", point.date), y: .value("Minuten", point.planned), series: .value("Geplant", "planned"))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }
            ForEach(points.filter { $0.done != nil }) { point in
                LineMark(x: .value("Woche", point.date), y: .value("Minuten", point.done ?? 0), series: .value("Trainiert", "done"))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                if point.isCurrent {
                    PointMark(x: .value("Woche", point.date), y: .value("Minuten", point.done ?? 0))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(80)
                    RuleMark(x: .value("Woche", point.date))
                        .foregroundStyle(Theme.accent.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle(locale: AppLocale.current).month(.abbreviated))
            }
        }
        .accessibilityLabel(Text("Geplante und trainierte Minuten je Woche bis zum Zieltag"))
    }
}
