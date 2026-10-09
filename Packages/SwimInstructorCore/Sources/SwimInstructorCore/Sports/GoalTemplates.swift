import Foundation

/// Vorlagen für typische Ziele. Sie füllen Disziplinen, Strecken und Schwerpunkte vor; danach ist alles frei änderbar.
public struct GoalTemplate: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let disciplines: [TrainingGoal.Discipline]
    public let emphasis: [TrainingGoal.Emphasis]

    public init(id: String, displayName: String, disciplines: [TrainingGoal.Discipline], emphasis: [TrainingGoal.Emphasis]) {
        self.id = id
        self.displayName = displayName
        self.disciplines = disciplines
        self.emphasis = emphasis
    }

    /// Ein Ziel nach dieser Vorlage; Zielzeiten trägt der Athlet selbst ein.
    public func goal(targetDate: Date, trainingDaysPerWeek: Int, weeklyHours: Double) -> TrainingGoal {
        TrainingGoal(
            template: id,
            disciplines: disciplines,
            targetDate: targetDate,
            trainingDaysPerWeek: trainingDaysPerWeek,
            weeklyHours: weeklyHours,
            emphasis: emphasis
        )
    }

    public static func template(id: String?) -> GoalTemplate? {
        all.first { $0.id == id }
    }

    /// Triathlon-Schwerpunkte nach üblicher Zeitverteilung: Rad am meisten, Schwimmen am wenigsten.
    private static let triathlonEmphasis = [
        TrainingGoal.Emphasis(sport: .swim, percent: 25),
        TrainingGoal.Emphasis(sport: .bike, percent: 45),
        TrainingGoal.Emphasis(sport: .run, percent: 30)
    ]

    private static func triathlon(_ id: String, _ name: String, swim: Double, bike: Double, run: Double) -> GoalTemplate {
        GoalTemplate(
            id: id,
            displayName: name,
            disciplines: [
                .init(sport: .swim, distanceMeters: swim),
                .init(sport: .bike, distanceMeters: bike),
                .init(sport: .run, distanceMeters: run)
            ],
            emphasis: triathlonEmphasis
        )
    }

    private static func single(_ id: String, _ name: String, sport: SportID, meters: Double) -> GoalTemplate {
        GoalTemplate(
            id: id,
            displayName: name,
            disciplines: [.init(sport: sport, distanceMeters: meters)],
            emphasis: [.init(sport: sport, percent: 100)]
        )
    }

    public static let all: [GoalTemplate] = [
        triathlon("triathlon_sprint", String(localized: "Triathlon Sprint"), swim: 750, bike: 20_000, run: 5_000),
        triathlon("triathlon_olympic", String(localized: "Triathlon Olympisch"), swim: 1_500, bike: 40_000, run: 10_000),
        triathlon("triathlon_half", String(localized: "Triathlon Mitteldistanz (70.3)"), swim: 1_900, bike: 90_000, run: 21_100),
        triathlon("triathlon_full", String(localized: "Triathlon Langdistanz"), swim: 3_800, bike: 180_000, run: 42_195),
        single("swim_long", String(localized: "Schwimmen 3,8 km"), sport: .swim, meters: 3_800),
        single("run_10k", String(localized: "Lauf 10 km"), sport: .run, meters: 10_000),
        single("run_half_marathon", String(localized: "Halbmarathon"), sport: .run, meters: 21_097.5),
        single("run_marathon", String(localized: "Marathon"), sport: .run, meters: 42_195),
        single("bike_century", String(localized: "Radfahren 100 km"), sport: .bike, meters: 100_000)
    ]
}
