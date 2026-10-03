import Foundation

/// Wie `SwimWorkoutDeduplicator`, für alle Sportarten: Überlappen sich zwei Einheiten derselben Sportart zu
/// mindestens der Hälfte der kürzeren, bleibt die vollständigere. Einheiten verschiedener Sportarten bleiben
/// immer beide stehen (ein Koppeltraining Rad und Lauf kann sich am Wechsel überschneiden).
public enum WorkoutDeduplicator {
    public static func deduplicate(_ workouts: [Workout]) -> [Workout] {
        var result: [Workout] = []
        for workout in workouts.sorted(by: { $0.startDate < $1.startDate }) {
            if let index = result.firstIndex(where: { $0.sport == workout.sport && overlapsSignificantly($0, workout) }) {
                if completeness(of: workout) > completeness(of: result[index]) {
                    result[index] = workout
                }
            } else {
                result.append(workout)
            }
        }
        return result
    }

    static func overlapsSignificantly(_ first: Workout, _ second: Workout) -> Bool {
        let overlap = min(first.endDate, second.endDate).timeIntervalSince(max(first.startDate, second.startDate))
        let shorter = min(first.endDate.timeIntervalSince(first.startDate), second.endDate.timeIntervalSince(second.startDate))
        guard overlap > 0, shorter > 0 else { return false }
        return overlap / shorter >= SwimWorkoutDeduplicator.minimumOverlapRatio
    }

    /// Die Strecke wiegt am schwersten, dann die sportartspezifischen Werte, dann Puls und Energie.
    static func completeness(of workout: Workout) -> Int {
        var score = 0
        if let distance = workout.distanceMeters, distance > 0 { score += 8 }
        score += 2 * workout.metrics.count
        if workout.averageHeartRate != nil { score += 1 }
        if workout.activeEnergyKilocalories != nil { score += 1 }
        return score
    }
}
