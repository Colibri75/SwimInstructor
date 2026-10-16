import Foundation

/// Die Einwilligung in die Weitergabe von Trainings- und Gesundheitsdaten an den Server und an Anthropic, mit Version und
/// Zeitpunkt. Apple (Richtlinie 5.1.2(i)) und die DSGVO (Art. 9 Abs. 2 lit. a) verlangen sie vor der ersten Plananfrage.
public struct AIDataConsentRecord: Equatable, Sendable {
    public let version: Int
    public let grantedAt: Date

    public init(version: Int, grantedAt: Date) {
        self.version = version
        self.grantedAt = grantedAt
    }
}

public protocol AIDataConsentStoring {
    /// Die zuletzt erteilte Einwilligung, `nil` ohne oder nach dem Widerruf.
    var record: AIDataConsentRecord? { get }
    func grant(now: Date)
    func withdraw()
}

public extension AIDataConsentStoring {
    /// Gilt nur eine Einwilligung zur aktuellen Fassung: Ändert sich, was weitergeht, fragt die App erneut.
    var isGranted: Bool {
        guard let record else { return false }
        return record.version >= UserDefaultsAIDataConsentStore.currentVersion
    }
}

/// Speichert die Einwilligung in UserDefaults (nur auf diesem iPhone).
public struct UserDefaultsAIDataConsentStore: AIDataConsentStoring {
    /// Fassung des Einwilligungstexts und der Datenschutzerklärung. Erhöhen, wenn sich ändert, was an Server oder
    /// Anthropic geht (backend/src/privacy/texts.ts).
    public static let currentVersion = 1
    static let versionKey = "privacy.aiConsent.version"
    static let dateKey = "privacy.aiConsent.grantedAt"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var record: AIDataConsentRecord? {
        let version = defaults.integer(forKey: Self.versionKey)
        guard version > 0, defaults.object(forKey: Self.dateKey) != nil else { return nil }
        return AIDataConsentRecord(version: version, grantedAt: Date(timeIntervalSince1970: defaults.double(forKey: Self.dateKey)))
    }

    public func grant(now: Date) {
        defaults.set(Self.currentVersion, forKey: Self.versionKey)
        defaults.set(now.timeIntervalSince1970, forKey: Self.dateKey)
    }

    public func withdraw() {
        defaults.removeObject(forKey: Self.versionKey)
        defaults.removeObject(forKey: Self.dateKey)
    }
}

/// Die Datenschutzerklärung auf dem Server, auf Deutsch oder Englisch (alle anderen Sprachen).
public enum PrivacyPolicy {
    public static func url(languageCode: String = AppLocale.languageCode, baseURL: URL = BackendConfiguration.defaultBaseURL) -> URL {
        baseURL.appendingPathComponent(languageCode == "de" ? "datenschutz" : "privacy")
    }
}

/// Fragt vor jeder Plananfrage, ob sie Daten senden darf (`PlanAPIClient.post`). Die einzige Stelle, an der die App
/// Trainings- und Gesundheitsdaten an den Server schickt.
public struct PlanConsentGate: Sendable {
    let allows: @Sendable () async -> Bool

    public init(allows: @escaping @Sendable () async -> Bool) {
        self.allows = allows
    }

    /// Ohne Prüfung (Tests, Vorschauen).
    public static let always = PlanConsentGate(allows: { true })
}

/// Die Einwilligung für die Oberfläche: Einstellungen, Einrichtung und die Abfrage vor der ersten Plananfrage.
@MainActor
public final class AIDataConsent: ObservableObject {
    @Published public private(set) var record: AIDataConsentRecord?
    /// Soll die App jetzt um die Einwilligung bitten? Setzt eine blockierte Plananfrage.
    @Published public var isPromptPresented = false

    private let store: AIDataConsentStoring
    private let now: () -> Date
    /// Nach "Nicht jetzt" fragt die App bis zum nächsten Start nicht wieder von selbst.
    private var declinedThisLaunch = false

    public init(store: AIDataConsentStoring = UserDefaultsAIDataConsentStore(), now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.now = now
        self.record = store.record
    }

    public var isGranted: Bool { store.isGranted }

    public func grant() {
        store.grant(now: now())
        record = store.record
        isPromptPresented = false
    }

    /// "Nicht jetzt": keine Einwilligung, und bis zum nächsten Start keine erneute Abfrage.
    public func decline() {
        declinedThisLaunch = true
        isPromptPresented = false
    }

    /// Widerruf in den Einstellungen: Ab sofort gehen keine Plananfragen mehr an den Server.
    public func withdraw() {
        store.withdraw()
        record = nil
        declinedThisLaunch = true
    }

    /// Darf eine Plananfrage jetzt Daten senden? Ohne Einwilligung bittet die App darum (einmal je Start) und die
    /// Anfrage unterbleibt.
    public func allowsPlanRequest() -> Bool {
        if store.isGranted { return true }
        if !declinedThisLaunch { isPromptPresented = true }
        return false
    }

    /// Für `PlanAPIClient`: fragt auf dem Main Actor nach.
    public nonisolated var gate: PlanConsentGate {
        PlanConsentGate { [weak self] in
            guard let self else { return false }
            return await self.allowsPlanRequest()
        }
    }
}

public extension BackendSettings {
    /// Der Client für Pläne zur aktuellen Konfiguration, `nil` ohne Token. Sendet nur mit Einwilligung.
    func planClient(consent: AIDataConsent) -> PlanAPIClient? {
        configuration.map { PlanAPIClient(configuration: $0, consentGate: consent.gate) }
    }
}
