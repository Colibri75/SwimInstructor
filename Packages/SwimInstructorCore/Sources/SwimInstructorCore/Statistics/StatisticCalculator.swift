import Foundation

/// Die Daten, aus denen die Kacheln rechnen.
public struct StatisticInput: Sendable {
    /// Einheiten aller Sportarten, bereinigt um Duplikate.
    public let workouts: [Workout]
    public let vitals: [DailyVitals]
    /// Die gespeicherten Tagespläne, für "Plan erfüllt".
    public let plans: [DayPlanV2Response]
    /// Für die Trainingslast nach TRIMP; ohne zählen die Minuten (`TrainingLoadCalculator`).
    public let restingHeartRate: Double?
    public let maximumHeartRate: Double?
    public let now: Date

    public init(
        workouts: [Workout],
        vitals: [DailyVitals] = [],
        plans: [DayPlanV2Response] = [],
        restingHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        now: Date
    ) {
        self.workouts = workouts
        self.vitals = vitals
        self.plans = plans
        self.restingHeartRate = restingHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.now = now
    }

    /// Aus dem zuletzt gelesenen Zustand, mit Ruhe- und Maximalpuls wie beim Snapshot (dieselbe Last wie im Plan).
    public init(reading: AthleteStateReading, plans: [DayPlanV2Response], now: Date) {
        let athlete = reading.snapshot.performance?.athlete ?? []
        self.init(
            workouts: reading.allWorkouts,
            vitals: reading.vitals,
            plans: plans,
            restingHeartRate: athlete.first { $0.metric == .restingHeartRate }?.value,
            maximumHeartRate: athlete.first { $0.metric == .maxHeartRate }?.value,
            now: now
        )
    }
}

/// Ein Abschnitt im Verlauf einer Kachel.
public struct StatisticPoint: Identifiable, Equatable, Sendable {
    public let start: Date
    /// `nil` ohne Messung oder für einen Tag, der noch kommt.
    public let value: Double?

    public var id: Date { start }

    public init(start: Date, value: Double?) {
        self.start = start
        self.value = value
    }
}

/// Der Anteil einer Sportart an einer Summe über alle Sportarten (etwa Stunden je Sportart).
public struct StatisticShare: Identifiable, Equatable, Sendable {
    public let sport: SportID
    public let value: Double

    public var id: SportID { sport }

    public init(sport: SportID, value: Double) {
        self.sport = sport
        self.value = value
    }
}

/// Worauf ein Mittelwert beruht.
public enum StatisticBasis: Equatable, Sendable {
    /// So viele Einheiten mit dem Messwert.
    case workouts(Int)
    /// So viele Tage mit Messung.
    case days(Int)
    /// An so vielen der vergangenen geplanten Trainingstage trainiert.
    case planDays(trained: Int, planned: Int)
}

/// Was eine Kachel zeigt.
public struct StatisticResult: Identifiable, Equatable, Sendable {
    /// Die Kachel, wie diese App-Version sie zeigt (`SportRegistry.resolve`).
    public let tile: StatisticTile
    public let definition: StatisticDefinition
    /// `nil` ohne passende Daten im Zeitraum. Summen ohne Einheit sind 0.
    public let value: Double?
    /// Derselbe Wert für dieselben Tage davor; `nil` ohne Vergleich oder ohne Daten.
    public let previous: Double?
    public let series: [StatisticPoint]
    /// Nur über alle Sportarten und nur für Summen aus den Einheiten, in der Reihenfolge der Registry.
    public let shares: [StatisticShare]
    public let basis: StatisticBasis?

    public var id: UUID { tile.id }

    public init(
        tile: StatisticTile,
        definition: StatisticDefinition,
        value: Double?,
        previous: Double?,
        series: [StatisticPoint],
        shares: [StatisticShare],
        basis: StatisticBasis?
    ) {
        self.tile = tile
        self.definition = definition
        self.value = value
        self.previous = previous
        self.series = series
        self.shares = shares
        self.basis = basis
    }
}

/// Rechnet die Kacheln aus Einheiten, Tageswerten und Plänen. Rein rechnerisch, ohne HealthKit und UI.
public struct StatisticCalculator: Sendable {
    private let calendar: Calendar
    private let registry: SportRegistry

