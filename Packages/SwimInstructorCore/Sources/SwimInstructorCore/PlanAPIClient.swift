import Foundation

/// Zugangsdaten fürs Backend. Das Token liegt nie im Code, die App speichert es im Schlüsselbund.
public struct BackendConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    /// Der Produktionsserver aus M4.
    public static let defaultBaseURL = URL(string: "https://swiminstructor.kellner.v6.rocks")!
}

public enum PlanAPIError: Error, Equatable, LocalizedError {
    /// Token fehlt oder ist falsch (401).
    case unauthorized
    /// Der Server hat den Snapshot abgelehnt (400); `details` nennt die fehlerhaften Felder.
    case invalidRequest(details: [String])
    /// Claude ist ausgefallen und es gibt noch keinen früheren Plan (503).
    case planUnavailable(reason: String?)
    /// Sonstiger HTTP-Status.
    case server(status: Int)
    /// Keine Verbindung, Zeitlimit o. Ä.
    case network(String)
    /// Die Antwort passt nicht zum erwarteten Format.
    case invalidResponse(String)
    /// Der Server kennt die Planung für mehrere Sportarten (Plan v2) noch nicht: Er wurde seit dem App-Update nicht
    /// aktualisiert.
    case serverOutdated

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Der Server hat das Token abgelehnt. Prüfe es in den Einstellungen."
        case .invalidRequest(let details):
            let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
            return "Der Server hat die Trainingsdaten abgelehnt\(suffix)."
        case .planUnavailable(let reason):
            return "Kein neuer Plan: \(PlanFormatting.fallbackReason(reason))"
        case .server(let status):
            return "Der Server hat mit Status \(status) geantwortet."
        case .network(let message):
            return "Keine Verbindung zum Server: \(message)"
        case .invalidResponse:
            return "Die Antwort des Servers war unverständlich."
        case .serverOutdated:
            return "Der Server kennt die Planung für mehrere Sportarten noch nicht. Er muss aktualisiert werden (deploy.sh)."
        }
    }
}

/// Abstraktion über den Netzwerkaufruf, damit der Client ohne echten Server testbar ist.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlanAPIError.invalidResponse("keine HTTP-Antwort")
        }
        return (data, http)
    }
}

/// Spricht mit dem Backend: Pläne (die Aufrufe stehen in `PlanV2Client.swift`) und `GET /v1/status`.
public struct PlanAPIClient: Sendable {
    /// Tages- und Wochenplan: Der Server wartet bis zu 75 s auf Claude (höchstens 85 s). Etwas darüber,
    /// damit die App nicht vor dem Server aufgibt.
    public static let planTimeout: TimeInterval = 95
    /// Gesamtplan und seine Überarbeitung brauchen deutlich länger: Der Server wartet bis zu 180 s
    /// (höchstens 230 s), Caddy bricht nach 240 s ab. Etwas darüber, damit die Meldung des Servers ankommt.
    public static let macroTimeout: TimeInterval = 245
    public static let statusTimeout: TimeInterval = 15

    public let configuration: BackendConfiguration
    private let transport: HTTPTransport

    public init(configuration: BackendConfiguration, transport: HTTPTransport = URLSession.shared) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Prüft Erreichbarkeit und Token, ohne Claude aufzurufen (kostet nichts).
    public func checkConnection() async throws {
        var request = makeRequest(path: "v1/status", timeout: Self.statusTimeout)
        request.httpMethod = "GET"
        let (_, response) = try await perform(request)
        guard response.statusCode == 200 else { throw statusError(response.statusCode) }
    }

    // MARK: - Intern

    func post(path: String, body: Data, timeout: TimeInterval = PlanAPIClient.planTimeout) async throws -> (Data, HTTPURLResponse) {
        var request = makeRequest(path: path, timeout: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request)
    }

    /// Leerer Wunsch oder nur Leerraum: nichts senden. Länger als erlaubt: kürzen statt vom Server ablehnen lassen.
    static func cleaned(_ wishes: String?) -> String? {
        let trimmed = wishes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(DailyWish.maxLength))
    }

    struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let path: String
            let message: String
        }
        let error: String?
        let reason: String?
        let details: [Detail]?
    }

    private func makeRequest(path: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.timeoutInterval = timeout
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as PlanAPIError {
            throw error
        } catch {
            throw PlanAPIError.network(Self.describe(error))
        }
    }

    /// Deutsche, verständliche Meldung statt des Systemtexts (der je nach Gerätesprache englisch kommt).
    static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return "Der Servername lässt sich nicht auflösen (DNS). Probiere WLAN statt Mobilfunk oder umgekehrt und prüfe die Server-Adresse in den Einstellungen."
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return "Das iPhone hat gerade keine Internetverbindung."
        case .timedOut:
            return "Der Server hat nicht rechtzeitig geantwortet."
        case .cannotConnectToHost, .networkConnectionLost:
            return "Der Server ist nicht erreichbar."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "Die gesicherte Verbindung zum Server ist fehlgeschlagen (Zertifikat)."
        default:
            return error.localizedDescription
        }
    }

    func statusError(_ status: Int) -> PlanAPIError {
        status == 401 ? .unauthorized : .server(status: status)
    }
}
