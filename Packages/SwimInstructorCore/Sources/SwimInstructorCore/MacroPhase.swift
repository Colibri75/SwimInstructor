import Foundation

/// Phase einer Woche im Gesamtplan. Der Server rechnet sie aus dem Abstand zum Zieltag.
public enum MacroPhase: String, Codable, Equatable, Sendable {
    case base
    case specific
    case taper
    case goalWeek = "goal_week"
    case maintain
}
