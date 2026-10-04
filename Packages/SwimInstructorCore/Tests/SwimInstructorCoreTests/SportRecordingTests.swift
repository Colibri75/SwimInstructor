import XCTest
import HealthKit
@testable import SwimInstructorCore

/// Was die Module der Watch über die Aufzeichnung sagen: Orte, Anzeige, Konfiguration und Metadaten für Health.
final class SportRecordingTests: XCTestCase {
    private func module(_ sport: SportID) throws -> any SportModule {
        try XCTUnwrap(SportRegistry.standard.module(for: sport))
    }

    // MARK: - Module

    func testSwimmingRecordsInThePoolOrOpenWater() throws {
        let recording = try module(.swim).recording

        XCTAssertEqual(recording.locations, [.pool, .openWater])
        XCTAssertEqual(recording.primaryField, .pacePerHundredMeters)
        XCTAssertEqual(recording.secondaryFields, [.distanceMeters, .laps])
        XCTAssertEqual(recording.speedSmoothing, SpeedSmoothing(
            window: CurrentPaceTracker.window, staleAfter: CurrentPaceTracker.staleAfter, minimumMeters: CurrentPaceTracker.minimumMeters
        ))
    }

    func testRunningAndCyclingRecordOutdoorsOrIndoors() throws {
        let run = try module(.run).recording
        XCTAssertEqual(run.locations, [.outdoor, .indoor])
        XCTAssertEqual(run.primaryField, .pacePerKilometer)
        XCTAssertEqual(run.secondaryFields, [.distanceKilometers, .power])

        let bike = try module(.bike).recording
        XCTAssertEqual(bike.locations, [.outdoor, .indoor])
        XCTAssertEqual(bike.primaryField, .speed)
        XCTAssertEqual(bike.secondaryFields, [.distanceKilometers, .elevationGain, .power, .cadence])
        XCTAssertEqual(bike.speedSmoothing, SpeedSmoothing(window: 15, staleAfter: 10, minimumMeters: 30))
    }

    func testAModuleWithoutOwnRecordingUsesTheStandard() {
        let rowing = RowingTestModule()

        XCTAssertEqual(rowing.recording, .standard)
        XCTAssertEqual(SportRecording.standard.locations, [.outdoor, .indoor])
        XCTAssertEqual(SportRecording.standard.primaryField, .speed)
        XCTAssertEqual(SportRecording.standard.secondaryFields, [.distanceKilometers])
    }

    func testLocationsSayWhatTheWatchRecords() {
        XCTAssertNil(RecordingLocation.pool.isIndoor)
        XCTAssertTrue(RecordingLocation.pool.usesLapLength)
        XCTAssertTrue(RecordingLocation.pool.usesWaterLock)
        XCTAssertFalse(RecordingLocation.pool.recordsRoute)

        XCTAssertEqual(RecordingLocation.openWater.isIndoor, false)
        XCTAssertFalse(RecordingLocation.openWater.usesLapLength)
        XCTAssertTrue(RecordingLocation.openWater.usesWaterLock)
        XCTAssertTrue(RecordingLocation.openWater.recordsRoute)

        XCTAssertEqual(RecordingLocation.outdoor.isIndoor, false)
        XCTAssertTrue(RecordingLocation.outdoor.recordsRoute)
        XCTAssertFalse(RecordingLocation.outdoor.usesWaterLock)
        XCTAssertNil(RecordingLocation.outdoor.swimmingLocationRawValue)

        XCTAssertEqual(RecordingLocation.indoor.isIndoor, true)
        XCTAssertFalse(RecordingLocation.indoor.recordsRoute)

        for location in [RecordingLocation.pool, .openWater, .outdoor, .indoor] {
            XCTAssertFalse(location.displayName.isEmpty, location.id)
            XCTAssertFalse(location.symbolName.isEmpty, location.id)
            XCTAssertTrue(SportID(rawValue: location.id).isWellFormed, location.id)
        }
    }

