import XCTest
@testable import SwimInstructorCore

final class AccountClientTests: XCTestCase {
    private let baseURL = URL(string: "https://example.test")!

    func testSignInWithAppleSendsIdentityTokenAndReturnsSession() async throws {
        let transport = StubTransport(status: 200, body: #"{"token":"server-token","user":{"id":"a-123456789abc","name":"Anna"}}"#)

        let session = try await AccountClient(baseURL: baseURL, transport: transport)
            .signInWithApple(identityToken: "apple.jwt.token", name: "  Anna  ")

        XCTAssertEqual(session, AccountSession(token: "server-token", userID: "a-123456789abc", name: "Anna"))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/auth/apple")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["identityToken"] as? String, "apple.jwt.token")
        XCTAssertEqual(json["name"] as? String, "Anna")
    }

    func testEmptyNameIsLeftOut() async throws {
        let transport = StubTransport(status: 200, body: #"{"token":"t","user":{"id":"a-1","name":"Apple-ID"}}"#)

        _ = try await AccountClient(baseURL: baseURL, transport: transport).signInWithApple(identityToken: "x", name: " ")

        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["name"])
    }

    func testSignInErrorsMapToAccountErrors() async {
        let cases: [(Int, AccountError)] = [
            (401, .invalidIdentity),
            (400, .invalidIdentity),
            (403, .signupClosed),
            (429, .rateLimited),
            (503, .appleUnavailable),
            (500, .server(status: 500))
        ]
        for (status, expected) in cases {
            let client = AccountClient(baseURL: baseURL, transport: StubTransport(status: status, body: "{}"))
            do {
                _ = try await client.signInWithApple(identityToken: "x", name: nil)
                XCTFail("Fehler erwartet für \(status)")
            } catch {
                XCTAssertEqual(error as? AccountError, expected, "Status \(status)")
            }
        }
    }

    func testSignInRejectsUnreadableAnswer() async {
        let client = AccountClient(baseURL: baseURL, transport: StubTransport(status: 200, body: #"{"token":""}"#))
        do {
            _ = try await client.signInWithApple(identityToken: "x", name: nil)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? AccountError, .invalidResponse)
        }
    }

    func testNetworkErrorIsDescribed() async {
        let client = AccountClient(baseURL: baseURL, transport: StubTransport(error: URLError(.notConnectedToInternet)))
        do {
            _ = try await client.signInWithApple(identityToken: "x", name: nil)
            XCTFail("Fehler erwartet")
        } catch let error as AccountError {
            guard case .network(let message) = error else { return XCTFail("falscher Fehler: \(error)") }
            XCTAssertTrue(message.contains("keine Internetverbindung"))
        } catch {
            XCTFail("falscher Fehlertyp: \(error)")
        }
    }

    func testDeleteAccountUsesBearerToken() async throws {
        let transport = StubTransport(status: 204, body: "")

        try await AccountClient(baseURL: baseURL, transport: transport).deleteAccount(token: "geheim")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/account")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
    }

    func testDeleteAccountErrors() async {
        let cases: [(Int, AccountError)] = [(401, .unauthorized), (409, .ownerCannotBeDeleted), (500, .server(status: 500))]
        for (status, expected) in cases {
            let client = AccountClient(baseURL: baseURL, transport: StubTransport(status: status, body: "{}"))
            do {
                try await client.deleteAccount(token: "t")
                XCTFail("Fehler erwartet für \(status)")
            } catch {
                XCTAssertEqual(error as? AccountError, expected, "Status \(status)")
            }
        }
    }

    func testErrorTextsAreGerman() {
        XCTAssertTrue(AccountError.signupClosed.errorDescription?.contains("freigeschaltet") == true)
        XCTAssertTrue(AccountError.ownerCannotBeDeleted.errorDescription?.contains("Besitzer") == true)
    }
}
