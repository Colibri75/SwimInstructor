import XCTest
@testable import SwimInstructorCore

@MainActor
final class PerformanceProfileLoaderTests: XCTestCase {
    /// Hält das Profil im Speicher; kann so tun, als ließe sich nichts speichern.
    private final class MemoryProfileStore: PerformanceProfileStoring {
        var stored: PerformanceProfile
        var rejects = false
        private(set) var resets = 0
        init(_ stored: PerformanceProfile = PerformanceProfile.empty) { self.stored = stored }

        func profile() -> PerformanceProfile { stored }

        @discardableResult
        func record(_ value: PerformanceValue) -> Bool {
            guard !rejects else { return false }
            stored = stored.recording(value)
            return true
        }

        func reset() {
            stored = PerformanceProfile.empty
            resets += 1
        }
    }

    private func makeLoader(store: MemoryProfileStore = MemoryProfileStore(), estimates: [PerformanceValue] = []) -> PerformanceProfileLoader {
        let loader = PerformanceProfileLoader(store: store, now: { TestFixtures.now })
        loader.estimatesProvider = { estimates }
        return loader
    }

    /// Ein bestätigter Schwellenpuls beim Laufen.
    private func storeWithRunThreshold(_ value: Double) -> MemoryProfileStore {
        MemoryProfileStore(PerformanceProfile(values: [
            TestFixtures.performance(.thresholdHeartRate, value, .tested, sport: .run, daysAgo: 30)
        ]))
    }

    // MARK: - Lesen

    func testEntriesShowTheEstimatesButIgnoreConfirmedValuesFromTheProvider() throws {
        let loader = makeLoader(estimates: [
            TestFixtures.performance(.maxHeartRate, 188, .estimated),
            TestFixtures.performance(.restingHeartRate, 52, .estimated),
            TestFixtures.performance(.thresholdHeartRate, 165, .formula, sport: .run),
            // Bestätigte Werte gelten nur aus dem eigenen Profil, nie aus dem Snapshot.
            TestFixtures.performance(.criticalSwimPace, 99, .tested, sport: .swim)
        ])

        let athlete = loader.entries(for: nil)
        XCTAssertEqual(athlete.map(\.definition.metric), [PerformanceMetric.maxHeartRate, PerformanceMetric.restingHeartRate])
        XCTAssertEqual(athlete.map(\.id), ["-|max_heart_rate", "-|resting_heart_rate"])
        XCTAssertEqual(athlete.first?.current?.value, 188)
        XCTAssertEqual(athlete.first?.current?.source, .estimated)
        XCTAssertEqual(athlete.first?.history, [])

        let run = loader.entries(for: SportID.run)
        XCTAssertEqual(run.map(\.definition.metric), [PerformanceMetric.thresholdHeartRate, PerformanceMetric.thresholdPacePerKilometer])
        XCTAssertEqual(run.first?.id, "run|threshold_heart_rate")
        XCTAssertEqual(run.first?.current?.value, 165)
        XCTAssertEqual(run.first?.current?.source, .formula)
        XCTAssertNil(run.last?.current)

        let swim = try XCTUnwrap(loader.entries(for: SportID.swim).first)
        XCTAssertEqual(swim.definition.metric, PerformanceMetric.criticalSwimPace)
        XCTAssertNil(swim.current)
        XCTAssertNil(loader.current(.criticalSwimPace, sport: SportID.swim))

        XCTAssertEqual(loader.entries(for: SportID(rawValue: "kayak")), [])
    }

    func testConfirmedValuesWinOverEstimatesAndShowTheirHistory() throws {
        let store = MemoryProfileStore(PerformanceProfile(values: [
            TestFixtures.performance(.criticalSwimPace, 112, .tested, sport: .swim, daysAgo: 40),
            TestFixtures.performance(.criticalSwimPace, 105, .manual, sport: .swim, daysAgo: 2)
        ]))
        let loader = makeLoader(store: store, estimates: [TestFixtures.performance(.criticalSwimPace, 98, .estimated, sport: .swim)])

        let swim = try XCTUnwrap(loader.entries(for: SportID.swim).first)

        XCTAssertEqual(swim.current?.value, 105)
        XCTAssertEqual(swim.current?.source, .manual)
        XCTAssertEqual(swim.history.map(\.value), [112, 105])
    }

