import Foundation

/// Was der Wochenplan für einen Tag vorgibt (Feld `day_plan` des Tagesplans v2): die Einheiten mit Sportart, Art,
/// Intensität, Umfang und Test. Ohne Einheit ist der Tag ein Ruhetag.
public struct DayTargetV2: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Sendable {
        public let sport: SportID
        public let sessionType: SessionType
        public let intensity: PlanIntensity
        public let amount: Double
        public let focus: String
        /// Kennung des Tests, wenn die Einheit ein Leistungstest ist.
        public let testID: String?
        /// Koppeltraining (direkt nach der ersten Einheit), nur gesetzt, wenn ja.
        public let brick: Bool?
        /// Drinnen, nur gesetzt, wenn ja.
        public let indoor: Bool?
        /// Im Freiwasser, nur gesetzt, wenn ja.
        public let openWater: Bool?

        public init(sport: SportID, sessionType: SessionType, intensity: PlanIntensity, amount: Double, focus: String, testID: String? = nil, brick: Bool = false, indoor: Bool = false, openWater: Bool = false) {
            self.sport = sport
            self.sessionType = sessionType
            self.intensity = intensity
            self.amount = amount
            self.focus = focus
            self.testID = testID
            self.brick = brick ? true : nil
            self.indoor = indoor ? true : nil
            self.openWater = openWater ? true : nil
        }

        private enum CodingKeys: String, CodingKey {
            case sport, sessionType, intensity, amount, focus, brick, indoor, openWater
            case testID = "testId"
        }
    }

    /// Ein Kraft- oder Mobilitätsblock der Vorgabe.
    public struct Extra: Codable, Equatable, Sendable {
        public let kind: ExtraKind
        public let minutes: Int
        public let focus: String

        public init(kind: ExtraKind, minutes: Int, focus: String) {
            self.kind = kind
            self.minutes = minutes
            self.focus = focus
        }
    }

    public let focus: String?
    public let sessions: [Session]
    /// Fehlt ohne Blöcke (nicht leer), damit die Vorgabe wie vor Kraft und Mobilität aussieht.
    public let extras: [Extra]?

    public init(focus: String?, sessions: [Session], extras: [Extra] = []) {
        self.focus = focus
        self.sessions = sessions
        self.extras = extras.isEmpty ? nil : extras
    }
}

/// Eine Einheit im Plan der nächsten 14 Tage: Sportart, Art, Umfang und Schwerpunkt. Die Schritte entstehen am Tag
/// selbst im Tagesplan.
public struct WeekSession: Codable, Equatable, Sendable {
    public var sport: SportID
    public var sessionType: SessionType
    public var intensity: PlanIntensity
    /// Umfang in der Einheit der Sportart (`unit`).
    public var amount: Double
    public var unit: PlanUnit
    public var minutes: Double
    public var distanceMeters: Double
    public var focus: String
    /// Gesetzt bei einem Leistungstest.
    public var test: PlannedTest?
    /// Schließt direkt an die erste Einheit des Tages an (Koppeltraining).
    public var brick: Bool
    /// Drinnen (Rolle, Laufband).
    public var indoor: Bool
    /// Im Freiwasser (See, Meer) statt im Becken.
    public var openWater: Bool

    public init(
        sport: SportID,
        sessionType: SessionType,
        intensity: PlanIntensity,
        amount: Double,
        unit: PlanUnit,
        minutes: Double,
        distanceMeters: Double,
        focus: String,
        test: PlannedTest? = nil,
        brick: Bool = false,
        indoor: Bool = false,
        openWater: Bool = false
    ) {
        self.sport = sport
        self.sessionType = sessionType
        self.intensity = intensity
        self.amount = amount
        self.unit = unit
        self.minutes = minutes
        self.distanceMeters = distanceMeters
        self.focus = focus
        self.test = test
        self.brick = brick
        self.indoor = indoor
        self.openWater = openWater
    }