    public init(calendar: Calendar = .current, registry: SportRegistry = .standard) {
        self.calendar = calendar
        self.registry = registry
    }

    public func results(for tiles: [StatisticTile], input: StatisticInput) -> [StatisticResult] {
        let resolved = tiles.map(registry.resolve)
        let needsPlan = resolved.contains { $0.definition.measure == .planAdherence }
        let prepared = Prepared(input: input, planDays: needsPlan ? planDays(input) : [])
        return resolved.map { result(tile: $0.tile, definition: $0.definition, prepared) }
    }

    public func result(for tile: StatisticTile, input: StatisticInput) -> StatisticResult {
        results(for: [tile], input: input)[0]
    }

    // MARK: - Rechnen

    private struct Prepared {
        let input: StatisticInput
        /// Wie die Tage mit gespeichertem Plan ausgingen, als `yyyy-MM-dd`.
        let planDays: [(date: String, outcome: AdherenceOutcome)]
    }

    private typealias Evaluation = (value: Double?, basis: StatisticBasis?)

    private func result(tile: StatisticTile, definition: StatisticDefinition, _ prepared: Prepared) -> StatisticResult {
        let now = prepared.input.now
        let measure = definition.measure
        let interval = tile.period.interval(now: now, calendar: calendar)
        let current = evaluate(measure, sport: tile.sport, in: interval, prepared)
        let previous = tile.period.previousInterval(now: now, calendar: calendar)
            .flatMap { evaluate(measure, sport: tile.sport, in: $0, prepared).value }
        let series = tile.period.buckets(now: now, calendar: calendar).map { bucket in
            StatisticPoint(
                start: bucket.start,
                value: bucket.start < interval.end ? evaluate(measure, sport: tile.sport, in: bucket, prepared).value : nil
            )
        }
        let shares = tile.sport == nil && measure.isTotal && measure.usesWorkouts ? self.shares(measure, in: interval, prepared) : []
        return StatisticResult(
            tile: tile, definition: definition, value: current.value, previous: previous, series: series, shares: shares, basis: current.basis
        )
    }

