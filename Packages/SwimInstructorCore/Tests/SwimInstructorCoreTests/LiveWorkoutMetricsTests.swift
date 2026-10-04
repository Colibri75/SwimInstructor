import XCTest
@testable import SwimInstructorCore

/// Live-Werte der Watch für jede Sportart: Texte der Anzeige, aktuelle Geschwindigkeit und Höhenmeter.
final class LiveWorkoutMetricsTests: XCTestCase {
    // MARK: - Werte der Einheit

    func testAverageSpeedNeedsDistanceAndTime() {
        XCTAssertNil(LiveWorkoutMetrics.zero.averageSpeed)
        XCTAssertNil(LiveWorkoutMetrics(elapsed: 100).averageSpeed)
        XCTAssertNil(LiveWorkoutMetrics(distanceMeters: 100).averageSpeed)
        XCTAssertEqual(LiveWorkoutMetrics(elapsed: 100, distanceMeters: 250).averageSpeed, 2.5)
    }

    func testProgressMetersCountLapsInThePool() {
        let metrics = LiveWorkoutMetrics(distanceMeters: 75, laps: 4)

        XCTAssertEqual(metrics.progressMeters(lapLengthMeters: 25), 100, "Strecke aus Health hinkt hinterher")
        XCTAssertEqual(metrics.progressMeters(lapLengthMeters: nil), 75)
        XCTAssertEqual(metrics.progressMeters(lapLengthMeters: 0), 75)
        XCTAssertEqual(LiveWorkoutMetrics(distanceMeters: 120, laps: 4).progressMeters(lapLengthMeters: 25), 120)
    }

    // MARK: - Texte

    func testPaceAndSpeedFromTheCurrentSpeed() {
        XCTAssertEqual(LiveFieldFormatting.value(.pacePerHundredMeters, metrics: LiveWorkoutMetrics(currentSpeed: 100.0 / 112)), "1:52")
        XCTAssertEqual(LiveFieldFormatting.value(.pacePerKilometer, metrics: LiveWorkoutMetrics(currentSpeed: 1000.0 / 310)), "5:10")
        XCTAssertEqual(LiveFieldFormatting.value(.speed, metrics: LiveWorkoutMetrics(currentSpeed: 28.4 / 3.6)), "28,4")
    }

    func testNoPaceOrSpeedWithoutAUsableSpeed() {
        for speed in [nil, 0.1, 0, -1, Double.infinity] as [Double?] {
            let metrics = LiveWorkoutMetrics(currentSpeed: speed)
            XCTAssertNil(LiveFieldFormatting.value(.pacePerHundredMeters, metrics: metrics), "\(String(describing: speed))")
            XCTAssertNil(LiveFieldFormatting.value(.pacePerKilometer, metrics: metrics), "\(String(describing: speed))")
        }
        for speed in [nil, 0, -1, Double.infinity] as [Double?] {
            XCTAssertNil(LiveFieldFormatting.value(.speed, metrics: LiveWorkoutMetrics(currentSpeed: speed)), "\(String(describing: speed))")
        }
    }

    func testDistanceInMetersOrKilometers() {
        let metrics = LiveWorkoutMetrics(distanceMeters: 5234)

        XCTAssertEqual(LiveFieldFormatting.value(.distanceMeters, metrics: metrics), "5.234")
        XCTAssertEqual(LiveFieldFormatting.value(.distanceKilometers, metrics: metrics), "5,23")
        XCTAssertEqual(LiveFieldFormatting.value(.distanceMeters, metrics: .zero), "0")
        XCTAssertEqual(LiveFieldFormatting.value(.distanceKilometers, metrics: .zero), "0,00")
    }

    func testValuesOnlySomeSportsMeasureAreLeftOutWithoutData() {
        let none = LiveWorkoutMetrics.zero
        for field in [LiveField.laps, .strokes, .power, .cadence, .elevationGain] {
            XCTAssertNil(LiveFieldFormatting.value(field, metrics: none), field.rawValue)
        }

        let measured = LiveWorkoutMetrics(
            laps: 18,
            elevationGainMeters: 123.6,
            values: [.strokes: 245, .averagePower: 212.4, .averageCadence: 88]
        )
        XCTAssertEqual(LiveFieldFormatting.value(.laps, metrics: measured), "18")
        XCTAssertEqual(LiveFieldFormatting.value(.strokes, metrics: measured), "245")
        XCTAssertEqual(LiveFieldFormatting.value(.power, metrics: measured), "212")
        XCTAssertEqual(LiveFieldFormatting.value(.cadence, metrics: measured), "88")
        XCTAssertEqual(LiveFieldFormatting.value(.elevationGain, metrics: measured), "124")

        let tiny = LiveWorkoutMetrics(values: [.averagePower: 0.4, .averageCadence: .nan])
        XCTAssertNil(LiveFieldFormatting.value(.power, metrics: tiny))
        XCTAssertNil(LiveFieldFormatting.value(.cadence, metrics: tiny))
    }

    func testEveryFieldHasAUnit() {
        let units = LiveField.allCases.map(LiveFieldFormatting.unit)

        XCTAssertEqual(units, ["/100 m", "/km", "km/h", "m", "km", "Bahnen", "Züge", "W", "U/min", "Hm"])
    }

