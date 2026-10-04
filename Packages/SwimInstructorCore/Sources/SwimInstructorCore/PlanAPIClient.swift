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

/// Zusätze zur Plananfrage.
public struct PlanRequestOptions: Equatable, Sendable {
    /// Claude auch dann neu fragen, wenn für denselben Zustand heute schon ein Plan vorliegt.
    public var regenerate: Bool
    /// Freitext-Wunsch des Athleten für heute.
    public var wishes: String?
    /// Vorgabe des Wochenplans für heute (Typ, Intensität, Umfang, Schwerpunkt).
    public var dayPlan: DayPlanTarget?
    /// Das Equipment, das der Athlet hat (Rohwerte des Servers). `nil`: keine Angabe, jedes ist erlaubt;
    /// leer: keins.
    public var equipment: [String]?

    public init(regenerate: Bool = false, wishes: String? = nil, dayPlan: DayPlanTarget? = nil, equipment: [String]? = nil) {
        self.regenerate = regenerate
        self.wishes = wishes
        self.dayPlan = dayPlan
        self.equipment = equipment
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
        let (data, response) = try await postSnapshot(path: "v1/plan/today", snapshot: snapshot) { snapshot in
            PlanRequestBody(
                snapshot: snapshot,
                regenerate: options.regenerate ? true : nil,
                wishes: Self.cleaned(options.wishes),
                dayPlan: options.dayPlan,
                equipment: options.equipment
            )
        }
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

    /// Schickt eine Plananfrage mit Snapshot. Kennt der Server Snapshot v2 noch nicht (er lehnt mit 400 genau
    /// `snapshot.schema_version` ab, weil er nach einem App-Update noch nicht neu gestartet wurde), geht dieselbe
    /// Anfrage einmal mit dem v1-Teil: Der Plan kommt dann wie vor dem Update, nur ohne die anderen Sportarten.
    func postSnapshot<Body: Encodable>(
        path: String,
        snapshot: AthleteStateSnapshot,
        body: (AthleteStateSnapshot) -> Body
    ) async throws -> (Data, HTTPURLResponse) {
        let encoder = AthleteStateSnapshot.jsonEncoder()
        let (data, response) = try await post(path: path, body: try encoder.encode(body(snapshot)))
        guard response.statusCode == 400,
              snapshot.schemaVersion > AthleteStateSnapshot.currentSchemaVersion,
              let error = try? JSONDecoder().decode(ErrorBody.self, from: data),
              error.details?.contains(where: { $0.path == "snapshot.schema_version" }) == true else {
            return (data, response)
        }
        return try await post(path: path, body: try encoder.encode(body(snapshot.version1)))
    }

    func post(path: String, body: Data) async throws -> (Data, HTTPURLResponse) {
        var request = makeRequest(path: path, timeout: Self.planTimeout)
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

    private struct PlanRequestBody: Encodable {
        let snapshot: AthleteStateSnapshot
        /// Fehlt im JSON, wenn `nil`: Der Server nimmt dann seinen Cache.
        let regenerate: Bool?
        /// Fehlt im JSON ohne Wunsch.
        let wishes: String?
        /// Fehlt im JSON ohne Wochenplan.
        let dayPlan: DayPlanTarget?
        /// Fehlt im JSON ohne Angabe; eine leere Liste geht als `[]` mit.
        let equipment: [String]?
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

// MARK: - Wochenplan

/// Ein schon geschwommener Tag der Woche, der mit der Wochenplan-Anfrage mitgeht.
public struct SwumDay: Codable, Equatable, Sendable {
    public let date: String
    public let meters: Double

    public init(date: String, meters: Double) {
        self.date = date
        self.meters = meters
    }
}

/// Anfrage für `POST /v1/plan/week`.
public struct WeekPlanRequest: Equatable, Sendable {
    public var snapshot: AthleteStateSnapshot
    /// Montag der Kalenderwoche, `yyyy-MM-dd`. `nil`: der rollende Plan, die sieben Tage ab `fromDate`.
    public var weekStart: String?
    /// Erster zu planender Tag: heute oder der Montag einer kommenden Woche.
    public var fromDate: String
    public var today: String
    /// Tage ohne Zeit, sie werden Ruhetage.
    public var unavailableDates: [String]
    /// Was vor `fromDate` in dieser Woche schon geschwommen wurde.
    public var swumThisWeek: [SwumDay]
    public var wishes: String?
    /// Das Equipment, das der Athlet hat; `nil`: keine Angabe.
    public var equipment: [String]?
    /// Was in den sieben Tagen vor `fromDate` geschwommen wurde (die Vorwoche); `nil`: keine Angabe.
    public var recentSwim: [SwumDay]?
    /// Was der Gesamtplan für die Wochen der geplanten Tage vorgibt.
    public var macroWeeks: [MacroWeek]

    public init(
        snapshot: AthleteStateSnapshot,
        weekStart: String?,
        fromDate: String,
        today: String,
        unavailableDates: [String] = [],
        swumThisWeek: [SwumDay] = [],
        wishes: String? = nil,
        equipment: [String]? = nil,
        recentSwim: [SwumDay]? = nil,
        macroWeeks: [MacroWeek] = []
    ) {
        self.snapshot = snapshot
        self.weekStart = weekStart
        self.fromDate = fromDate
        self.today = today
        self.unavailableDates = unavailableDates
        self.swumThisWeek = swumThisWeek
        self.wishes = wishes
        self.equipment = equipment
        self.recentSwim = recentSwim
        self.macroWeeks = macroWeeks
    }
}

public protocol WeekPlanProviding: Sendable {
    func fetchWeekPlan(_ request: WeekPlanRequest) async throws -> WeekPlanResponse
}

extension PlanAPIClient: WeekPlanProviding {
    public func fetchWeekPlan(_ weekRequest: WeekPlanRequest) async throws -> WeekPlanResponse {
        let (data, response) = try await postSnapshot(path: "v1/plan/week", snapshot: weekRequest.snapshot) { snapshot in
            WeekRequestBody(
                snapshot: snapshot,
                weekStart: weekRequest.weekStart,
                fromDate: weekRequest.fromDate,
                today: weekRequest.today,
                unavailableDates: weekRequest.unavailableDates,
                swumThisWeek: weekRequest.swumThisWeek,
                wishes: Self.cleaned(weekRequest.wishes),
                equipment: weekRequest.equipment,
                recentSwim: weekRequest.recentSwim,
                macroWeeks: weekRequest.macroWeeks.isEmpty ? nil : weekRequest.macroWeeks
            )
        }
        switch response.statusCode {
        case 200:
            do {
                return try PlanResponse.jsonDecoder().decode(WeekPlanResponse.self, from: data)
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

    private struct WeekRequestBody: Encodable {
        let snapshot: AthleteStateSnapshot
        /// Fehlt im JSON beim rollenden Plan.
        let weekStart: String?
        let fromDate: String
        let today: String
        let unavailableDates: [String]
        let swumThisWeek: [SwumDay]
        let wishes: String?
        let equipment: [String]?
        let recentSwim: [SwumDay]?
        let macroWeeks: [MacroWeek]?
    }
}

// MARK: - Gesamtplan

/// Anfrage für `POST /v1/plan/macro`: Zustand und Ziel stecken im Snapshot, dazu "heute".
public struct MacroPlanRequest: Equatable, Sendable {
    public var snapshot: AthleteStateSnapshot
    public var today: String

    public init(snapshot: AthleteStateSnapshot, today: String) {
        self.snapshot = snapshot
        self.today = today
    }
}

public protocol MacroPlanProviding: Sendable {
    func fetchMacroPlan(_ request: MacroPlanRequest) async throws -> MacroPlanResponse
}

extension PlanAPIClient: MacroPlanProviding {
    public func fetchMacroPlan(_ macroRequest: MacroPlanRequest) async throws -> MacroPlanResponse {
        let (data, response) = try await postSnapshot(path: "v1/plan/macro", snapshot: macroRequest.snapshot) { snapshot in
            MacroRequestBody(snapshot: snapshot, today: macroRequest.today)
        }
        switch response.statusCode {
        case 200:
            do {
                return try PlanResponse.jsonDecoder().decode(MacroPlanResponse.self, from: data)
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

    private struct MacroRequestBody: Encodable {
        let snapshot: AthleteStateSnapshot
        let today: String
    }
}

