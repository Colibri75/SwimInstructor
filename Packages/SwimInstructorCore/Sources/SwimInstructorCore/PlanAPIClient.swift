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

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Der Server hat das Token abgelehnt. Prüfe es in den Einstellungen."
        case .invalidRequest(let details):
            let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
            return "Der Server hat die Trainingsdaten abgelehnt\(suffix)."
        case .planUnavailable:
            return "Claude ist gerade nicht erreichbar und es gibt noch keinen früheren Plan."
        case .server(let status):
            return "Der Server hat mit Status \(status) geantwortet."
        case .network(let message):
            return "Keine Verbindung zum Server: \(message)"
        case .invalidResponse:
            return "Die Antwort des Servers war unverständlich."
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

/// Zusätze zur Plananfrage.
public struct PlanRequestOptions: Equatable, Sendable {
    /// Claude auch dann neu fragen, wenn für denselben Zustand heute schon ein Plan vorliegt.
    public var regenerate: Bool
    /// Freitext-Wunsch des Athleten für heute.
    public var wishes: String?

    public init(regenerate: Bool = false, wishes: String? = nil) {
        self.regenerate = regenerate
        self.wishes = wishes
    }
}

public protocol PlanProviding: Sendable {
    func fetchPlan(for snapshot: AthleteStateSnapshot, options: PlanRequestOptions) async throws -> PlanResponse
}

public extension PlanProviding {
    /// Plan für heute; hat der Server für denselben Zustand schon einen, kommt er aus dem Cache.
    func fetchTodayPlan(for snapshot: AthleteStateSnapshot) async throws -> PlanResponse {
        try await fetchPlan(for: snapshot, options: PlanRequestOptions())
    }

    /// Neuer Plan, auch bei unverändertem Zustand (Ziehen zum Aktualisieren).
    func fetchNewPlan(for snapshot: AthleteStateSnapshot) async throws -> PlanResponse {
        try await fetchPlan(for: snapshot, options: PlanRequestOptions(regenerate: true))
    }
}

/// Spricht mit dem Backend aus M4/M5: `POST /v1/plan/today` und `GET /v1/status`.
public struct PlanAPIClient: PlanProviding {
    /// Der Server wartet bis zu 75 s auf Claude, Caddy bricht nach 90 s ab. Etwas darüber, damit
    /// die App nicht vor dem Server aufgibt.
    public static let planTimeout: TimeInterval = 95
    public static let statusTimeout: TimeInterval = 15

    public let configuration: BackendConfiguration
    private let transport: HTTPTransport

    public init(configuration: BackendConfiguration, transport: HTTPTransport = URLSession.shared) {
        self.configuration = configuration
        self.transport = transport
    }

    public func fetchPlan(for snapshot: AthleteStateSnapshot, options: PlanRequestOptions) async throws -> PlanResponse {
        var request = makeRequest(path: "v1/plan/today", timeout: Self.planTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try AthleteStateSnapshot.jsonEncoder().encode(PlanRequestBody(
            snapshot: snapshot,
            regenerate: options.regenerate ? true : nil,
            wishes: Self.cleaned(options.wishes)
        ))

        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            do {
                return try PlanResponse.jsonDecoder().decode(PlanResponse.self, from: data)
            } catch {
                throw PlanAPIError.invalidResponse(String(describing: error))
            }
        case 400:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw PlanAPIError.invalidRequest(details: body?.details?.map { "\($0.path): \($0.message)" } ?? [])
        case 503:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw PlanAPIError.planUnavailable(reason: body?.reason)
        default:
            throw statusError(response.statusCode)
        }
    }

    /// Prüft Erreichbarkeit und Token, ohne Claude aufzurufen (kostet nichts).
    public func checkConnection() async throws {
        var request = makeRequest(path: "v1/status", timeout: Self.statusTimeout)
        request.httpMethod = "GET"
        let (_, response) = try await perform(request)
        guard response.statusCode == 200 else { throw statusError(response.statusCode) }
    }

    // MARK: - Intern

    /// Leerer Wunsch oder nur Leerraum: nichts senden. Länger als erlaubt: kürzen statt vom Server ablehnen lassen.
    static func cleaned(_ wishes: String?) -> String? {
        let trimmed = wishes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(DailyWish.maxLength))
    }

    private struct PlanRequestBody: Encodable {
        let snapshot: AthleteStateSnapshot
        /// Fehlt im JSON, wenn `nil`: Der Server nimmt dann seinen Cache.
        let regenerate: Bool?
        /// Fehlt im JSON ohne Wunsch.
        let wishes: String?
    }

    private struct ErrorBody: Decodable {
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
            throw PlanAPIError.network(error.localizedDescription)
        }
    }

    private func statusError(_ status: Int) -> PlanAPIError {
        status == 401 ? .unauthorized : .server(status: status)
    }
}
