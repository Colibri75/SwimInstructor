import Foundation

/// Kennung einer Sportart, z. B. `swim`. Bewusst kein festes Enum: Eine neue Sportart ist ein neues Modul
/// (siehe `SportModule`), und eine Kennung, die diese App-Version noch nicht kennt (neuerer Server), bleibt
/// lesbar, statt das Dekodieren scheitern zu lassen.
///
/// Die Kennungen und ihre Bedeutung sind Teil des Vertrags zwischen App und Server (`contracts/sports.json`).
public struct SportID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Kleinbuchstaben, Ziffern und Unterstrich, beginnt mit einem Buchstaben, 2 bis 32 Zeichen. So bleibt
    /// die Kennung als JSON-Wert, Dateiname und Schlüssel im Prompt eindeutig.
    public var isWellFormed: Bool {
        guard (2...32).contains(rawValue.count), let first = rawValue.unicodeScalars.first,
              Self.letters.contains(first) else { return false }
        return rawValue.unicodeScalars.allSatisfy { Self.allowed.contains($0) }
    }

    private static let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
}