    // MARK: - Von Hand

    func testAManualValueIsStoredAndCountsAtOnce() {
        let store = MemoryProfileStore()
        let loader = makeLoader(store: store)

        let stored = loader.setManual(186, metric: .maxHeartRate, sport: nil)

        XCTAssertTrue(stored)
        XCTAssertEqual(loader.profile.history(of: .maxHeartRate), [
            PerformanceValue(sport: nil, metric: .maxHeartRate, value: 186, source: .manual, measuredAt: TestFixtures.now)
        ])
        XCTAssertEqual(store.stored, loader.profile)
        XCTAssertEqual(loader.current(.maxHeartRate, sport: nil)?.value, 186)
        XCTAssertEqual(loader.entries(for: nil).first?.history.count, 1)
        XCTAssertNil(loader.error)
    }

    func testAManualValueOutsideThePlausibleRangeIsRejected() {
        let store = MemoryProfileStore()
        let loader = makeLoader(store: store)

        XCTAssertFalse(loader.setManual(250, metric: .maxHeartRate, sport: nil))
        XCTAssertEqual(loader.error, "Maximalpuls liegt außerhalb von 120 bpm bis 230 bpm.")
        XCTAssertFalse(loader.setManual(Double.nan, metric: .thresholdHeartRate, sport: SportID.run))
        XCTAssertFalse(loader.setManual(40, metric: .criticalSwimPace, sport: SportID.swim))
        XCTAssertEqual(loader.profile, PerformanceProfile.empty)
        XCTAssertEqual(store.stored, PerformanceProfile.empty)

        // Ein gültiger Wert danach löscht den Hinweis.
        XCTAssertTrue(loader.setManual(171, metric: .thresholdHeartRate, sport: SportID.run))
        XCTAssertNil(loader.error)
    }

    func testAnUnknownMetricIsRejected() {
        let store = MemoryProfileStore()
        let loader = makeLoader(store: store)

        // Laufen kennt keine CSS, der Schwellenpuls gehört zu einer Sportart, eine unbekannte Sportart kennt nichts.
        XCTAssertFalse(loader.setManual(105, metric: .criticalSwimPace, sport: SportID.run))
        XCTAssertEqual(loader.error, "Diesen Wert kennt die App nicht.")
        XCTAssertFalse(loader.setManual(170, metric: .thresholdHeartRate, sport: nil))
        XCTAssertFalse(loader.setManual(170, metric: .thresholdHeartRate, sport: SportID(rawValue: "kayak")))
        XCTAssertFalse(loader.setManual(170, metric: PerformanceMetric(rawValue: "vo2max"), sport: nil))
        XCTAssertEqual(store.stored, PerformanceProfile.empty)
    }

    // MARK: - Testergebnis vorlegen

    func testAProposalShowsTheValuesWithThePreviousOneAndTheChange() throws {
        // Bisher nur die Faustformel für den Schwellenpuls beim Laufen.
        let loader = makeLoader(estimates: [TestFixtures.performance(.thresholdHeartRate, 168, .formula, sport: .run)])

        let proposed = loader.propose(
            testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 172, "threshold_pace_per_km": 290]
        )

        XCTAssertTrue(proposed)
        let pending = try XCTUnwrap(loader.pending)
        XCTAssertEqual(pending.sport, SportID.run)
        XCTAssertEqual(pending.testID, "threshold_30min")
        XCTAssertEqual(pending.testName, "30-Minuten-Test")
        XCTAssertEqual(pending.measuredAt, TestFixtures.now)
        XCTAssertEqual(pending.proposals.map(\.definition.metric), [PerformanceMetric.thresholdHeartRate, PerformanceMetric.thresholdPacePerKilometer])
        XCTAssertEqual(pending.proposals.map(\.value), [172, 290])
        XCTAssertFalse(pending.needsReview)

