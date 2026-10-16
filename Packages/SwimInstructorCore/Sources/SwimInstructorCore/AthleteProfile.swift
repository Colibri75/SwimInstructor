import Foundation

/// Wie es um eine Verletzung steht. Die Raw-Werte sind Teil des Snapshots (`athlete_profile.injuries[].status`).
public enum InjuryStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case current
    case recurring
    case past

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .current: return String(localized: "Gerade aktuell")
        case .recurring: return String(localized: "Kommt immer wieder")
        case .past: return String(localized: "Früher, ausgeheilt")
        }
    }
}

/// Belastung durch Beruf und Familie. Raw-Werte: `athlete_profile.life_stress`.
public enum LifeStress: String, Codable, Sendable, CaseIterable, Identifiable {
    case low
    case normal
    case high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: return String(localized: "Wenig")
        case .normal: return String(localized: "Normal")
        case .high: return String(localized: "Hoch")
        }
    }
}

/// Wie gern der Athlet hart trainiert, innerhalb der 80/20-Regel. Raw-Werte: `athlete_profile.intensity_preference`.
public enum IntensityPreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case easy
    case balanced
    case intense

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .easy: return String(localized: "Lieber locker")
        case .balanced: return String(localized: "Ausgewogen")
        case .intense: return String(localized: "Lieber knackig")
        }
    }
}

/// Was der Athlet unter "Über mich" angibt, damit der Coach besser plant: Erfahrung, Verletzungen, je Sportart Können,
/// Wunschtag der langen Einheit und Bahn, Alltag und Vorliebe bei der Intensität. Alles ist freiwillig; ohne Angabe
/// plant der Coach wie bisher. Geht als `athlete_profile` im Snapshot v2 zum Server (`snapshotProfile`).
public struct AthleteProfile: Codable, Equatable, Sendable {
    public struct Injury: Codable, Equatable, Sendable, Identifiable {
        public var area: PainArea
        public var status: InjuryStatus

        public var id: PainArea { area }

        public init(area: PainArea, status: InjuryStatus) {
            self.area = area
            self.status = status
        }
    }

    /// Angaben zu einer Sportart.
    public struct SportPreferences: Codable, Equatable, Sendable, Identifiable {
        public var sport: SportID
        /// Kennungen aus `SportModule.skills`, die der Athlet kann; `nil` oder leer: nicht angegeben.
        public var skills: [String]?
        /// 1 = Montag bis 7 = Sonntag; `nil`: egal.
        public var longSessionWeekday: Int?
        /// Eine der `PoolVenue.lapLengths`; `nil`: unterschiedlich oder unbekannt.
        public var lapLengthMeters: Int?
        /// Wochentage mit Zugang zur Bahn (1 = Montag); `nil`: jeden Tag.
        public var poolWeekdays: [Int]?

        public var id: SportID { sport }

        public init(sport: SportID, skills: [String]? = nil, longSessionWeekday: Int? = nil, lapLengthMeters: Int? = nil, poolWeekdays: [Int]? = nil) {
            self.sport = sport
            self.skills = skills
            self.longSessionWeekday = longSessionWeekday
            self.lapLengthMeters = lapLengthMeters
            self.poolWeekdays = poolWeekdays
        }

        var isEmpty: Bool {
            skills == nil && longSessionWeekday == nil && lapLengthMeters == nil && poolWeekdays == nil
        }
    }

    /// Nur, wenn Health kein Geburtsdatum kennt.
    public var birthYear: Int?
    /// Jahre regelmäßiger Ausdauersport.
    public var trainingYears: Int?
    public var injuries: [Injury]
    public var sports: [SportPreferences]
    public var lifeStress: LifeStress?
    public var shiftWork: Bool
    public var intensityPreference: IntensityPreference?

    public init(
        birthYear: Int? = nil,
        trainingYears: Int? = nil,
        injuries: [Injury] = [],
        sports: [SportPreferences] = [],
        lifeStress: LifeStress? = nil,
        shiftWork: Bool = false,
        intensityPreference: IntensityPreference? = nil
    ) {
        self.birthYear = birthYear
        self.trainingYears = trainingYears
        self.injuries = injuries
        self.sports = sports
        self.lifeStress = lifeStress
        self.shiftWork = shiftWork
        self.intensityPreference = intensityPreference
    }

    private enum CodingKeys: String, CodingKey {
        case birthYear, trainingYears, injuries, sports, lifeStress, shiftWork, intensityPreference
    }

