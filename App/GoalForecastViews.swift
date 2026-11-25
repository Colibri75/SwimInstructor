import SwiftUI
import SwimInstructorCore

/// Zielprognose (Variante C): welche Zeit heute über die Strecken des Ziels drin wäre, je Disziplin gegen die
/// Zielzeit. Steht im Dashboard (Bereich "goal"), in "Weg zum Ziel" und als eine Zeile auf der Karte in "Aktuell".
@MainActor
enum GoalForecastSource {
    static func forecast(profileLoader: PerformanceProfileLoader, todayLoader: MultiSportTodayLoader, now: Date = Date()) -> GoalForecast? {
        GoalForecaster().forecast(
            goal: UserDefaultsTrainingGoalStore().goal(),
            value: { sport, metric in profileLoader.current(metric, sport: sport)?.value },
            startingLevels: UserDefaultsStartingLevelStore().levels(),
            workouts: todayLoader.reading?.allWorkouts ?? [],
            now: now
        )
    }
}

/// Eine Zeile für die Karte in "Aktuell": "Prognose heute 2:51:30 · Ziel 2:45:00".
struct GoalForecastLine: View {
    @EnvironmentObject private var profileLoader: PerformanceProfileLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader

    var body: some View {
        if let forecast = GoalForecastSource.forecast(profileLoader: profileLoader, todayLoader: todayLoader),
           let predicted = forecast.predictedTotal {
            HStack(alignment: .firstTextBaseline) {
                Text("Prognose heute")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: GoalForecast.clock(predicted))
                    .fontWeight(.semibold)
                if let target = forecast.targetTotal {
                    Text("Ziel \(GoalForecast.clock(target))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Der Bereich "Zielprognose": Gesamtzeit gegen Zielzeit, je Disziplin Prognose, Abstand und Grundlage.
struct GoalForecastSection: View {
    /// Im Dashboard: mit Link auf "Weg zum Ziel".
    var showsLink = false

    @EnvironmentObject private var profileLoader: PerformanceProfileLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @AppStorage(Theme.greenWeakKey) private var greenWeak = false

    private let registry = SportRegistry.standard

    var body: some View {
        if let forecast = GoalForecastSource.forecast(profileLoader: profileLoader, todayLoader: todayLoader) {
            Section {
                totals(forecast)
                ForEach(forecast.disciplines) { discipline in
                    row(discipline)
                }
                if let transitions = forecast.transitionSeconds, forecast.predictedTotal != nil {
                    LabeledContent("Wechsel (geschätzt)") {
                        Text(verbatim: GoalForecast.gap(transitions))
                    }
                    .font(.subheadline)
                }
                Text(forecast.sentence())
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if showsLink {
                    NavigationLink("Weg zum Ziel") {
                        GoalCourseView()
                    }
                }
            } header: {
                Text("Zielprognose")
            } footer: {
                Text("Eine grobe Schätzung aus deinem Leistungsprofil, deinem Startniveau und deinen Radfahrten in Health, so wie du heute in Form bist. Nach jedem Test wird sie genauer.")
            }
        } else if showsLink {
            Section("Zielprognose") {
                Text("Für ein Fitnessziel ohne Strecke gibt es keine Zielprognose.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink("Weg zum Ziel") {
                    GoalCourseView()
                }
            }
        }
    }

    @ViewBuilder
    private func totals(_ forecast: GoalForecast) -> some View {
        if let predicted = forecast.predictedTotal {
            VStack(alignment: .leading, spacing: 4) {
                if let target = forecast.targetTotal {
                    Text("Zielzeit \(GoalForecast.clock(target))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Prognose heute")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: GoalForecast.clock(predicted))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                if let gap = forecast.totalGap {
                    Text(gap <= 0 ? String(localized: "Schneller als deine Zielzeit") : String(localized: "Noch \(GoalForecast.gap(gap)) bis zur Zielzeit"))
                        .font(.caption)
                        .foregroundStyle(gap <= 0 ? Theme.done(greenWeak: greenWeak) : Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.vertical, 4)
        }
    }

    private func row(_ discipline: GoalForecast.Discipline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(registry.displayName(for: discipline.sport)) \(PlanFormatting.distance(discipline.distanceMeters))")
                Spacer()
                if let predicted = discipline.predictedSeconds {
                    Text(verbatim: GoalForecast.clock(predicted))
                        .fontWeight(.semibold)
                } else {
                    Text("Noch offen")
                        .foregroundStyle(.secondary)
                }
                if let target = discipline.targetSeconds {
                    Text("Ziel \(GoalForecast.clock(target))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            if let percent = discipline.progressPercent {
                ForecastBar(fraction: Double(percent) / 100, color: Theme.sport(discipline.sport, greenWeak: greenWeak))
            }
            if let verdict = discipline.verdict {
                Text(verdict)
                    .font(.caption)
                    .foregroundStyle(verdictColor(discipline))
            }
            Text(discipline.basis?.text ?? String(localized: "Es fehlt ein Leistungswert. Trag ihn im Leistungsprofil ein oder mach einen Test."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 2)
    }

    private func verdictColor(_ discipline: GoalForecast.Discipline) -> Color {
        guard let gap = discipline.gapSeconds, let target = discipline.targetSeconds else { return .secondary }
        if gap <= target * GoalForecaster.almostThereShare { return Theme.done(greenWeak: greenWeak) }
        return Theme.caution(greenWeak: greenWeak)
    }
}

private struct ForecastBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(geometry.size.width * min(fraction, 1), 0))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// "Mehr oder weniger trainieren?": die Ampel als Wahl Weniger / So bleiben / Mehr, mit dem Satz dazu und dem Hinweis,
/// wo die meiste Zeit liegt.
struct GoalCourseAdviceSection: View {
    let course: GoalCourse

    @EnvironmentObject private var profileLoader: PerformanceProfileLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader

    private enum Choice: CaseIterable {
        case less, keep, more
    }

    private var selected: Choice? {
        switch course.status {
        case .trainLess: return .less
        case .onTrack: return .keep
        case .trainMore: return .more
        case .noData: return nil
        }
    }

    var body: some View {
        if let selected {
            Section {
                HStack(spacing: 8) {
                    chip(Text("Weniger"), isOn: selected == .less)
                    chip(Text("So bleiben"), isOn: selected == .keep)
                    chip(Text("Mehr"), isOn: selected == .more)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(course.status.title))
                Text(course.sentence())
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let largest = GoalForecastSource.forecast(profileLoader: profileLoader, todayLoader: todayLoader)?.largestGap {
                    Text("Am meisten Zeit holst du beim \(SportRegistry.standard.displayName(for: largest.sport)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Mehr oder weniger trainieren?")
            }
        }
    }

    private func chip(_ label: Text, isOn: Bool) -> some View {
        label
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(isOn ? Theme.action : Theme.track))
            .foregroundStyle(isOn ? Theme.onAction : Color.secondary)
    }
}