    func testTextJoinsValueAndUnit() {
        let metrics = LiveWorkoutMetrics(currentSpeed: 100.0 / 112, values: [.averagePower: 245])

        XCTAssertEqual(LiveFieldFormatting.text(.pacePerHundredMeters, metrics: metrics), "1:52 /100 m")
        XCTAssertEqual(LiveFieldFormatting.text(.power, metrics: metrics), "245 W")
        XCTAssertNil(LiveFieldFormatting.text(.cadence, metrics: metrics))
    }

    func testAverageOfTheWholeSessionInTheFormatOfTheMainValue() {
        XCTAssertEqual(LiveFieldFormatting.average(.pacePerHundredMeters, metrics: LiveWorkoutMetrics(elapsed: 2500, distanceMeters: 2000)), "2:05 /100 m")
        XCTAssertEqual(LiveFieldFormatting.average(.pacePerKilometer, metrics: LiveWorkoutMetrics(elapsed: 3400, distanceMeters: 10000)), "5:40 /km")
        XCTAssertEqual(LiveFieldFormatting.average(.speed, metrics: LiveWorkoutMetrics(elapsed: 3600, distanceMeters: 26100)), "26,1 km/h")
        // Die aktuelle Geschwindigkeit zählt für den Schnitt nicht.
        XCTAssertNil(LiveFieldFormatting.average(.speed, metrics: LiveWorkoutMetrics(currentSpeed: 7)))
        XCTAssertNil(LiveFieldFormatting.average(.distanceKilometers, metrics: LiveWorkoutMetrics(elapsed: 3600, distanceMeters: 26100)))
    }

    // MARK: - Aktuelle Geschwindigkeit

    func testSpeedNeedsEnoughDistance() {
        var tracker = SpeedTracker(window: 30, staleAfter: 15, minimumMeters: 20)
        XCTAssertNil(tracker.speed(atElapsed: 0))

        tracker.record(elapsed: 5, distanceMeters: 15)
        XCTAssertNil(tracker.speed(atElapsed: 5))

        tracker.record(elapsed: 10, distanceMeters: 30)
        XCTAssertEqual(tracker.speed(atElapsed: 10), 3)
    }

    func testSpeedGoesStaleWithoutNewDistance() {
        var tracker = SpeedTracker(window: 30, staleAfter: 15, minimumMeters: 20)
        tracker.record(elapsed: 10, distanceMeters: 30)

        // Stehen an der Ampel: dieselbe Strecke zählt nicht als neue Meldung.
        tracker.record(elapsed: 20, distanceMeters: 30)
        tracker.record(elapsed: 5, distanceMeters: 40)

        XCTAssertEqual(tracker.speed(atElapsed: 25), 3)
        XCTAssertNil(tracker.speed(atElapsed: 26))
    }

    func testSpeedFollowsTheWindow() {
        var tracker = SpeedTracker(window: 30, staleAfter: 15, minimumMeters: 20)
        // Eine Minute mit 3 m/s, dann eine halbe mit 2 m/s.
        for second in stride(from: 5, through: 60, by: 5) {
            tracker.record(elapsed: TimeInterval(second), distanceMeters: Double(second) * 3)
        }
        for second in stride(from: 65, through: 90, by: 5) {
            tracker.record(elapsed: TimeInterval(second), distanceMeters: 180 + Double(second - 60) * 2)
        }

        XCTAssertEqual(try XCTUnwrap(tracker.speed(atElapsed: 90)), 2, accuracy: 0.0001)
    }

    func testALongGapUsesThePreviousReport() {
        var tracker = SpeedTracker(window: 30, staleAfter: 15, minimumMeters: 20)

        tracker.record(elapsed: 100, distanceMeters: 300)

        XCTAssertEqual(tracker.speed(atElapsed: 100), 3)
    }

    func testPoolLapsGiveASteadyPace() throws {
        let smoothing = try XCTUnwrap(SportRegistry.standard.module(for: .swim)).recording.speedSmoothing
        var tracker = smoothing.makeTracker()

        for lap in 1...4 {
            tracker.record(elapsed: TimeInterval(lap * 30), distanceMeters: Double(lap * 25))
        }

        XCTAssertEqual(LiveFieldFormatting.value(.pacePerHundredMeters, metrics: LiveWorkoutMetrics(currentSpeed: tracker.speed(atElapsed: 125))), "2:00")
    }

    // MARK: - Höhenmeter

    func testElevationGainIgnoresSmallJumpsAndBadReadings() {
        var tracker = ElevationGainTracker()

        tracker.record(altitude: 100, verticalAccuracy: 5)
        tracker.record(altitude: 102, verticalAccuracy: 5)
        XCTAssertEqual(tracker.gainMeters, 0)

        tracker.record(altitude: 104, verticalAccuracy: 5)
        XCTAssertEqual(tracker.gainMeters, 4)

        // Bergab setzt den Bezug neu, ohne abzuziehen.
        tracker.record(altitude: 101, verticalAccuracy: 5)
        tracker.record(altitude: 106, verticalAccuracy: 5)
        XCTAssertEqual(tracker.gainMeters, 9)

        // Ungenaue oder ungültige Höhen zählen nicht.
        tracker.record(altitude: 200, verticalAccuracy: 25)
        tracker.record(altitude: 200, verticalAccuracy: -1)
        tracker.record(altitude: .nan, verticalAccuracy: 5)
        XCTAssertEqual(tracker.gainMeters, 9)

        tracker.record(altitude: 108, verticalAccuracy: 5)
        XCTAssertEqual(tracker.gainMeters, 9)
    }
}