    private enum CodingKeys: String, CodingKey {
        case sport, sessionType, intensity, amount, unit, minutes, distanceMeters, focus, test, brick, indoor, openWater
    }

    /// Gespeicherte Wochen und ältere Server ohne `brick`, `indoor` und `open_water` bleiben lesbar.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sport = try container.decode(SportID.self, forKey: .sport)
        sessionType = try container.decode(SessionType.self, forKey: .sessionType)
        intensity = try container.decode(PlanIntensity.self, forKey: .intensity)
        amount = try container.decode(Double.self, forKey: .amount)
        unit = try container.decode(PlanUnit.self, forKey: .unit)
        minutes = try container.decode(Double.self, forKey: .minutes)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        focus = try container.decode(String.self, forKey: .focus)
        test = try container.decodeIfPresent(PlannedTest.self, forKey: .test)
        brick = try container.decodeIfPresent(Bool.self, forKey: .brick) ?? false
        indoor = try container.decodeIfPresent(Bool.self, forKey: .indoor) ?? false
        openWater = try container.decodeIfPresent(Bool.self, forKey: .openWater) ?? false
    }

    /// Hart im Sinne der Planung: harte Intensität oder ein Test mit Vollbelastung.
    public var isHard: Bool { intensity == .hard || test?.maximalEffort == true }

    /// Die Vorgabe für den Tagesplan.
    public var target: DayTargetV2.Session {
        DayTargetV2.Session(
            sport: sport, sessionType: sessionType, intensity: intensity, amount: amount,
            focus: String(focus.prefix(DayTargetV2Limits.focusLength)), testID: test?.id, brick: brick, indoor: indoor,
            openWater: openWater
        )
    }
}

enum DayTargetV2Limits {
    /// So lang darf ein Schwerpunkt in der Vorgabe an den Server sein.
    static let focusLength = 120
}

/// Der geplante Inhalt eines Tages, ohne Datum und Markierungen: zum Merken bei "keine Zeit" und zum Tauschen.
public struct PlannedDayContent: Codable, Equatable, Sendable {
    public var focus: String
    public var sessions: [WeekSession]

    public init(focus: String, sessions: [WeekSession]) {
        self.focus = focus
        self.sessions = sessions
    }

    public static func rest(focus: String = "Ruhetag") -> PlannedDayContent {
        PlannedDayContent(focus: focus, sessions: [])
    }

    public var isRestDay: Bool { sessions.isEmpty }
}

/// Ein Tag im Plan v2. `date`, `focus` und `sessions` kommen vom Server, die übrigen Felder sind Änderungen des Athleten
/// und nur auf dem Gerät gespeichert.
public struct PlannedDay: Codable, Equatable, Sendable, Identifiable {
    /// Kalendertag `yyyy-MM-dd`.
    public var date: String
    public var focus: String
    /// Null bis zwei Einheiten; leer an einem Ruhetag.
    public var sessions: [WeekSession]
    /// Der Athlet hat an diesem Tag keine Zeit: Ruhetag, bis er ihn wieder freigibt.
    public var isUnavailable: Bool
    /// Was vor "keine Zeit" geplant war, zum Zurückstellen.
    public var contentBeforeUnavailable: PlannedDayContent?
    /// Der Athlet hat diesen Tag von Hand geändert.
    public var isEdited: Bool
    /// Kraft- und Mobilitätsblöcke (vom Server).
    public var extras: [WeekExtra]

    public var id: String { date }

    public init(
        date: String,
        content: PlannedDayContent,
        isUnavailable: Bool = false,
        contentBeforeUnavailable: PlannedDayContent? = nil,
        isEdited: Bool = false,
        extras: [WeekExtra] = []
    ) {
        self.date = date
        self.focus = content.focus
        self.sessions = content.sessions
        self.isUnavailable = isUnavailable
        self.contentBeforeUnavailable = contentBeforeUnavailable
        self.isEdited = isEdited
        self.extras = extras
    }

