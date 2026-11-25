import Foundation

/// Die Faustformeln der Zielprognose je Sportart. Liegt unter `Sports/`, weil nur hier nach Sportarten verzweigt werden
/// darf (`SportLintTests`).
extension GoalForecaster {
    /// Prognose und Grundlage für eine Disziplin; `before` sind die Disziplinen davor im selben Wettkampf.
    func estimate(
        _ discipline: TrainingGoal.Discipline,
        before: [TrainingGoal.Discipline],
        isMultisport: Bool,
        value: (SportID, PerformanceMetric) -> Double?,
        level: StartingLevel?,
        workouts: [Workout],
        now: Date
    ) -> (Double, GoalForecast.Basis)? {
        if discipline.sport == .swim {
            return swim(discipline, css: value(.swim, "css_pace_per_100m"), level: level)
        }
        if discipline.sport == .bike {
            return bike(discipline, workouts: workouts, now: now, level: level)
        }
        if discipline.sport == .run {
            let afterBike = isMultisport && before.contains { $0.sport == .bike }
            return run(discipline, threshold: value(.run, "threshold_pace_per_km"), level: level, afterBike: afterBike)
        }
        // Weitere Sportarten bekommen ihre Prognose, sobald es eine Faustformel dafür gibt.
        return nil
    }

    // MARK: - Schwimmen

    /// Wettkampftempo = CSS plus Aufschlag je Strecke (kurz etwas schneller als CSS, lang langsamer); im Freiwasser
    /// 2 s/100 m mehr fürs Orientieren.
    fileprivate func swim(_ discipline: TrainingGoal.Discipline, css: Double?, level: StartingLevel?) -> (Double, GoalForecast.Basis)? {
        let meters = discipline.distanceMeters
        let offset: Double = meters <= 800 ? -1 : meters <= 1600 ? 2 : meters <= 2000 ? 3 : 5
        let openWater: Double = discipline.openWater ? 2 : 0
        if let css, css > 0 {
            return (meters / 100 * (css + offset + openWater), .criticalSwimSpeed(css))
        }
        if let pace = level?.pace, pace > 0 {
            // Übliches Trainingstempo liegt etwa 4 s/100 m über CSS.
            return (meters / 100 * (pace - 4 + offset + openWater), .swimPace(pace))
        }
        return nil
    }

    // MARK: - Rad

    /// Wettkampftempo = Schnitt der zwei schnellsten Fahrten ab 45 Minuten der letzten 8 Wochen, im Wettkampf je nach
    /// Strecke 0 bis 8 % schneller als im Training.
    fileprivate func bike(_ discipline: TrainingGoal.Discipline, workouts: [Workout], now: Date, level: StartingLevel?) -> (Double, GoalForecast.Basis)? {
        let kilometers = discipline.distanceMeters / 1000
        let raceFactor = kilometers <= 25 ? 1.08 : kilometers <= 45 ? 1.06 : kilometers <= 100 ? 1.03 : 1.0
        let start = calendar.date(byAdding: .day, value: -Self.rideWindowDays, to: now) ?? now
        let speeds = WorkoutDeduplicator.deduplicate(workouts)
            .filter { $0.sport == .bike && $0.startDate >= start && $0.duration >= Self.minimumRideMinutes * 60 }
            .compactMap { workout -> Double? in
                guard let meters = workout.distanceMeters, meters > 0 else { return nil }
                return meters / 1000 / (workout.duration / 3600)
            }
            .filter { (10...60).contains($0) }
            .sorted(by: >)
        if !speeds.isEmpty {
            let top = speeds.prefix(2)
            let speed = top.reduce(0, +) / Double(top.count)
            return (kilometers / (speed * raceFactor) * 3600, .recentRides(speed))
        }
        if let speed = level?.pace, speed > 0 {
            return (kilometers / (speed * raceFactor) * 3600, .rideSpeed(speed))
        }
        return nil
    }

    // MARK: - Laufen

    /// Schwellentempo hält man etwa eine Stunde; von da aus nach Riegel auf die Strecke. Nach dem Rad im Triathlon je
    /// nach Strecke 5 bis 12 % langsamer.
    fileprivate func run(_ discipline: TrainingGoal.Discipline, threshold: Double?, level: StartingLevel?, afterBike: Bool) -> (Double, GoalForecast.Basis)? {
        let meters = discipline.distanceMeters
        let fatigue = !afterBike ? 1.0 : meters <= 10_500 ? 1.05 : meters <= 21_200 ? 1.08 : 1.12
        if let threshold, threshold > 0 {
            return (riegel(fromSeconds: 3600, meters: 3600 / threshold * 1000, to: meters) * fatigue, .thresholdPace(threshold))
        }
        if let best = level?.bestTimes?.filter({ $0.distanceMeters > 0 && $0.seconds > 0 })
            .min(by: { abs(Double($0.distanceMeters) - meters) < abs(Double($1.distanceMeters) - meters) }) {
            return (riegel(fromSeconds: best.seconds, meters: Double(best.distanceMeters), to: meters) * fatigue, .bestTime(meters: best.distanceMeters, seconds: best.seconds))
        }
        if let pace = level?.pace, pace > 0 {
            let threshold = pace / Self.easyToThresholdFactor
            return (riegel(fromSeconds: 3600, meters: 3600 / threshold * 1000, to: meters) * fatigue, .runPace(pace))
        }
        return nil
    }

    fileprivate func riegel(fromSeconds seconds: Double, meters: Double, to target: Double) -> Double {
        seconds * pow(target / meters, Self.riegel)
    }
}
