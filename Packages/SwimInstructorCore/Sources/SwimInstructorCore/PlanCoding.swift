import Foundation

/// Art der Einheit. Unbekannte Werte vom Server werden zu `.unknown`, damit eine neue Serverversion
/// die App nicht aus dem Tritt bringt.
public enum SessionType: String, Codable, Sendable, CaseIterable {
    case rest
    case recovery
    case technique
    case endurance
    case threshold
    case intervals
    case test
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionType(rawValue: raw) ?? .unknown
    }
}

public enum PlanIntensity: String, Codable, Sendable, CaseIterable {
    case rest
    case easy
    case moderate
    case hard
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlanIntensity(rawValue: raw) ?? .unknown
    }
}

/// Woher der Plan stammt (siehe docs/plan-generation.md).
public enum PlanSource: String, Codable, Sendable {
    /// Frisch von Claude erzeugt.
    case claude
    /// Heute schon für denselben Zustand erzeugt.
    case cache
    /// Letzter gültiger Plan, weil Claude nicht geantwortet hat.
    case fallback
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlanSource(rawValue: raw) ?? .unknown
    }
}

/// Kodierung der Antworten des Servers und der lokal gespeicherten Pläne.
public enum PlanCoding {
    /// Der Server schreibt Zeitstempel mit Millisekunden (`toISOString()`), das eingebaute `.iso8601` versteht die
    /// nicht. Darum ein eigener Decoder, der beide Formen annimmt.
    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601Parsing.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Kein ISO-8601-Datum: \(raw)"
            )
        }
        return decoder
    }

    /// Zum Zwischenspeichern auf dem Gerät, passend zu `jsonDecoder()`.
    public static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum ISO8601Parsing {
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