    private enum CodingKeys: String, CodingKey {
        case date, focus, sessions, isUnavailable, contentBeforeUnavailable, isEdited, extras
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? ""
        sessions = try container.decode([WeekSession].self, forKey: .sessions)
        isUnavailable = try container.decodeIfPresent(Bool.self, forKey: .isUnavailable) ?? false
        contentBeforeUnavailable = try container.decodeIfPresent(PlannedDayContent.self, forKey: .contentBeforeUnavailable)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        extras = (try container.decodeIfPresent([WeekExtra].self, forKey: .extras) ?? []).filter { $0.kind != .unknown }
    }

    public var content: PlannedDayContent {
        get { PlannedDayContent(focus: focus, sessions: sessions) }
        set {
            focus = newValue.focus
            sessions = newValue.sessions
        }
    }

    public var isRestDay: Bool { sessions.isEmpty }

    /// Geplante Minuten aller Einheiten des Tages.
    public var totalMinutes: Double { sessions.reduce(0) { $0 + $1.minutes } }

    /// Die Vorgabe für den Tagesplan. Ein Tag ohne Zeit ist ein Ruhetag, ohne Kraft und Mobilität.
    public var target: DayTargetV2 {
        DayTargetV2(
            focus: focus.isEmpty ? nil : String(focus.prefix(DayTargetV2Limits.focusLength)),
            sessions: isUnavailable ? [] : sessions.map(\.target),
            extras: isUnavailable ? [] : extras.map {
                DayTargetV2.Extra(kind: $0.kind, minutes: Int($0.minutes.rounded()), focus: String($0.focus.prefix(DayTargetV2Limits.focusLength)))
            }
        )
    }
}

/// Die Tage einer Kalenderwoche im Plan v2, wie die App sie hält und der Athlet sie anpasst. Enthält nur die geplanten
/// Tage (wer mitten in der Woche plant, hat für die Tage davor keinen Eintrag).
public struct WeekPlanV2: Codable, Equatable, Sendable, Identifiable {
    /// Montag der Woche, `yyyy-MM-dd`.
    public var weekStart: String
    public var generatedAt: Date
    public var rationale: String
    public var adjustments: [String]
    public var wishes: String?
    /// Aufsteigend nach Datum.
    public var days: [PlannedDay]

    public var id: String { weekStart }

    public init(weekStart: String, generatedAt: Date, rationale: String, adjustments: [String] = [], wishes: String? = nil, days: [PlannedDay]) {
        self.weekStart = weekStart
        self.generatedAt = generatedAt
        self.rationale = rationale
        self.adjustments = adjustments
        self.wishes = wishes
        self.days = days.sorted { $0.date < $1.date }
    }

    public func day(on date: String) -> PlannedDay? {
        days.first { $0.date == date }
    }

    /// Geplante Minuten der Woche, ohne Tage ohne Zeit.
    public var plannedMinutes: Double {
        days.filter { !$0.isUnavailable }.reduce(0) { $0 + $1.totalMinutes }
    }

    /// Die Sportarten der Woche in der Reihenfolge, in der sie zuerst vorkommen.
    public var sports: [SportID] {
        var seen = Set<SportID>()
        return days.flatMap(\.sessions).map(\.sport).filter { seen.insert($0).inserted }
    }
}

/// Antwort von `POST /v1/plan/week` mit `plan_version: 2`: die angefragten 14 Tage ab `from_date`.
public struct WeekPlanV2Response: Decodable, Equatable, Sendable {
    public struct Plan: Decodable, Equatable, Sendable {
        public let rationale: String
        public let totalMinutes: Double
        public let days: [PlannedDay]
    }

    public let planVersion: Int
    public let fromDate: String
    public let generatedAt: Date
    public let plan: Plan
    public let adjustments: [String]
    public let wishes: String?
}