    func testLocationLookupFallsBackToTheFirst() {
        let recording = SportRecording.standard

        XCTAssertEqual(recording.location(id: "indoor"), .indoor)
        XCTAssertEqual(recording.location(id: "pool"), .outdoor, "Fremder Ort: der erste")
        XCTAssertEqual(recording.location(id: nil), .outdoor)

        let empty = SportRecording(locations: [], primaryField: .speed, secondaryFields: [], speedSmoothing: SportRecording.standard.speedSmoothing)
        XCTAssertNil(empty.location(id: "outdoor"))
    }

    func testSpeedSmoothingBuildsItsTracker() {
        let smoothing = SpeedSmoothing(window: 15, staleAfter: 10, minimumMeters: 30)

        let tracker = smoothing.makeTracker()

        XCTAssertEqual(tracker, SpeedTracker(window: 15, staleAfter: 10, minimumMeters: 30))
    }

    // MARK: - Prüfung in der Registry

    func testEveryRealRecordingIsValid() {
        for module in SportRegistry.standard.modules {
            XCTAssertTrue(module.recording.isValid, "\(module.id)")
        }
        XCTAssertTrue(SportRecording.standard.isValid)
    }

    func testInvalidRecordingsAreRejected() {
        let smoothing = SportRecording.standard.speedSmoothing
        func recording(_ locations: [RecordingLocation]) -> SportRecording {
            SportRecording(locations: locations, primaryField: .speed, secondaryFields: [], speedSmoothing: smoothing)
        }
        let invalid: [(String, SportRecording)] = [
            ("ohne Ort", recording([])),
            ("Kennung", recording([RecordingLocation(id: "Im Haus", displayName: "Drinnen", symbolName: "house", isIndoor: true)])),
            ("ohne Namen", recording([RecordingLocation(id: "indoor", displayName: "", symbolName: "house", isIndoor: true)])),
            ("doppelt", recording([.indoor, .indoor]))
        ]
        for (message, recording) in invalid {
            XCTAssertFalse(recording.isValid, message)
            XCTAssertThrowsError(try SportRegistry(modules: [RecordingStubModule(recording: recording)]), message) { error in
                XCTAssertEqual(error as? SportRegistry.Problem, .invalidRecording("kayak"), message)
            }
        }
        XCTAssertNoThrow(try SportRegistry(modules: [RecordingStubModule(recording: recording([.outdoor, .indoor]))]))
    }

    // MARK: - Konfiguration für HealthKit

    func testPoolSwimmingConfiguresLapLengthAndLeavesIndoorOpen() throws {
        let swim = try module(.swim)

        let configuration = swim.workoutConfiguration(at: .pool, lapLengthMeters: 50)

        XCTAssertEqual(configuration.activityType, .swimming)
        XCTAssertEqual(configuration.swimmingLocationType, .pool)
        XCTAssertEqual(configuration.locationType, .unknown)
        XCTAssertEqual(configuration.lapLength?.doubleValue(for: .meter()), 50)
        XCTAssertEqual(swim.lapLength(at: .pool, lapLengthMeters: 50), 50)
    }

    func testLapLengthIsClampedToWhatTheWatchCounts() throws {
        let swim = try module(.swim)

        XCTAssertEqual(swim.workoutConfiguration(at: .pool, lapLengthMeters: 500).lapLength?.doubleValue(for: .meter()), 100)
        XCTAssertEqual(swim.lapLength(at: .pool, lapLengthMeters: 3), 10)
    }

    func testOpenWaterIsOutdoorsWithoutLapLength() throws {
        let swim = try module(.swim)

        let configuration = swim.workoutConfiguration(at: .openWater, lapLengthMeters: 25)

        XCTAssertEqual(configuration.activityType, .swimming)
        XCTAssertEqual(configuration.swimmingLocationType, .openWater)
        XCTAssertEqual(configuration.locationType, .outdoor)
        XCTAssertNil(configuration.lapLength)
        XCTAssertNil(swim.lapLength(at: .openWater, lapLengthMeters: 25))
    }

    func testRunningAndCyclingConfigureTheirActivityAndLocation() throws {
        let run = try module(.run)
        let bike = try module(.bike)

        let outdoorRun = run.workoutConfiguration(at: .outdoor, lapLengthMeters: 25)
        XCTAssertEqual(outdoorRun.activityType, .running)
        XCTAssertEqual(outdoorRun.locationType, .outdoor)
        XCTAssertEqual(outdoorRun.swimmingLocationType, .unknown)
        XCTAssertNil(outdoorRun.lapLength)

        let indoorRide = bike.workoutConfiguration(at: .indoor, lapLengthMeters: 25)
        XCTAssertEqual(indoorRide.activityType, .cycling)
        XCTAssertEqual(indoorRide.locationType, .indoor)
        XCTAssertNil(bike.lapLength(at: .indoor, lapLengthMeters: 25))
    }

