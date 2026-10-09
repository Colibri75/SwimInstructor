import XCTest
@testable import SwimInstructorCore

final class AIDataConsentTests: XCTestCase {
    private let configuration = BackendConfiguration(baseURL: URL(string: "https://example.test")!, token: "geheim")

    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "AIDataConsentTests-\(UUID().uuidString)"))
    }

    // MARK: - Store

    func testNoConsentUntilGrantedThenStoredWithVersionAndDate() throws {
        let defaults = try defaults()
        let store = UserDefaultsAIDataConsentStore(defaults: defaults)
        XCTAssertNil(store.record)
        XCTAssertFalse(store.isGranted)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.grant(now: now)

        XCTAssertTrue(store.isGranted)
        XCTAssertEqual(store.record, AIDataConsentRecord(version: UserDefaultsAIDataConsentStore.currentVersion, grantedAt: now))
        // Ein neuer Store auf denselben UserDefaults kennt sie (App-Neustart).
        XCTAssertTrue(UserDefaultsAIDataConsentStore(defaults: defaults).isGranted)
    }

    func testWithdrawRemovesTheConsent() throws {
        let store = UserDefaultsAIDataConsentStore(defaults: try defaults())
        store.grant(now: Date())
        store.withdraw()

        XCTAssertNil(store.record)
        XCTAssertFalse(store.isGranted)
    }

    func testConsentToAnOlderVersionDoesNotCount() throws {
        let defaults = try defaults()
        defaults.set(UserDefaultsAIDataConsentStore.currentVersion - 1, forKey: UserDefaultsAIDataConsentStore.versionKey)
        defaults.set(1_700_000_000.0, forKey: UserDefaultsAIDataConsentStore.dateKey)
        let store = UserDefaultsAIDataConsentStore(defaults: defaults)

        XCTAssertFalse(store.isGranted)
    }

    // MARK: - Link

    func testPolicyLinkFollowsTheAppLanguage() {
        XCTAssertEqual(PrivacyPolicy.url(languageCode: "de").absoluteString, "https://swiminstructor.kellner.v6.rocks/datenschutz")
        XCTAssertEqual(PrivacyPolicy.url(languageCode: "en").absoluteString, "https://swiminstructor.kellner.v6.rocks/privacy")
        XCTAssertEqual(PrivacyPolicy.url(languageCode: "ja").absoluteString, "https://swiminstructor.kellner.v6.rocks/privacy")
    }

    // MARK: - Oberfläche

    @MainActor
    func testBlockedRequestAsksOnceUntilDeclined() throws {
        let consent = AIDataConsent(store: UserDefaultsAIDataConsentStore(defaults: try defaults()))
        XCTAssertFalse(consent.isGranted)

        XCTAssertFalse(consent.allowsPlanRequest())
        XCTAssertTrue(consent.isPromptPresented)

        // "Nicht jetzt": bis zum nächsten Start keine neue Abfrage, Anfragen bleiben gesperrt.
        consent.decline()
        XCTAssertFalse(consent.isPromptPresented)
        XCTAssertFalse(consent.allowsPlanRequest())
        XCTAssertFalse(consent.isPromptPresented)

        consent.grant()
        XCTAssertTrue(consent.isGranted)
        XCTAssertNotNil(consent.record)
        XCTAssertTrue(consent.allowsPlanRequest())
    }

    @MainActor
    func testWithdrawStopsPlanRequestsWithoutAsking() throws {
        let consent = AIDataConsent(store: UserDefaultsAIDataConsentStore(defaults: try defaults()))
        consent.grant()
        consent.withdraw()

        XCTAssertNil(consent.record)
        XCTAssertFalse(consent.allowsPlanRequest())
        XCTAssertFalse(consent.isPromptPresented)
    }

    // MARK: - Client

    func testClientSendsNothingWithoutConsent() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        let client = PlanAPIClient(configuration: configuration, transport: transport, consentGate: PlanConsentGate(allows: { false }))

        do {
            _ = try await client.post(path: "v1/plan/today", body: Data("{}".utf8))
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? PlanAPIError, .consentRequired)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    @MainActor
    func testClientFromSettingsAsksTheConsent() async throws {
        let defaults = try defaults()
        let settings = BackendSettings(defaults: defaults, secrets: InMemorySecretStore(value: "geheim"))
        let consent = AIDataConsent(store: UserDefaultsAIDataConsentStore(defaults: defaults))
        let client = try XCTUnwrap(settings.planClient(consent: consent))

        do {
            _ = try await client.post(path: "v1/plan/today", body: Data("{}".utf8))
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? PlanAPIError, .consentRequired)
        }
        XCTAssertTrue(consent.isPromptPresented)
    }

    func testClientSendsWithConsent() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        let client = PlanAPIClient(configuration: configuration, transport: transport, consentGate: PlanConsentGate(allows: { true }))

        let (_, response) = try await client.post(path: "v1/plan/today", body: Data("{}".utf8))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testConsentErrorPointsToTheSettings() {
        XCTAssertTrue(PlanAPIError.consentRequired.localizedDescription.contains("Einstellungen › Datenschutz"))
    }
}
