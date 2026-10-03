import XCTest
@testable import SwimInstructorCore

final class PerformanceProfileTests: XCTestCase {
    private func perf(
        _ metric: PerformanceMetric, _ value: Double, _ source: PerformanceOrigin, _ sport: SportID? = nil, _ daysAgo: Int = 0
    ) -> PerformanceValue {
        TestFixtures.performance(metric, value, source, sport: sport, daysAgo: daysAgo)
    }

    // MARK: - Herkunft und Verlauf

    func testConfirmedOriginsOutrankEstimatesAndFormulas() {
        XCTAssertTrue(PerformanceOrigin.tested.isConfirmed)
        XCTAssertTrue(PerformanceOrigin.manual.isConfirmed)
        XCTAssertFalse(PerformanceOrigin.estimated.isConfirmed)
        XCTAssertFalse(PerformanceOrigin.formula.isConfirmed)
        XCTAssertGreaterThan(PerformanceOrigin.tested.rank, PerformanceOrigin.estimated.rank)
        XCTAssertGreaterThan(PerformanceOrigin.estimated.rank, PerformanceOrigin.formula.rank)
        XCTAssertEqual(PerformanceOrigin.tested.rank, PerformanceOrigin.manual.rank)
    }

    func testRecordingKeepsHistorySortedAndSeparatedBySportAndMetric() {
        let profile = PerformanceProfile.empty
            .recording(perf(.criticalSwimPace, 105, .tested, .swim, 2))
            .recording(perf(.criticalSwimPace, 112, .tested, .swim, 40))
            .recording(perf(.thresholdHeartRate, 168, .manual, .run, 5))
            .recording(perf(.thresholdHeartRate, 158, .manual, .bike, 5))
            .recording(perf(.maxHeartRate, 191, .manual, nil, 9))

        XCTAssertEqual(profile.history(of: .criticalSwimPace, sport: .swim).map(\.value), [112, 105])
        XCTAssertEqual(profile.history(of: .thresholdHeartRate, sport: .run).map(\.value), [168])
        XCTAssertEqual(profile.history(of: .thresholdHeartRate, sport: .bike).map(\.value), [158])
        XCTAssertEqual(profile.history(of: .maxHeartRate).map(\.value), [191])
        XCTAssertTrue(profile.history(of: .maxHeartRate, sport: .run).isEmpty)
        XCTAssertEqual(profile.values.count, 5)
    }

    func testHistoryKeepsOnlyTheNewestValuesPerMetric() {
        var profile = PerformanceProfile.empty.recording(perf(.thresholdHeartRate, 150, .manual, .bike, 0))
        for daysAgo in 1...(PerformanceProfile.historyLimit + 5) {
            profile = profile.recording(perf(.criticalSwimPace, Double(100 + daysAgo), .tested, .swim, daysAgo))
        }
        let history = profile.history(of: .criticalSwimPace, sport: .swim)
        XCTAssertEqual(history.count, PerformanceProfile.historyLimit)
        XCTAssertEqual(history.last?.value, 101, "der neueste bleibt")
        XCTAssertEqual(history.first?.value, Double(100 + PerformanceProfile.historyLimit), "die ältesten fallen weg")
        XCTAssertEqual(profile.history(of: .thresholdHeartRate, sport: .bike).count, 1, "andere Werte bleiben")
    }

