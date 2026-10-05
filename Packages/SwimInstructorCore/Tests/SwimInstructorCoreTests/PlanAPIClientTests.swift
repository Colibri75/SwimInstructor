import XCTest
@testable import SwimInstructorCore

/// Verbindung, Fehlertexte und Hilfen des Clients. Die Aufrufe der Planung (Tag, sieben Tage, Gesamtplan) prüft
/// `PlanV2ClientTests`.
final class PlanAPIClientTests: XCTestCase {
    private let configuration = BackendConfiguration(baseURL: URL(string: "https://example.test")!, token: "geheim")

    func testOverlongWishIsCutToTheLimit() {
        let long = String(repeating: "x", count: DailyWish.maxLength + 50)

        XCTAssertEqual(PlanAPIClient.cleaned(long)?.count, DailyWish.maxLength)
        XCTAssertNil(PlanAPIClient.cleaned(nil))
        XCTAssertNil(PlanAPIClient.cleaned("   \n"))
    }

    func testNetworkErrorsAreDescribedInGerman() {
        XCTAssertTrue(PlanAPIClient.describe(URLError(.cannotFindHost)).contains("auflösen"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.dnsLookupFailed)).contains("DNS"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.notConnectedToInternet)).contains("keine Internetverbindung"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.timedOut)).contains("rechtzeitig"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.cannotConnectToHost)).contains("nicht erreichbar"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.serverCertificateUntrusted)).contains("Zertifikat"))
        // Alles andere behält den Systemtext.
        XCTAssertEqual(PlanAPIClient.describe(URLError(.badURL)), URLError(.badURL).localizedDescription)
        XCTAssertEqual(PlanAPIClient.describe(TestError(message: "sonst")), "sonst")
    }

    func testHostLookupFailureReachesTheUserAsGermanText() async {
        let client = PlanAPIClient(configuration: configuration, transport: StubTransport(error: URLError(.cannotFindHost)))
        do {
            try await client.checkConnection()
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("Keine Verbindung zum Server: Der Servername lässt sich nicht auflösen"))
        }
    }

    func testNetworkFailure() async {
        let client = PlanAPIClient(
            configuration: configuration,
            transport: StubTransport(error: URLError(.notConnectedToInternet))
        )
        do {
            try await client.checkConnection()
            XCTFail("Fehler erwartet")
        } catch let error as PlanAPIError {
            guard case .network = error else { return XCTFail("falscher Fehler: \(error)") }
        } catch {
            XCTFail("falscher Fehlertyp: \(error)")
        }
    }

    func testCheckConnectionUsesStatusRoute() async throws {
        let transport = StubTransport(status: 200, body: #"{"status":"authenticated"}"#)
        try await PlanAPIClient(configuration: configuration, transport: transport).checkConnection()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/status")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
    }

    func testCheckConnectionRejectedToken() async {
        let client = PlanAPIClient(configuration: configuration, transport: StubTransport(status: 401, body: "{}"))
        do {
            try await client.checkConnection()
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? PlanAPIError, .unauthorized)
        }
    }

    func testOtherStatusIsAServerError() async {
        let client = PlanAPIClient(configuration: configuration, transport: StubTransport(status: 500, body: "{}"))
        do {
            try await client.checkConnection()
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? PlanAPIError, .server(status: 500))
        }
    }

    func testPlanUnavailableTextNamesTheReason() {
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: "budget_exceeded").errorDescription?.contains("Tageslimit") == true)
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: "not_configured").errorDescription?.contains("nicht eingerichtet") == true)
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: "timeout").errorDescription?.contains("nicht erreichbar") == true)
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: nil).errorDescription?.hasPrefix("Kein neuer Plan") == true)
    }
}