        let heartRate = try XCTUnwrap(pending.proposals.first)
        XCTAssertEqual(heartRate.id, "threshold_heart_rate")
        XCTAssertEqual(heartRate.previous?.value, 168)
        XCTAssertEqual(heartRate.previous?.source, .formula)
        let change = try XCTUnwrap(heartRate.changePercent)
        XCTAssertEqual(change, 2.38, accuracy: 0.01)
        XCTAssertFalse(heartRate.needsReview)

        // Ohne bisherigen Wert gibt es keine Änderung.
        let pace = try XCTUnwrap(pending.proposals.last)
        XCTAssertNil(pace.previous)
        XCTAssertNil(pace.changePercent)
        XCTAssertFalse(pace.needsReview)

        // Erst vorgelegt, noch nicht im Profil.
        XCTAssertEqual(loader.profile, PerformanceProfile.empty)
        XCTAssertNil(loader.error)
    }

    func testAJumpOfMoreThanTenPercentNeedsReview() throws {
        XCTAssertEqual(PerformanceProfileLoader.reviewThresholdPercent, 10)

        // 160 → 180: +12,5 %.
        let up = makeLoader(store: storeWithRunThreshold(160))
        XCTAssertTrue(up.propose(testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 180]))
        let upChange = try XCTUnwrap(up.pending?.proposals.first?.changePercent)
        XCTAssertEqual(upChange, 12.5, accuracy: 0.001)
        XCTAssertEqual(up.pending?.proposals.first?.needsReview, true)
        XCTAssertEqual(up.pending?.needsReview, true)

        // 160 → 140: −12,5 %, ebenso.
        let down = makeLoader(store: storeWithRunThreshold(160))
        XCTAssertTrue(down.propose(testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 140]))
        XCTAssertEqual(down.pending?.needsReview, true)

        // 150 → 165: genau 10 %, noch kein Sprung.
        let edge = makeLoader(store: storeWithRunThreshold(150))
        XCTAssertTrue(edge.propose(testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 165]))
        XCTAssertEqual(edge.pending?.needsReview, false)

        // 160 → 170: +6,25 %.
        let small = makeLoader(store: storeWithRunThreshold(160))
        XCTAssertTrue(small.propose(testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 170]))
        XCTAssertEqual(small.pending?.needsReview, false)
    }

    func testTheCssTestGivesThePacePer100Meters() throws {
        let loader = makeLoader()

        // (400 s − 190 s) / 2 = 105 s pro 100 m.
        XCTAssertTrue(loader.propose(testID: "css_400_200", sport: .swim, entries: ["time_400m": 400, "time_200m": 190]))

        let proposal = try XCTUnwrap(loader.pending?.proposals.first)
        XCTAssertEqual(loader.pending?.proposals.count, 1)
        XCTAssertEqual(proposal.definition.metric, PerformanceMetric.criticalSwimPace)
        XCTAssertEqual(proposal.value, 105)
    }

    func testTheBikeTestNeedsOnlyTheHeartRateWithoutAPowerMeter() throws {
        let loader = makeLoader()

        XCTAssertTrue(loader.propose(testID: "threshold_30min", sport: .bike, entries: ["threshold_heart_rate": 165]))

        XCTAssertEqual(loader.pending?.proposals.map(\.definition.metric), [PerformanceMetric.thresholdHeartRate])
    }

    func testATestWithoutFullEffortIsRejected() {
        let loader = makeLoader()

        let proposed = loader.propose(testID: "entry_easy_25min", sport: .run, entries: ["threshold_pace_per_km": 330])

        XCTAssertFalse(proposed)
        XCTAssertNil(loader.pending)
        XCTAssertEqual(
            loader.error,
            "Einstiegstest locker ist kein Test mit Vollbelastung. Das Tempo schätzt die App aus deinen Einheiten."
        )
    }

    func testAnUnknownTestIsRejected() {
        let loader = makeLoader()

        // Der CSS-Test gehört zum Schwimmen, nicht zum Laufen.
        XCTAssertFalse(loader.propose(testID: "css_400_200", sport: .run, entries: ["time_400m": 400, "time_200m": 190]))
        XCTAssertEqual(loader.error, "Diesen Test kennt die App nicht.")
        XCTAssertFalse(loader.propose(testID: "threshold_30min", sport: SportID(rawValue: "kayak"), entries: ["threshold_heart_rate": 160]))
        XCTAssertNil(loader.pending)
    }

    func testInvalidInputsGiveNoResult() {
        let loader = makeLoader()
        let message = "Aus diesen Angaben ergibt sich kein Wert. Prüf die Eingaben."

        // 400 m nicht langsamer als 200 m.
        XCTAssertFalse(loader.propose(testID: "css_400_200", sport: .swim, entries: ["time_400m": 300, "time_200m": 320]))
        XCTAssertEqual(loader.error, message)
        // Außerhalb des Bereichs der Eingabe.
        XCTAssertFalse(loader.propose(testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 250]))
        XCTAssertEqual(loader.error, message)
        // Nichts eingetragen, eine fremde Eingabe oder kein endlicher Wert.
        XCTAssertFalse(loader.propose(testID: "threshold_30min", sport: .run, entries: [:]))
        XCTAssertFalse(loader.propose(testID: "threshold_30min", sport: .run, entries: ["time_400m": 400]))
        XCTAssertFalse(loader.propose(testID: "time_trial_1000m", sport: .swim, entries: ["time_1000m": Double.infinity]))
        XCTAssertNil(loader.pending)
        XCTAssertEqual(loader.profile, PerformanceProfile.empty)
    }

    // MARK: - Übernehmen oder verwerfen

    func testAcceptingStoresThePendingResultAsTested() throws {
        let store = MemoryProfileStore()
        let loader = makeLoader(store: store, estimates: [TestFixtures.performance(.thresholdHeartRate, 168, .formula, sport: .run)])
        let measured = TestFixtures.date(daysAgo: 1, hour: 18)
        XCTAssertTrue(loader.propose(
            testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 172, "threshold_pace_per_km": 290], measuredAt: measured
        ))

        let accepted = loader.accept()

        XCTAssertTrue(accepted)
        XCTAssertNil(loader.pending)
        XCTAssertNil(loader.error)
        XCTAssertEqual(loader.profile.history(of: .thresholdHeartRate, sport: SportID.run), [
            PerformanceValue(sport: SportID.run, metric: .thresholdHeartRate, value: 172, source: .tested, measuredAt: measured)
        ])
        XCTAssertEqual(loader.profile.history(of: .thresholdPacePerKilometer, sport: SportID.run), [
            PerformanceValue(sport: SportID.run, metric: .thresholdPacePerKilometer, value: 290, source: .tested, measuredAt: measured)
        ])
        XCTAssertEqual(store.stored, loader.profile)
        // Der getestete Wert geht jetzt der Faustformel vor.
        XCTAssertEqual(loader.current(.thresholdHeartRate, sport: SportID.run)?.value, 172)
        XCTAssertEqual(loader.current(.thresholdHeartRate, sport: SportID.run)?.source, .tested)
    }

    func testAcceptingWithoutAPendingResultDoesNothing() {
        let store = MemoryProfileStore()
        let loader = makeLoader(store: store)

        XCTAssertFalse(loader.accept())
        XCTAssertEqual(store.stored, PerformanceProfile.empty)
    }

    func testAFailedSaveKeepsThePendingResult() {
        let store = MemoryProfileStore()
        store.rejects = true
        let loader = makeLoader(store: store)
        XCTAssertTrue(loader.propose(testID: "css_400_200", sport: .swim, entries: ["time_400m": 400, "time_200m": 190]))

        XCTAssertFalse(loader.accept())

        XCTAssertNotNil(loader.pending)
        XCTAssertEqual(loader.error, "Der Wert konnte nicht gespeichert werden.")
        XCTAssertEqual(loader.profile, PerformanceProfile.empty)
    }

    func testDiscardingLeavesTheProfileUnchanged() {
        let store = storeWithRunThreshold(160)
        let before = store.stored
        let loader = makeLoader(store: store)
        XCTAssertTrue(loader.propose(testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 180]))

        loader.discard()

        XCTAssertNil(loader.pending)
        XCTAssertEqual(loader.profile, before)
        XCTAssertEqual(store.stored, before)
        XCTAssertEqual(loader.current(.thresholdHeartRate, sport: SportID.run)?.value, 160)
    }

    func testResetClearsTheProfileThePendingResultAndTheError() {
        let store = storeWithRunThreshold(160)
        let loader = makeLoader(store: store)
        XCTAssertTrue(loader.propose(testID: "threshold_30min", sport: .run, entries: ["threshold_heart_rate": 170]))
        XCTAssertFalse(loader.setManual(250, metric: .maxHeartRate, sport: nil))

        loader.reset()

        XCTAssertEqual(store.resets, 1)
        XCTAssertEqual(loader.profile, PerformanceProfile.empty)
        XCTAssertNil(loader.pending)
        XCTAssertNil(loader.error)
    }

    func testAnAcceptedResultIsKeptInTheSettings() throws {
        let suiteName = "PerformanceProfileLoaderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loader = PerformanceProfileLoader(store: UserDefaultsPerformanceProfileStore(defaults: defaults), now: { TestFixtures.now })
        XCTAssertTrue(loader.propose(testID: "css_400_200", sport: .swim, entries: ["time_400m": 400, "time_200m": 190]))
        XCTAssertTrue(loader.accept())

        let reopened = PerformanceProfileLoader(store: UserDefaultsPerformanceProfileStore(defaults: defaults), now: { TestFixtures.now })

        XCTAssertEqual(reopened.current(.criticalSwimPace, sport: SportID.swim)?.value, 105)
        XCTAssertEqual(reopened.current(.criticalSwimPace, sport: SportID.swim)?.source, .tested)
        XCTAssertEqual(reopened.entries(for: SportID.swim).first?.history.count, 1)
    }

    // MARK: - Snapshot

    func testTheSnapshotSummaryBecomesPerformanceValues() {
        let measured = TestFixtures.date(daysAgo: 3, hour: 12)
        let summary = AthleteStateSnapshot.PerformanceSummary(
            athlete: [
                AthleteStateSnapshot.PerformanceSummary.Value(metric: .maxHeartRate, value: 190, source: .estimated, measuredAt: measured)
            ],
            sports: [
                AthleteStateSnapshot.PerformanceSummary.Sport(
                    sport: .swim,
                    values: [AthleteStateSnapshot.PerformanceSummary.Value(metric: .criticalSwimPace, value: 105, source: .tested, measuredAt: measured)],
                    zones: []
                ),
                AthleteStateSnapshot.PerformanceSummary.Sport(
                    sport: .run,
                    values: [AthleteStateSnapshot.PerformanceSummary.Value(metric: .thresholdHeartRate, value: 167, source: .formula, measuredAt: measured)],
                    zones: []
                )
            ]
        )

        XCTAssertEqual(summary.performanceValues, [
            PerformanceValue(sport: nil, metric: .maxHeartRate, value: 190, source: .estimated, measuredAt: measured),
            PerformanceValue(sport: SportID.swim, metric: .criticalSwimPace, value: 105, source: .tested, measuredAt: measured),
            PerformanceValue(sport: SportID.run, metric: .thresholdHeartRate, value: 167, source: .formula, measuredAt: measured)
        ])
        XCTAssertTrue(AthleteStateSnapshot.PerformanceSummary(athlete: [], sports: []).performanceValues.isEmpty)

        // So kommen die Schätzungen aus dem Snapshot in die Ansicht: Der getestete Wert zählt dort nicht.
        let loader = makeLoader(estimates: summary.performanceValues)
        XCTAssertEqual(loader.current(.maxHeartRate, sport: nil)?.value, 190)
        XCTAssertEqual(loader.current(.thresholdHeartRate, sport: SportID.run)?.value, 167)
        XCTAssertNil(loader.current(.criticalSwimPace, sport: SportID.swim))
    }
}
