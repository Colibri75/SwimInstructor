import Foundation

/// Ergebnis der Anmeldung: der Token für alle weiteren Aufrufe und wer angemeldet ist.
public struct AccountSession: Equatable, Sendable {
    public let token: String
    public let userID: String
    public let name: String

    public init(token: String, userID: String, name: String) {
        self.token = token
        self.userID = userID
        self.name = name
    }
}

public enum AccountError: Error, Equatable, LocalizedError {
    /// Neue Konten gibt der Besitzer des Servers erst frei (`APPLE_SIGNUP=closed`), 403.
    case signupClosed
    /// Apple hat kein brauchbares Identitätstoken geliefert oder der Server hat es abgelehnt (401 bei der Anmeldung).
    case invalidIdentity
    /// Zu viele Anmeldeversuche (429).
    case rateLimited
    /// Der Zugang des Besitzers lässt sich nicht löschen (409).
    case ownerCannotBeDeleted
    /// Beim Löschen: Der Token gilt nicht (mehr) (401).
    case unauthorized
    /// Apple war für den Server nicht erreichbar (503).
    case appleUnavailable
    case server(status: Int)
    case network(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .signupClosed:
            return String(localized: "Dein Konto ist noch nicht freigeschaltet. Versuche es später noch einmal.")
        case .invalidIdentity:
            return String(localized: "Die Anmeldung mit Apple hat nicht geklappt. Versuche es noch einmal.")
        case .rateLimited:
            return String(localized: "Zu viele Anmeldeversuche. Warte eine Minute und versuche es dann noch einmal.")
        case .ownerCannotBeDeleted:
            return String(localized: "Der Zugang des Server-Besitzers lässt sich in der App nicht löschen.")
        case .unauthorized:
            return String(localized: "Deine Anmeldung gilt nicht mehr. Melde dich neu an und lösche das Konto dann.")
        case .appleUnavailable:
            return String(localized: "Apple ist gerade nicht erreichbar. Versuche es später noch einmal.")
        case .server(let status):
            return String(localized: "Der Server hat mit Status \(status) geantwortet.")
        case .network(let message):
            return String(localized: "Keine Verbindung zum Server: \(message)")
        case .invalidResponse:
            return String(localized: "Die Antwort des Servers war unverständlich.")
        }
    }
}

/// Anmeldung mit Apple (`POST /v1/auth/apple`) und Löschen des Kontos (`DELETE /v1/account`).
public struct AccountClient: Sendable {
    public static let timeout: TimeInterval = 20

    public let baseURL: URL
    private let transport: HTTPTransport

    public init(baseURL: URL, transport: HTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Tauscht das Identitätstoken von Apple gegen einen Token des Servers.
    /// - Parameter name: Den Namen gibt Apple nur bei der ersten Anmeldung heraus; leer bleibt er weg.
    public func signInWithApple(identityToken: String, name: String?) async throws -> AccountSession {
        struct Body: Encodable {
            let identityToken: String
            let name: String?
        }
        struct Response: Decodable {
            struct User: Decodable {
                let id: String
                let name: String
            }
            let token: String
            let user: User
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var request = makeRequest(path: "v1/auth/apple")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(identityToken: identityToken, name: trimmedName.isEmpty ? nil : trimmedName))

        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data), !decoded.token.isEmpty else {
                throw AccountError.invalidResponse
            }
            return AccountSession(token: decoded.token, userID: decoded.user.id, name: decoded.user.name)
        case 400, 401:
            throw AccountError.invalidIdentity
        case 403:
            throw AccountError.signupClosed
        case 429:
            throw AccountError.rateLimited
        case 503:
            throw AccountError.appleUnavailable
        default:
            throw AccountError.server(status: response.statusCode)
        }
    }

    /// Löscht das Konto zum Token samt seiner Daten auf dem Server.
    public func deleteAccount(token: String) async throws {
        var request = makeRequest(path: "v1/account")
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200, 204:
            return
        case 401:
            throw AccountError.unauthorized
        case 409:
            throw AccountError.ownerCannotBeDeleted
        default:
            throw AccountError.server(status: response.statusCode)
        }
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppLocale.languageCode, forHTTPHeaderField: "X-App-Language")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as AccountError {
            throw error
        } catch {
            throw AccountError.network(PlanAPIClient.describe(error))
        }
    }
}