    /// Tolerant: Fehlt ein Feld (ältere oder neuere Version), gilt sein Standardwert.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        trainingYears = try container.decodeIfPresent(Int.self, forKey: .trainingYears)
        injuries = (try? container.decodeIfPresent([Injury].self, forKey: .injuries)) ?? []
        sports = (try? container.decodeIfPresent([SportPreferences].self, forKey: .sports)) ?? []
        lifeStress = try? container.decodeIfPresent(LifeStress.self, forKey: .lifeStress)
        shiftWork = (try? container.decodeIfPresent(Bool.self, forKey: .shiftWork)) ?? false
        intensityPreference = try? container.decodeIfPresent(IntensityPreference.self, forKey: .intensityPreference)
    }

    public static let empty = AthleteProfile()

    /// Bereiche der Eingabe; Gegenstück: `AthleteProfileSchema` im Server (Alter 10 bis 100, Jahre 0 bis 70).
    public static let ageRange = 10...100
    public static let trainingYearsRange = 0...70

    /// Die Angaben zu einer Sportart (leer, wenn es keine gibt).
    public func preferences(for sport: SportID) -> SportPreferences {
        sports.first { $0.sport == sport } ?? SportPreferences(sport: sport)
    }

    /// Ersetzt die Angaben zu einer Sportart; leere fallen weg.
    public mutating func setPreferences(_ preferences: SportPreferences) {
        sports.removeAll { $0.sport == preferences.sport }
        if !preferences.isEmpty { sports.append(preferences) }
    }

    /// Die Verletzungsgeschichte an einer Körperstelle, `nil` ohne.
    public func injuryStatus(at area: PainArea) -> InjuryStatus? {
        injuries.first { $0.area == area }?.status
    }

    /// Setzt oder löscht (`nil`) die Angabe an einer Körperstelle, in der Reihenfolge von `PainArea`.
    public mutating func setInjury(_ status: InjuryStatus?, at area: PainArea) {
        injuries.removeAll { $0.area == area }
        if let status { injuries.append(Injury(area: area, status: status)) }
        injuries.sort { (PainArea.allCases.firstIndex(of: $0.area) ?? 0) < (PainArea.allCases.firstIndex(of: $1.area) ?? 0) }
    }

    /// Das Alter: aus Health, sonst aus dem Geburtsjahr; `nil` ohne beides oder außerhalb des erlaubten Bereichs.
    public func age(healthAge: Int?, now: Date, calendar: Calendar = .current) -> Int? {
        let age = healthAge ?? birthYear.map { calendar.component(.year, from: now) - $0 }
        return age.flatMap { Self.ageRange.contains($0) ? $0 : nil }
    }

    /// Was davon zum Server geht: nur gültige Angaben, je Sportart nur für Sportarten im Snapshot und was das Modul kennt.
    /// `nil`, wenn nichts übrig bleibt.
    public func snapshotProfile(age: Int?, sports planned: [SportID], registry: SportRegistry = .standard) -> AthleteStateSnapshot.AthleteProfileSummary? {
        let weekdays = 1...7
        let sportEntries: [AthleteStateSnapshot.AthleteProfileSummary.Sport] = registry.ids.filter(planned.contains).compactMap { id in
            guard let module = registry.module(for: id), let entry = sports.first(where: { $0.sport == id }) else { return nil }
            let known = module.skills.map(\.id)
            // Nichts angekreuzt heißt: keine Angabe.
            let skills = entry.skills.map { chosen in known.filter(chosen.contains) }.flatMap { $0.isEmpty ? nil : $0 }
            let lap = entry.lapLengthMeters.flatMap { module.pool?.lapLengths.contains($0) == true ? $0 : nil }
            let days = entry.poolWeekdays.flatMap { chosen -> [Int]? in
                let valid = Array(Set(chosen.filter { weekdays.contains($0) })).sorted()
                return module.pool != nil && !valid.isEmpty && valid.count < 7 ? valid : nil
            }
            let long = entry.longSessionWeekday.flatMap { weekdays.contains($0) ? $0 : nil }
            let result = AthleteStateSnapshot.AthleteProfileSummary.Sport(
                sport: id,
                skills: known.isEmpty ? nil : skills,
                longSessionWeekday: long,
                lapLengthMeters: lap,
                poolWeekdays: days
            )
            return result.skills == nil && long == nil && lap == nil && days == nil ? nil : result
        }
        let summary = AthleteStateSnapshot.AthleteProfileSummary(
            age: age,
            trainingYears: trainingYears.flatMap { Self.trainingYearsRange.contains($0) ? $0 : nil },
            injuries: injuries.isEmpty ? nil : injuries.map { AthleteStateSnapshot.AthleteProfileSummary.Injury(area: $0.area, status: $0.status) },
            sports: sportEntries.isEmpty ? nil : sportEntries,
            lifeStress: lifeStress,
            shiftWork: shiftWork ? true : nil,
            intensityPreference: intensityPreference
        )
        return summary.isEmpty ? nil : summary
    }
}

/// Speichert die Angaben unter "Über mich" auf dem Gerät.
public protocol AthleteProfileStoring {
    func profile() -> AthleteProfile
    func save(_ profile: AthleteProfile)
}

public struct UserDefaultsAthleteProfileStore: AthleteProfileStoring {
    static let storageKey = "settings.athleteProfile"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func profile() -> AthleteProfile {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(AthleteProfile.self, from: data) else { return .empty }
        return stored
    }

    public func save(_ profile: AthleteProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
