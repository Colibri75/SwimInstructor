import Foundation

/// Health führt dieselbe Einheit mitunter doppelt, wenn mehrere Quellen sie schreiben (z. B.
/// Apple Watch plus eine Drittanbieter-App). Ohne Bereinigung würden Volumen und Sitzungszahl
/// doppelt zählen. Zwei Workouts gelten als Duplikat, wenn sich ihre Zeitfenster zu mindestens
/// der Hälfte des kürzeren überlappen - dann bleibt das vollständigere.
public enum SwimWorkoutDeduplicator {
    static let minimumOverlapRatio = 0.5

    public static func deduplicate(_ workouts: [SwimWorkout]) -> [SwimWorkout] {
        var result: [SwimWorkout] = []
        for workout in workouts.sorted(by: { $0.startDate < $1.startDate }) {
            if let index = result.firstIndex(where: { overlapsSignificantly($0, workout) }) {
                if completeness(of: workout) > completeness(of: result[index]) {
                    result[index] = workout
                }
            } else {
                result.append(workout)
            }
        }
        return result
    }

    static func overlapsSignificantly(_ first: SwimWorkout, _ second: SwimWorkout) -> Bool {
        let overlapStart = max(first.startDate, second.startDate)
        let overlapEnd = min(first.endDate, second.endDate)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        guard overlap > 0 else { return false }

        let shorter = min(
            first.endDate.timeIntervalSince(first.startDate),
            second.endDate.timeIntervalSince(second.startDate)
        )
        guard shorter > 0 else { return false }
        return overlap / shorter >= minimumOverlapRatio
    }

    /// Je mehr Messwerte ein Workout mitbringt, desto eher bleibt es bestehen. Die Distanz
    /// wiegt am schwersten, weil Pace und Volumen daran hängen.
    static func completeness(of workout: SwimWorkout) -> Int {
        var score = 0
        if let distance = workout.totalDistanceMeters, distance > 0 { score += 8 }
        if workout.lapCount != nil { score += 4 }
        if workout.totalStrokeCount != nil { score += 2 }
        if workout.averageHeartRate != nil { score += 1 }
        return score
    }
}
