import Foundation
import Security

/// Ablage für das API-Token. Eigenes Protokoll, damit die Einstellungen ohne Schlüsselbund testbar sind.
public protocol SecretStoring {
    func read() -> String?
    func write(_ value: String) throws
    func delete() throws
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Speichert das Token im Schlüsselbund des Geräts (nur dieses Gerät, erst nach dem ersten Entsperren).
public struct KeychainSecretStore: SecretStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.kellner.SwimInstructor.backend", account: String = "api-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Nur für Tests und Vorschauen.
public final class InMemorySecretStore: SecretStoring {
    private var value: String?

    public init(value: String? = nil) {
        self.value = value
    }

    public func read() -> String? { value }
    public func write(_ value: String) throws { self.value = value }
    public func delete() throws { value = nil }
}

public enum BackendSettingsError: Error, Equatable, LocalizedError {
    case invalidURL
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "Die Server-Adresse muss mit https:// beginnen.")
        case .missingToken: return String(localized: "Bitte ein Token eingeben.")
        }
    }
}

/// Server-Adresse (UserDefaults) und Token (Schlüsselbund), wie sie in den Einstellungen stehen. Der Token kommt aus der
/// Anmeldung mit Apple (`signIn`) oder, für den Besitzer und eigene Server, von Hand (`save`).
@MainActor
public final class BackendSettings: ObservableObject {
    static let baseURLKey = "backend.baseURL"
    static let accountNameKey = "backend.accountName"

    @Published public private(set) var baseURL: URL
    @Published public private(set) var hasToken: Bool
    /// Name des mit Apple angemeldeten Kontos; `nil` ohne Anmeldung oder mit Token von Hand.
    @Published public private(set) var accountName: String?

    private let defaults: UserDefaults
    private let secrets: SecretStoring

    public init(defaults: UserDefaults = .standard, secrets: SecretStoring = KeychainSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
        self.baseURL = defaults.string(forKey: Self.baseURLKey).flatMap(Self.validatedURL)
            ?? BackendConfiguration.defaultBaseURL
        let hasToken = !(secrets.read() ?? "").isEmpty
        self.hasToken = hasToken
        self.accountName = hasToken ? defaults.string(forKey: Self.accountNameKey) : nil
    }

    /// Mit Apple angemeldet (und nicht nur mit einem Token von Hand).
    public var isSignedInWithApple: Bool { hasToken && accountName != nil }

    /// `nil`, solange kein Token hinterlegt ist.
    public var configuration: BackendConfiguration? {
        guard let token = secrets.read(), !token.isEmpty else { return nil }
        return BackendConfiguration(baseURL: baseURL, token: token)
    }

    /// Speichert Adresse und, falls angegeben, ein neues Token. Ein leeres `token` lässt das
    /// gespeicherte unverändert, damit man die Adresse ändern kann, ohne das Token neu einzugeben.
    public func save(baseURLString: String, token: String?) throws {
        guard let url = Self.validatedURL(baseURLString) else { throw BackendSettingsError.invalidURL }
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedToken.isEmpty && !hasToken { throw BackendSettingsError.missingToken }

        if !trimmedToken.isEmpty {
            try secrets.write(trimmedToken)
            hasToken = true
            // Ein Token von Hand gehört nicht zum Apple-Konto.
            clearAccountName()
        }
        defaults.set(url.absoluteString, forKey: Self.baseURLKey)
        baseURL = url
    }

    /// Speichert nur die Server-Adresse (ohne Token, etwa vor der Anmeldung mit Apple).
    public func saveBaseURL(_ string: String) throws {
        guard let url = Self.validatedURL(string) else { throw BackendSettingsError.invalidURL }
        defaults.set(url.absoluteString, forKey: Self.baseURLKey)
        baseURL = url
    }

    /// Nach der Anmeldung mit Apple: Der Token des Servers kommt an dieselbe Stelle wie ein Token von Hand, damit alle
    /// Aufrufe unverändert funktionieren.
    public func signIn(_ session: AccountSession) throws {
        try secrets.write(session.token)
        hasToken = true
        defaults.set(session.name, forKey: Self.accountNameKey)
        accountName = session.name
    }

    /// Abmelden: Token und Kontoname weg, die Server-Adresse bleibt.
    public func signOut() throws {
        try removeToken()
    }

    public func removeToken() throws {
        try secrets.delete()
        hasToken = false
        clearAccountName()
    }

    private func clearAccountName() {
        defaults.removeObject(forKey: Self.accountNameKey)
        accountName = nil
    }

    /// Nur https mit Host; ein abschließender Schrägstrich wird entfernt.
    public nonisolated static func validatedURL(_ string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