    private func evaluate(_ measure: StatisticMeasure, sport: SportID?, in interval: StatisticInterval, _ prepared: Prepared) -> Evaluation {
        let input = prepared.input
        let workouts = input.workouts.filter { interval.contains($0.startDate) && (sport == nil || $0.sport == sport) }
        switch measure {
        case .distance:
            return (workouts.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) }, nil)
        case .duration:
            return (workouts.reduce(0.0) { $0 + max($1.duration, 0) }, nil)
        case .sessions:
            return (Double(workouts.count), nil)
        case .longestDistance:
            return (workouts.compactMap(\.distanceMeters).filter { $0 > 0 }.max(), nil)
        case .longestDuration:
            return (workouts.map(\.duration).filter { $0 > 0 }.max(), nil)
        case .pace(let meters):
            let moving = Self.withDistance(workouts)
            guard let total = moving.total else { return (nil, nil) }
            return (total.seconds / total.meters * meters, .workouts(moving.count))
        case .speed:
            let moving = Self.withDistance(workouts)
            guard let total = moving.total else { return (nil, nil) }
            return (total.meters / total.seconds, .workouts(moving.count))
        case .averageHeartRate:
            return Self.weightedMean(workouts.compactMap { workout in workout.averageHeartRate.map { (value: $0, weight: workout.duration) } })
        case .total(let metric):
            let values = workouts.compactMap { $0[metric] }
            // Einheiten ohne den Messwert: lieber kein Wert als eine falsche 0.
            guard !values.isEmpty || workouts.isEmpty else { return (nil, nil) }
            return (values.reduce(0, +), nil)
        case .average(let metric):
            return Self.weightedMean(workouts.compactMap { workout in workout[metric].map { (value: $0, weight: workout.duration) } })
        case .perDistance(let metric, let meters):
            let pairs = workouts.compactMap { workout -> (value: Double, meters: Double)? in
                guard let value = workout[metric], let distance = workout.distanceMeters, distance > 0 else { return nil }
                return (value, distance)
            }
            let distance = pairs.reduce(0.0) { $0 + $1.meters }
            guard distance > 0 else { return (nil, nil) }
            return (pairs.reduce(0.0) { $0 + $1.value } / distance * meters, .workouts(pairs.count))
        case .trainingLoad:
            let calculator = TrainingLoadCalculator(
                registry: registry, restingHeartRate: input.restingHeartRate, maximumHeartRate: input.maximumHeartRate
            )
            return (workouts.reduce(0.0) { $0 + calculator.load(of: $1) }, nil)
        case .restingHeartRate:
            return Self.dailyMean(input.vitals, in: interval) { $0.restingHeartRate }
        case .heartRateVariability:
            return Self.dailyMean(input.vitals, in: interval) { $0.hrvSDNN }
        case .sleep:
            return Self.dailyMean(input.vitals, in: interval) { $0.sleepHours.map { $0 * 3600 } }
        case .planAdherence:
            let first = PlanFormatting.isoDay(interval.start, calendar: calendar)
            let end = PlanFormatting.isoDay(interval.end, calendar: calendar)
            let outcomes = prepared.planDays.filter { $0.date >= first && $0.date < end }.map { $0.outcome }
            let summary = PlanAdherenceCalculator.summary(of: outcomes)
            guard summary.plannedTrainingDays > 0 else { return (nil, nil) }
            return (
                Double(summary.trainedDays) / Double(summary.plannedTrainingDays),
                .planDays(trained: summary.trainedDays, planned: summary.plannedTrainingDays)
            )
        }
    }

    /// Je Sportart mit einem Wert über 0: zuerst die der Registry in ihrer Reihenfolge, dann unbekannte nach Kennung.
    private func shares(_ measure: StatisticMeasure, in interval: StatisticInterval, _ prepared: Prepared) -> [StatisticShare] {
        let present = Set(prepared.input.workouts.filter { interval.contains($0.startDate) }.map(\.sport))
        let unknown = present.filter { registry.module(for: $0) == nil }.sorted { $0.rawValue < $1.rawValue }
        return (registry.ids.filter(present.contains) + unknown).compactMap { sport -> StatisticShare? in
            guard let value = evaluate(measure, sport: sport, in: interval, prepared).value, value > 0 else { return nil }
            return StatisticShare(sport: sport, value: value)
        }
    }

    /// Ausgang der Tage mit gespeichertem Plan, so weit die Einheiten zurückreichen (sonst fehlten Einheiten).
    private func planDays(_ input: StatisticInput) -> [(date: String, outcome: AdherenceOutcome)] {
        MultiSportAdherenceCalculator(calendar: calendar, registry: registry)
            .entries(plans: input.plans, workouts: input.workouts, days: SnapshotBuilder.workoutWindowDays, now: input.now)
            .map { (date: $0.date, outcome: $0.outcome) }
    }

    /// Einheiten mit Strecke und Dauer und ihre Summen.
    private static func withDistance(_ workouts: [Workout]) -> (count: Int, total: (meters: Double, seconds: Double)?) {
        let moving = workouts.filter { ($0.distanceMeters ?? 0) > 0 && $0.duration > 0 }
        guard !moving.isEmpty else { return (0, nil) }
        let meters = moving.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) }
        let seconds = moving.reduce(0.0) { $0 + $1.duration }
        return (count: moving.count, total: (meters: meters, seconds: seconds))
    }

    /// Nach Dauer gewichtet; ohne Dauer zählt jede Einheit gleich.
    private static func weightedMean(_ pairs: [(value: Double, weight: Double)]) -> Evaluation {
        let valid = pairs.filter { $0.value.isFinite }
        guard !valid.isEmpty else { return (nil, nil) }
        let weight = valid.reduce(0.0) { $0 + max($1.weight, 0) }
        let mean = weight > 0
            ? valid.reduce(0.0) { $0 + $1.value * max($1.weight, 0) } / weight
            : valid.reduce(0.0) { $0 + $1.value } / Double(valid.count)
        return (mean, .workouts(valid.count))
    }

    private static func dailyMean(_ vitals: [DailyVitals], in interval: StatisticInterval, _ value: (DailyVitals) -> Double?) -> Evaluation {
        let values = vitals.filter { interval.contains($0.date) }.compactMap(value).filter(\.isFinite)
        guard !values.isEmpty else { return (nil, nil) }
        return (values.reduce(0, +) / Double(values.count), .days(values.count))
    }
}
