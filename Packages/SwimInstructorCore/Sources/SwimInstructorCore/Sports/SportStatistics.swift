import Foundation

/// Die Kennzahlen der Statistik je Sportart: abgeleitet für Module ohne eigene Liste und die Prüfung der Registry.
public enum SportStatistics {
    /// Kennzahlen aus dem, was die Sportart aus Health liest: mit Strecke Umfang (in Metern, wenn der Plan in Metern
    /// rechnet, sonst in km), Zeit, Einheiten, mit Strecke Tempo, Puls, jeder Zusatzwert mit eigener Kennzahl (Watt,
    /// Trittfrequenz, Höhenmeter), die längste Einheit und die Trainingslast. So bekommt eine neue Sportart ohne eigene
    /// Liste trotzdem Kacheln.
    public static func derived(for module: any SportModule) -> [StatisticDefinition] {
        let hasDistance = module.health.distance != nil
        let inMeters = module.planUnit == .meters
        var list: [StatisticDefinition] = []
        if hasDistance {
            list.append(inMeters ? .distanceMeters : .distanceKilometers)
        }
        list.append(contentsOf: [StatisticDefinition.duration, .sessions])
        if hasDistance {
            list.append(.speed)
        }
        list.append(.averageHeartRate)
        list.append(contentsOf: module.health.metrics.keys
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap(StatisticDefinition.forWorkoutMetric))
        if hasDistance {
            list.append(inMeters ? .longestDistanceMeters : .longestDistanceKilometers)
        } else {
            list.append(.longestDuration)
        }
        list.append(.trainingLoad)
        return list
    }

    /// Mindestens eine Kennzahl, jede mit gültiger Kennung, Namen und nur einmal, und jede rechnet aus den Einheiten.
    static func isValid(_ statistics: [StatisticDefinition]) -> Bool {
        var seen = Set<StatisticMetric>()
        return !statistics.isEmpty && statistics.allSatisfy {
            SportID(rawValue: $0.metric.rawValue).isWellFormed
                && !$0.displayName.trimmingCharacters(in: .whitespaces).isEmpty
                && $0.measure.usesWorkouts
                && seen.insert($0.metric).inserted
        }
    }
}