    func testProfileRoundTripsAsJSON() throws {
        let profile = PerformanceProfile.empty
            .recording(perf(.criticalSwimPace, 105, .tested, .swim, 2))
            .recording(perf(.maxHeartRate, 191, .manual, nil, 9))
        let decoded = try JSONDecoder().decode(PerformanceProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    // MARK: - Auflösen

    func testConfirmedValueBeatsNewerEstimateAndNewestConfirmedWins() {
        let profile = PerformanceProfile(values: [
            perf(.criticalSwimPace, 112, .tested, .swim, 40),
            perf(.criticalSwimPace, 105, .manual, .swim, 10)
        ])
        let resolved = ResolvedPerformance(profile: profile, estimates: [perf(.criticalSwimPace, 120, .estimated, .swim, 0)])
        XCTAssertEqual(resolved.value(.criticalSwimPace, sport: .swim)?.value, 105)
        XCTAssertEqual(resolved.value(.criticalSwimPace, sport: .swim)?.source, .manual)
    }

    func testEstimateBeatsFormulaAndNewerBeatsOlderOfTheSameOrigin() {
        let resolved = ResolvedPerformance(profile: .empty, estimates: [
            perf(.thresholdHeartRate, 160, .formula, .bike, 0),
            perf(.thresholdHeartRate, 150, .estimated, .bike, 3),
            perf(.thresholdHeartRate, 152, .estimated, .bike, 1)
        ])
        XCTAssertEqual(resolved.value(.thresholdHeartRate, sport: .bike)?.value, 152)
    }

    func testHigherObservedMaximumHeartRateReplacesAConfirmedOne() {
        let profile = PerformanceProfile(values: [perf(.maxHeartRate, 185, .tested, nil, 30)])

        let higher = ResolvedPerformance(profile: profile, estimates: [perf(.maxHeartRate, 192, .estimated), perf(.maxHeartRate, 200, .formula)])
        XCTAssertEqual(higher.value(.maxHeartRate)?.value, 192, "gemessen höher: gilt")
        XCTAssertEqual(higher.value(.maxHeartRate)?.source, .estimated)

        let lower = ResolvedPerformance(profile: profile, estimates: [perf(.maxHeartRate, 180, .estimated)])
        XCTAssertEqual(lower.value(.maxHeartRate)?.value, 185, "gemessen niedriger: der bestätigte bleibt")

        // Bei anderen Werten löst eine höhere Schätzung nichts ab.
        let threshold = ResolvedPerformance(
            profile: PerformanceProfile(values: [perf(.thresholdHeartRate, 160, .tested, .run, 30)]),
            estimates: [perf(.thresholdHeartRate, 170, .estimated, .run)]
        )
        XCTAssertEqual(threshold.value(.thresholdHeartRate, sport: .run)?.value, 160)
    }

    func testImplausibleAndUnknownValuesAreDropped() {
        let resolved = ResolvedPerformance(profile: .empty, estimates: [
            perf(.maxHeartRate, 250, .estimated),
            perf(.maxHeartRate, 180, .formula),
            perf(.restingHeartRate, 20, .estimated),
            perf("vo2max", 55, .tested, .run),
            perf(.criticalSwimPace, 105, .tested, .run),
            perf(.criticalSwimPace, 105, .tested, "kayak")
        ])
        XCTAssertEqual(resolved.value(.maxHeartRate)?.value, 180, "250 ist ein Messfehler, die Formel bleibt")
        XCTAssertNil(resolved.value(.restingHeartRate))
        XCTAssertEqual(resolved.values.count, 1)
    }

    func testValuesComeInRegistryOrderAthleteFirst() {
        let resolved = ResolvedPerformance(profile: .empty, estimates: [
            perf(.thresholdPacePerKilometer, 290, .estimated, .run),
            perf(.thresholdHeartRate, 160, .formula, .bike),
            perf(.criticalSwimPace, 105, .tested, .swim),
            perf(.restingHeartRate, 52, .estimated),
            perf(.maxHeartRate, 188, .estimated)
        ])
        XCTAssertEqual(resolved.values.map(\.metric), [.maxHeartRate, .restingHeartRate, .criticalSwimPace, .thresholdHeartRate, .thresholdPacePerKilometer])
    }

    func testBasisFallsBackToTheValueForAllSports() {
        let resolved = ResolvedPerformance(profile: .empty, estimates: [perf(.maxHeartRate, 188, .estimated)])
        XCTAssertEqual(resolved.basis(.maxHeartRate, sport: .swim)?.value, 188)
        XCTAssertNil(resolved.basis(.criticalSwimPace, sport: .swim))
    }

    // MARK: - Zonen und Snapshot

    func testZonesNeedTheirBasisValue() {
        let resolved = ResolvedPerformance(profile: .empty, estimates: [perf(.thresholdHeartRate, 160, .formula, .bike)])
        let zones = resolved.zones(for: BikeModule())
        XCTAssertEqual(zones.map(\.target), [.heartRateZone], "ohne FTP keine Leistungszonen")
        XCTAssertEqual(zones.first?.zone(2), TrainingZones.Zone(zone: 2, minimum: 130, maximum: 144))
        XCTAssertTrue(resolved.zones(for: RunModule()).isEmpty)
    }

    func testSummaryListsTheAthleteValuesAndOnlySportsWithValuesOrZones() {
        let resolved = ResolvedPerformance(profile: .empty, estimates: [
            perf(.maxHeartRate, 188, .estimated),
            perf(.thresholdHeartRate, 160, .formula, .bike)
        ])
        let summary = resolved.summary(sports: [.swim, .bike, .run, "kayak"])

        XCTAssertEqual(summary.athlete, [.init(metric: .maxHeartRate, value: 188, source: .estimated, measuredAt: TestFixtures.date(daysAgo: 0, hour: 12))])
        // Schwimmen hat nur Pulszonen aus dem Maximalpuls, Laufen gar nichts, "kayak" kennt die App nicht.
        XCTAssertEqual(summary.sports.map(\.sport), [.swim, .bike])
        XCTAssertTrue(summary.sports.first?.values.isEmpty ?? false)
        XCTAssertEqual(summary.sports.first?.zones.map(\.target), [.heartRateZone])
        XCTAssertEqual(summary.sports.last?.values.map(\.value), [160])
    }
}
