import Foundation

/// Ein geschätzter Wert, wie ihn ein Modul liefert; Sportart und Zeitpunkt setzt `PerformanceEstimator`.
public struct PerformanceEstimate: Equatable, Sendable {
    public let metric: PerformanceMetric
    public let value: Double
    /// `.estimated` (aus Messwerten) oder `.formula` (Faustformel).
    public let source: PerformanceOrigin

    public init(metric: PerformanceMetric, value: Double, source: PerformanceOrigin) {
        self.metric = metric
        self.value = value
        self.source = source
    }
}

/// Was ein Modul zum Schätzen bekommt.
public struct PerformanceEstimationContext: Sendable {
    public let sport: SportID
    public let now: Date
    /// Die Einheiten dieser Sportart im Fenster des Snapshots.
    public let workouts: [Workout]
    /// Die schon bekannten Werte: bestätigte aller Sportarten und die für alle Sportarten (Maximal-, Ruhepuls).
    public let known: ResolvedPerformance

    public init(sport: SportID, now: Date, workouts: [Workout], known: ResolvedPerformance) {
        self.sport = sport
        self.now = now
        self.workouts = workouts
        self.known = known
    }

    public var maximumHeartRate: Double? { known.value(.maxHeartRate)?.value }
    public var restingHeartRate: Double? { known.value(.restingHeartRate)?.value }

    /// Ein bekannter Wert dieser Sportart (etwa ein getesteter Schwellenpuls).
    public func value(_ metric: PerformanceMetric) -> Double? {
        known.value(metric, sport: sport)?.value
    }
}

/// Was die Schätzung aus Health bekommt.
public struct PerformanceEstimationInput: Sendable {
    public let now: Date
    /// Die Einheiten aller Sportarten im Fenster des Snapshots.
    public let workouts: [Workout]
    /// Tageswerte; der Ruhepuls ist der Schnitt der letzten sieben Tage mit Messung.
    public let vitals: [DailyVitals]
    /// Höchster gemessener Puls je Tag der letzten sechs Monate.
    public let dailyMaximumHeartRates: [Double]
    /// Alter in Jahren, für die Faustformel des Maximalpulses.
    public let age: Int?

    public init(now: Date, workouts: [Workout], vitals: [DailyVitals], dailyMaximumHeartRates: [Double], age: Int?) {
        self.now = now
        self.workouts = workouts
        self.vitals = vitals
        self.dailyMaximumHeartRates = dailyMaximumHeartRates
        self.age = age
    }
}

/// Startwerte ohne Test: Maximal- und Ruhepuls hier, alles Sportartspezifische im Modul
/// (`SportModule.estimatePerformance`). Bestätigte Werte aus dem Profil gehen immer vor (`ResolvedPerformance`).
public struct PerformanceEstimator: Sendable {
    /// Wie weit der höchste gemessene Puls zurückreicht.
    public static let maximumHeartRateWindowDays = 182

    public let registry: SportRegistry

    public init(registry: SportRegistry = .standard) {
        self.registry = registry
    }

    public func resolve(profile: PerformanceProfile, input: PerformanceEstimationInput) -> ResolvedPerformance {
        var estimates = athleteEstimates(input).map {
            PerformanceValue(metric: $0.metric, value: $0.value, source: $0.source, measuredAt: input.now)
        }
        // Erst die Werte für alle Sportarten auflösen: Die Module rechnen mit dem gültigen Maximalpuls.
        let known = ResolvedPerformance(profile: profile, estimates: estimates, registry: registry)
        for module in registry.modules {
            let context = PerformanceEstimationContext(
                sport: module.id,
                now: input.now,
                workouts: input.workouts.filter { $0.sport == module.id },
                known: known
            )
            estimates += module.estimatePerformance(context).map {
                PerformanceValue(sport: module.id, metric: $0.metric, value: $0.value, source: $0.source, measuredAt: input.now)
            }
        }
        return ResolvedPerformance(profile: profile, estimates: estimates, registry: registry)
    }

    /// So weit darf ein gemessener Maximalpuls über der Faustformel liegen (gut zwei Standardabweichungen von Tanaka).
    /// Höher ist fast immer ein Messfehler des Sensors.
    public static let maximumHeartRateAboveFormula = 20.0

    /// Maximalpuls nach Tanaka (208 − 0,7 × Alter).
    static func formulaMaximumHeartRate(age: Int?) -> Double? {
        guard let age, age > 0 else { return nil }
        return (208 - 0.7 * Double(age)).rounded()
    }

    /// Der gemessene Maximalpuls aus den Tageshöchstwerten, robust gegen Ausreißer des Sensors:
    /// - Werte mehr als `maximumHeartRateAboveFormula` über der Faustformel fallen weg.
    /// - Es zählt der zweithöchste Tag: Ein Wert muss an zwei Tagen erreicht sein, eine einzelne Spitze reicht nicht.
    /// - Unter der Faustformel ist eine Messung nur eine Untergrenze (man war nie am Anschlag) und kein Maximalpuls.
    static func observedMaximumHeartRate(dailyMaxima: [Double], age: Int?) -> Double? {
        let formula = formulaMaximumHeartRate(age: age)
        let ceiling = formula.map { $0 + maximumHeartRateAboveFormula } ?? PerformanceMetricDefinition.maxHeartRate.plausibleRange.upperBound
        let plausible = dailyMaxima.filter { $0 <= ceiling }.sorted(by: >)
        guard plausible.count >= 2 else { return nil }
        let observed = plausible[1].rounded()
        if let formula, observed <= formula { return nil }
        return observed
    }

    /// Maximalpuls gemessen (`observedMaximumHeartRate`) und nach Tanaka, Ruhepuls als Schnitt der letzten sieben Messtage.
    func athleteEstimates(_ input: PerformanceEstimationInput) -> [PerformanceEstimate] {
        var estimates: [PerformanceEstimate] = []
        if let observed = Self.observedMaximumHeartRate(dailyMaxima: input.dailyMaximumHeartRates, age: input.age) {
            estimates.append(PerformanceEstimate(metric: .maxHeartRate, value: observed, source: .estimated))
        }
        if let formula = Self.formulaMaximumHeartRate(age: input.age) {
            estimates.append(PerformanceEstimate(metric: .maxHeartRate, value: formula, source: .formula))
        }
        let resting = input.vitals
            .filter { $0.restingHeartRate != nil }
            .sorted { $0.date > $1.date }
            .prefix(7)
            .compactMap(\.restingHeartRate)
        if !resting.isEmpty {
            let average = resting.reduce(0, +) / Double(resting.count)
            estimates.append(PerformanceEstimate(metric: .restingHeartRate, value: average.rounded(), source: .estimated))
        }
        return estimates
    }
}
