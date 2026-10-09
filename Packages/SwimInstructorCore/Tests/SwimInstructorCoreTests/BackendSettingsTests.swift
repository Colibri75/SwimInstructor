import XCTest
@testable import SwimInstructorCore

@MainActor
final class BackendSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "BackendSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsToProductionServerWithoutToken() {
        let settings = BackendSettings(defaults: defaults, secrets: InMemorySecretStore())

        XCTAssertEqual(settings.baseURL, BackendConfiguration.defaultBaseURL)
        XCTAssertFalse(settings.hasToken)
        XCTAssertNil(settings.configuration)
    }

    func testSaveStoresTokenAndNormalizedURL() throws {
        let secrets = InMemorySecretStore()
        let settings = BackendSettings(defaults: defaults, secrets: secrets)

        try settings.save(baseURLString: "  https://plan.example.test/  ", token: " abc123 ")

        XCTAssertTrue(settings.hasToken)
        XCTAssertEqual(secrets.read(), "abc123")
        XCTAssertEqual(settings.configuration, BackendConfiguration(baseURL: URL(string: "https://plan.example.test")!, token: "abc123"))
        // Überlebt einen Neustart der App.
        let reloaded = BackendSettings(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reloaded.baseURL.absoluteString, "https://plan.example.test")
        XCTAssertTrue(reloaded.hasToken)
    }

    func testEmptyTokenKeepsExistingOne() throws {
        let secrets = InMemorySecretStore(value: "alt")
        let settings = BackendSettings(defaults: defaults, secrets: secrets)

        try settings.save(baseURLString: "https://neu.example.test", token: "")

        XCTAssertEqual(settings.configuration?.token, "alt")
        XCTAssertEqual(settings.baseURL.absoluteString, "https://neu.example.test")
    }

    func testRejectsMissingTokenAndInsecureURL() {
        let settings = BackendSettings(defaults: defaults, secrets: InMemorySecretStore())

        XCTAssertThrowsError(try settings.save(baseURLString: "https://ok.example.test", token: nil)) {
            XCTAssertEqual($0 as? BackendSettingsError, .missingToken)
        }
        XCTAssertThrowsError(try settings.save(baseURLString: "http://unsicher.example.test", token: "x")) {
            XCTAssertEqual($0 as? BackendSettingsError, .invalidURL)
        }
        XCTAssertThrowsError(try settings.save(baseURLString: "kein url", token: "x")) {
            XCTAssertEqual($0 as? BackendSettingsError, .invalidURL)
        }
        XCTAssertFalse(settings.hasToken)
    }

    func testRemoveToken() throws {
        let settings = BackendSettings(defaults: defaults, secrets: InMemorySecretStore(value: "abc"))
        XCTAssertTrue(settings.hasToken)

        try settings.removeToken()

        XCTAssertFalse(settings.hasToken)
        XCTAssertNil(settings.configuration)
    }

    func testSignInWithAppleStoresTokenAndName() throws {
        let secrets = InMemorySecretStore()
        let settings = BackendSettings(defaults: defaults, secrets: secrets)

        try settings.signIn(AccountSession(token: "server-token", userID: "a-1", name: "Anna"))

        XCTAssertTrue(settings.hasToken)
        XCTAssertTrue(settings.isSignedInWithApple)
        XCTAssertEqual(settings.accountName, "Anna")
        // Dieselbe Stelle wie ein Token von Hand: alle Aufrufe nutzen ihn.
        XCTAssertEqual(settings.configuration?.token, "server-token")
        let reloaded = BackendSettings(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reloaded.accountName, "Anna")
    }

    func testSignOutRemovesTokenAndName() throws {
        let secrets = InMemorySecretStore()
        let settings = BackendSettings(defaults: defaults, secrets: secrets)
        try settings.signIn(AccountSession(token: "t", userID: "a-1", name: "Anna"))

        try settings.signOut()

        XCTAssertFalse(settings.hasToken)
        XCTAssertNil(settings.accountName)
        XCTAssertFalse(settings.isSignedInWithApple)
        XCTAssertNil(BackendSettings(defaults: defaults, secrets: secrets).accountName)
    }

    func testManualTokenReplacesAppleAccount() throws {
        let settings = BackendSettings(defaults: defaults, secrets: InMemorySecretStore())
        try settings.signIn(AccountSession(token: "t", userID: "a-1", name: "Anna"))

        try settings.save(baseURLString: "https://plan.example.test", token: "von-hand")

        XCTAssertNil(settings.accountName)
        XCTAssertEqual(settings.configuration?.token, "von-hand")
    }

    func testSaveBaseURLWithoutToken() throws {
        let settings = BackendSettings(defaults: defaults, secrets: InMemorySecretStore())

        try settings.saveBaseURL("https://eigen.example.test/")

        XCTAssertEqual(settings.baseURL.absoluteString, "https://eigen.example.test")
        XCTAssertFalse(settings.hasToken)
        XCTAssertThrowsError(try settings.saveBaseURL("http://unsicher.example.test"))
    }
}