    func testAModuleWithoutActivityTypeRecordsAsOther() {
        let module = RecordingStubModule(recording: .standard, activityTypes: [])

        XCTAssertEqual(module.workoutConfiguration(at: .outdoor, lapLengthMeters: 25).activityType, .other)
        XCTAssertEqual(RowingTestModule().workoutConfiguration(at: .indoor, lapLengthMeters: 25).activityType, .rowing)
    }

    // MARK: - Metadaten

    func testPoolMetadataCarriesLapLengthAndSwimmingLocation() throws {
        let metadata = try module(.swim).workoutMetadata(at: .pool, lapLengthMeters: 25)

        XCTAssertEqual((metadata[HKMetadataKeyLapLength] as? HKQuantity)?.doubleValue(for: .meter()), 25)
        XCTAssertEqual(metadata[HKMetadataKeySwimmingLocationType] as? NSNumber, NSNumber(value: HKWorkoutSwimmingLocationType.pool.rawValue))
        XCTAssertNil(metadata[HKMetadataKeyIndoorWorkout])
        XCTAssertEqual(metadata.count, 2)
    }

    func testOpenWaterAndIndoorMetadata() throws {
        let openWater = try module(.swim).workoutMetadata(at: .openWater, lapLengthMeters: 25)
        XCTAssertNil(openWater[HKMetadataKeyLapLength])
        XCTAssertEqual(openWater[HKMetadataKeySwimmingLocationType] as? NSNumber, NSNumber(value: HKWorkoutSwimmingLocationType.openWater.rawValue))
        XCTAssertEqual(openWater[HKMetadataKeyIndoorWorkout] as? NSNumber, NSNumber(value: false))

        let treadmill = try module(.run).workoutMetadata(at: .indoor, lapLengthMeters: 25)
        XCTAssertEqual(treadmill.count, 1)
        XCTAssertEqual(treadmill[HKMetadataKeyIndoorWorkout] as? NSNumber, NSNumber(value: true))
    }

    // MARK: - Freigaben

    func testWorkoutShareTypesCoverRouteAndAllSports() throws {
        let types = SportRegistry.standard.workoutShareTypes

        XCTAssertTrue(types.contains(HKObjectType.workoutType()))
        XCTAssertTrue(types.contains(HKSeriesType.workoutRoute()))
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate, .activeEnergyBurned, .distanceSwimming, .swimmingStrokeCount, .distanceCycling, .distanceWalkingRunning, .runningPower
        ]
        for identifier in identifiers {
            let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: identifier))
            XCTAssertTrue(types.contains(type), identifier.rawValue)
        }
        // Ein zusätzliches Modul bringt seine Messwerte mit.
        let withRowing = try SportRegistry(modules: [SwimModule(), RowingTestModule()])
        XCTAssertTrue(withRowing.workoutShareTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningPower))))
        XCTAssertFalse(withRowing.workoutShareTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .distanceCycling))))
    }
}

/// Eine Sportart nur mit eigener Aufzeichnung, für die Prüfung in der Registry.
private struct RecordingStubModule: SportModule {
    let id: SportID = "kayak"
    let displayName = "Kajak"
    let symbolName = "figure.water.fitness"
    let measures: Set<StepMeasure> = [.duration]
    let targets: Set<StepTarget> = [.perceivedEffort]
    let health: SportHealthMapping
    let loadFactor = 0.8
    let goalSpeedRange: ClosedRange<Double> = 0.5...5
    let planUnit = PlanUnit.minutes
    let typicalSpeedMetersPerSecond = 2.0
    let recording: SportRecording

    init(recording: SportRecording, activityTypes: [HKWorkoutActivityType] = [.paddleSports]) {
        self.recording = recording
        self.health = SportHealthMapping(activityTypes: activityTypes, distance: nil)
    }
}
