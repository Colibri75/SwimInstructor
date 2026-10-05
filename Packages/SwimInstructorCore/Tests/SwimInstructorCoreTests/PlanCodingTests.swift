import XCTest
@testable import SwimInstructorCore

final class PlanCodingTests: XCTestCase {
    private struct Stamp: Codable, Equatable {
        let generatedAt: Date
        let sessionType: SessionType
    }

    func testDecodesTimestampsWithAndWithoutMilliseconds() throws {
        let withMillis = try PlanCoding.jsonDecoder().decode(Stamp.self, from: Data(#"{"generated_at":"2026-09-30T10:00:00.123Z","session_type":"rest"}"#.utf8))
        let plain = try PlanCoding.jsonDecoder().decode(Stamp.self, from: Data(#"{"generated_at":"2026-09-30T10:00:00Z","session_type":"rest"}"#.utf8))

        XCTAssertEqual(withMillis.generatedAt.timeIntervalSince(plain.generatedAt), 0.123, accuracy: 0.001)
        XCTAssertEqual(plain.generatedAt, ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z"))
    }

    func testRejectsNonDates() {
        XCTAssertThrowsError(try PlanCoding.jsonDecoder().decode(Stamp.self, from: Data(#"{"generated_at":"gestern","session_type":"rest"}"#.utf8)))
    }

    func testEncoderAndDecoderRoundTrip() throws {
        let original = Stamp(generatedAt: TestFixtures.now, sessionType: .threshold)

        let data = try PlanCoding.jsonEncoder().encode(original)

        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"generated_at\""))
        XCTAssertEqual(try PlanCoding.jsonDecoder().decode(Stamp.self, from: data), original)
    }

    func testUnknownEnumValuesFallBackToUnknown() throws {
        let json = #"[{"generated_at":"2026-09-30T10:00:00Z","session_type":"brick"}]"#

        let stamps = try PlanCoding.jsonDecoder().decode([Stamp].self, from: Data(json.utf8))

        XCTAssertEqual(stamps.first?.sessionType, .unknown)
        XCTAssertEqual(try PlanCoding.jsonDecoder().decode(PlanIntensity.self, from: Data(#""extreme""#.utf8)), .unknown)
        XCTAssertEqual(try PlanCoding.jsonDecoder().decode(PlanSource.self, from: Data(#""magic""#.utf8)), .unknown)
    }
}
