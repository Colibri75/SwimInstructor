import Foundation

/// Was der Wochenplan für einen Tag vorgibt. Geht mit der Tagesplan-Anfrage an den Server, damit der
/// Detailplan zur Woche passt.
public struct DayPlanTarget: Codable, Equatable, Sendable {
    public let sessionType: SessionType
    public let intensity: PlanIntensity
    public let targetDistanceMeters: Int
    public let focus: String

    public init(sessionType: SessionType, intensity: PlanIntensity, targetDistanceMeters: Int, focus: String) {
        self.sessionType = sessionType
        self.intensity = intensity
        self.targetDistanceMeters = targetDistanceMeters
        self.focus = focus
    }
}

/// Der geplante Inhalt eines Tages, ohne Datum und ohne Markierungen des Athleten. Dient zum Merken
/// und Zurückstellen ("keine Zeit" rückgängig machen) und zum Tauschen von Tagen.
public struct WeekDayContent: Codable, Equatable, Sendable {
    public var sessionType: SessionType
    public var intensity: PlanIntensity
    public var targetDistanceMeters: Int
    public var estimatedDurationMinutes: Int
    public var focus: String

    public init(sessionType: SessionType, intensity: PlanIntensity, targetDistanceMeters: Int, estimatedDurationMinutes: Int, focus: String) {
        self.sessionType = sessionType
        self.intensity = intensity
        self.targetDistanceMeters = targetDistanceMeters
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.focus = focus
    }

    public static func rest(focus: String = "Ruhetag") -> WeekDayContent {
        WeekDayContent(sessionType: .rest, intensity: .rest, targetDistanceMeters: 0, estimatedDurationMinutes: 0, focus: focus)
    }

    public var isRestDay: Bool {
        sessionType == .rest || intensity == .rest || targetDistanceMeters == 0
    }
}

/// Ein Tag im Wochenplan. Die Felder bis `focus` kommen vom Server, die übrigen sind Änderungen des
/// Athleten und nur auf dem Gerät gespeichert (ältere Daten ohne sie bleiben lesbar).
public struct WeekDayPlan: Codable, Equatable, Sendable, Identifiable {
    /// Kalendertag `yyyy-MM-dd`.
    public var date: String
    public var sessionType: SessionType
    public var intensity: PlanIntensity
    public var targetDistanceMeters: Int
    public var estimatedDurationMinutes: Int
    public var focus: String
    /// Der Athlet hat an diesem Tag keine Zeit: Ruhetag, bis er ihn wieder freigibt.
    public var isUnavailable: Bool
    /// Was vor "keine Zeit" geplant war, zum Zurückstellen.
    public var contentBeforeUnavailable: WeekDayContent?
    /// Der Athlet hat diesen Tag von Hand geändert (getauscht, verschoben, Umfang).
    public var isEdited: Bool

    public var id: String { date }

    public init(
        date: String,
        content: WeekDayContent,
        isUnavailable: Bool = false,
        contentBeforeUnavailable: WeekDayContent? = nil,
        isEdited: Bool = false
    ) {
        self.date = date
        self.sessionType = content.sessionType
        self.intensity = content.intensity
        self.targetDistanceMeters = content.targetDistanceMeters
        self.estimatedDurationMinutes = content.estimatedDurationMinutes
        self.focus = content.focus
        self.isUnavailable = isUnavailable
        self.contentBeforeUnavailable = contentBeforeUnavailable
        self.isEdited = isEdited
    }

    private enum CodingKeys: String, CodingKey {
        case date, sessionType, intensity, targetDistanceMeters, estimatedDurationMinutes, focus
        case isUnavailable, contentBeforeUnavailable, isEdited
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        sessionType = try container.decode(SessionType.self, forKey: .sessionType)
        intensity = try container.decode(PlanIntensity.self, forKey: .intensity)
        targetDistanceMeters = try container.decode(Int.self, forKey: .targetDistanceMeters)
        estimatedDurationMinutes = try container.decode(Int.self, forKey: .estimatedDurationMinutes)
        focus = try container.decode(String.self, forKey: .focus)
        isUnavailable = try container.decodeIfPresent(Bool.self, forKey: .isUnavailable) ?? false
        contentBeforeUnavailable = try container.decodeIfPresent(WeekDayContent.self, forKey: .contentBeforeUnavailable)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
    }

    public var content: WeekDayContent {
        get {
            WeekDayContent(
                sessionType: sessionType,
                intensity: intensity,
                targetDistanceMeters: targetDistanceMeters,
                estimatedDurationMinutes: estimatedDurationMinutes,
                focus: focus
            )
        }
        set {
            sessionType = newValue.sessionType
            intensity = newValue.intensity
            targetDistanceMeters = newValue.targetDistanceMeters
            estimatedDurationMinutes = newValue.estimatedDurationMinutes
            focus = newValue.focus
        }
    }

    public var isRestDay: Bool { content.isRestDay }

    public var target: DayPlanTarget {
        DayPlanTarget(sessionType: sessionType, intensity: intensity, targetDistanceMeters: targetDistanceMeters, focus: focus)
    }
}

/// Der Wochenplan, wie ihn die App hält und der Athlet ihn anpasst. Enthält nur die Tage, die geplant
/// wurden (wer mitten in der Woche plant, hat für die Tage davor keinen Eintrag).
public struct WeekPlan: Codable, Equatable, Sendable, Identifiable {
    /// Montag der Woche, `yyyy-MM-dd`.
    public var weekStart: String
    public var generatedAt: Date
    public var rationale: String
    /// Korrekturen der Sicherheitsschicht des Servers, auf Deutsch.
    public var adjustments: [String]
    /// Der Wunsch, mit dem der Plan entstand.
    public var wishes: String?
    /// Geplante Tage, aufsteigend nach Datum.
    public var days: [WeekDayPlan]

    public var id: String { weekStart }

    public init(weekStart: String, generatedAt: Date, rationale: String, adjustments: [String] = [], wishes: String? = nil, days: [WeekDayPlan]) {
        self.weekStart = weekStart
        self.generatedAt = generatedAt
        self.rationale = rationale
        self.adjustments = adjustments
        self.wishes = wishes
        self.days = days.sorted { $0.date < $1.date }
    }

    public func day(on date: String) -> WeekDayPlan? {
        days.first { $0.date == date }
    }

    /// Summe der geplanten Meter, ohne Tage ohne Zeit.
    public var plannedMeters: Int {
        days.filter { !$0.isUnavailable }.reduce(0) { $0 + $1.targetDistanceMeters }
    }
}

/// Antwort von `POST /v1/plan/week`.
public struct WeekPlanResponse: Decodable, Equatable, Sendable {
    public struct Plan: Decodable, Equatable, Sendable {
        public let rationale: String
        public let totalDistanceMeters: Int
        public let days: [WeekDayPlan]
    }

    public let weekStart: String
    public let generatedAt: Date
    public let plan: Plan
    public let adjustments: [String]
    public let wishes: String?

    public var weekPlan: WeekPlan {
        WeekPlan(
            weekStart: weekStart,
            generatedAt: generatedAt,
            rationale: plan.rationale,
            adjustments: adjustments,
            wishes: wishes,
            days: plan.days
        )
    }
}
