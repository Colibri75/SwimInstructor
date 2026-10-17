import SwiftUI
import SwimInstructorCore

/// "Über mich": Fragen, mit denen dein Coach besser plant (Erfahrung, Verletzungen, Können, Bahn, langer Tag, Alltag,
/// Intensität). Alles freiwillig; jede Änderung wird sofort gespeichert und gilt ab dem nächsten Plan.
struct AthleteProfileView: View {
    private let store: AthleteProfileStoring
    private let registry = SportRegistry.standard
    @State private var profile = AthleteProfile.empty
    @State private var goalSports: [SportID] = []
    @State private var healthAge: Int?

    /// Auswahl für "Ausdauersport seit"; 0 heißt weniger als ein Jahr.
    private static let trainingYearChoices = [0, 1, 2, 3, 5, 10, 20]

    init(store: AthleteProfileStoring = UserDefaultsAthleteProfileStore()) {
        self.store = store
    }

    var body: some View {
        Form {
            Group {
                personSection
                injurySection
                ForEach(shownSports, id: \.self) { sport in
                    sportSection(sport)
                    poolSection(sport)
                }
                everydaySection
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Über mich")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            profile = store.profile()
            goalSports = UserDefaultsTrainingGoalStore().goal().emphasis.filter { $0.percent > 0 }.map(\.sport)
            healthAge = HealthKitPerformanceDataRepository().age(now: Date())
        }
    }

    /// Die Sportarten des Ziels in der Reihenfolge der Registry.
    private var shownSports: [SportID] {
        registry.ids.filter(goalSports.contains)
    }

    // MARK: - Person

    private var personSection: some View {
        Section {
            if let healthAge {
                LabeledContent("Alter", value: String(localized: "\(healthAge) Jahre"))
            } else {
                Picker("Geburtsjahr", selection: update(\.birthYear)) {
                    Text("Keine Angabe").tag(Int?.none)
                    ForEach(birthYears, id: \.self) { year in
                        Text(verbatim: String(year)).tag(Optional(year))
                    }
                }
            }
            Picker("Ausdauersport seit", selection: update(\.trainingYears)) {
                Text("Keine Angabe").tag(Int?.none)
                ForEach(Self.trainingYearChoices, id: \.self) { years in
                    Text(yearsTitle(years)).tag(Optional(years))
                }
            }
        } header: {
            Text("Erfahrung")
        } footer: {
            if healthAge != nil {
                Text("Das Alter kommt aus Apple Health. Mit Alter und Erfahrung steigert dein Coach behutsamer oder plant mehr Erholung.")
            } else {
                Text("Mit Alter und Erfahrung steigert dein Coach behutsamer oder plant mehr Erholung. Das Geburtsjahr fragt die App nur, wenn Apple Health kein Geburtsdatum kennt.")
            }
        }
    }

    private var birthYears: [Int] {
        let year = Calendar.current.component(.year, from: Date())
        return Array(((year - AthleteProfile.ageRange.upperBound)...(year - AthleteProfile.ageRange.lowerBound)).reversed())
    }

    private func yearsTitle(_ years: Int) -> String {
        switch years {
        case 0: return String(localized: "Weniger als 1 Jahr")
        case 1: return String(localized: "1 Jahr")
        default: return String(localized: "\(years) Jahren")
        }
    }

    // MARK: - Verletzungen

    private var injurySection: some View {
        Section {
            ForEach(PainArea.allCases) { area in
                Picker(area.displayName, selection: injuryBinding(area)) {
                    Text("Keine").tag(InjuryStatus?.none)
                    ForEach(InjuryStatus.allCases) { status in
                        Text(status.title).tag(Optional(status))
                    }
                }
            }
        } header: {
            Text("Verletzungen")
        } footer: {
            Text("Eine aktuelle Verletzung schont dein Coach, bei einer wiederkehrenden steigert er vorsichtiger und stärkt die Stelle mit Kraft und Mobilität. Keine Diagnose: Bei anhaltenden Beschwerden geh zum Arzt.")
        }
    }

    private func injuryBinding(_ area: PainArea) -> Binding<InjuryStatus?> {
        Binding(
            get: { profile.injuryStatus(at: area) },
            set: { status in change { $0.setInjury(status, at: area) } }
        )
    }

    // MARK: - Je Sportart

    @ViewBuilder
    private func sportSection(_ sport: SportID) -> some View {
        let module = registry.module(for: sport)
        Section {
            Picker("Lange Einheit am", selection: sportBinding(sport, \.longSessionWeekday)) {
                Text("Egal").tag(Int?.none)
                ForEach(1...7, id: \.self) { weekday in
                    Text(WeeklySchedule.weekdayNames[weekday - 1]).tag(Optional(weekday))
                }
            }
            ForEach(module?.skills ?? []) { skill in
                Toggle(skill.displayName, isOn: skillBinding(sport, skill.id))
            }
        } header: {
            Text(registry.displayName(for: sport))
        } footer: {
            if module?.skills.isEmpty == false {
                Text("Kreuz an, was du sicher kannst. Dein Coach plant nur damit; ohne Kreuz gilt keine Angabe.")
            }
        }
    }

    @ViewBuilder
    private func poolSection(_ sport: SportID) -> some View {
        if let pool = registry.module(for: sport)?.pool {
            Section {
                Picker("Bahnlänge", selection: sportBinding(sport, \.lapLengthMeters)) {
                    Text("Unterschiedlich").tag(Int?.none)
                    ForEach(pool.lapLengths, id: \.self) { meters in
                        Text(verbatim: "\(meters) m").tag(Optional(meters))
                    }
                }
                ForEach(1...7, id: \.self) { weekday in
                    Toggle(WeeklySchedule.weekdayNames[weekday - 1], isOn: poolDayBinding(sport, weekday))
                }
            } header: {
                Text("\(registry.displayName(for: sport)): \(pool.displayName)")
            } footer: {
                Text("An welchen Tagen du hinkommst. An den anderen Tagen plant dein Coach dort nichts, im Freiwasser geht es trotzdem.")
            }
        }
    }

    private func sportBinding<Value>(_ sport: SportID, _ keyPath: WritableKeyPath<AthleteProfile.SportPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { profile.preferences(for: sport)[keyPath: keyPath] },
            set: { value in
                change {
                    var preferences = $0.preferences(for: sport)
                    preferences[keyPath: keyPath] = value
                    $0.setPreferences(preferences)
                }
            }
        )
    }

    private func skillBinding(_ sport: SportID, _ skill: String) -> Binding<Bool> {
        Binding(
            get: { profile.preferences(for: sport).skills?.contains(skill) == true },
            set: { isOn in
                change {
                    var preferences = $0.preferences(for: sport)
                    var skills = (preferences.skills ?? []).filter { $0 != skill }
                    if isOn { skills.append(skill) }
                    preferences.skills = skills.isEmpty ? nil : skills
                    $0.setPreferences(preferences)
                }
            }
        )
    }

    /// Ohne Angabe ist jeder Tag an; sind wieder alle an, fällt die Angabe weg.
    private func poolDayBinding(_ sport: SportID, _ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { profile.preferences(for: sport).poolWeekdays?.contains(weekday) ?? true },
            set: { isOn in
                change {
                    var preferences = $0.preferences(for: sport)
                    var days = Set(preferences.poolWeekdays ?? Array(1...7))
                    if isOn { days.insert(weekday) } else { days.remove(weekday) }
                    // Mindestens ein Tag bleibt, sonst gäbe es die Sportart gar nicht.
                    guard !days.isEmpty else { return }
                    preferences.poolWeekdays = days.count == 7 ? nil : days.sorted()
                    $0.setPreferences(preferences)
                }
            }
        )
    }

    // MARK: - Alltag und Intensität

    private var everydaySection: some View {
        Section {
            Picker("Stress im Alltag", selection: update(\.lifeStress)) {
                Text("Keine Angabe").tag(LifeStress?.none)
                ForEach(LifeStress.allCases) { level in
                    Text(level.title).tag(Optional(level))
                }
            }
            Toggle("Schichtarbeit", isOn: update(\.shiftWork))
            Picker("Harte Einheiten", selection: update(\.intensityPreference)) {
                Text("Keine Angabe").tag(IntensityPreference?.none)
                ForEach(IntensityPreference.allCases) { preference in
                    Text(preference.title).tag(Optional(preference))
                }
            }
        } header: {
            Text("Alltag")
        } footer: {
            Text("Stress im Alltag: wie sehr dich Beruf, Familie oder wenig Schlaf gerade fordern. Ist es viel oder arbeitest du in Schichten, plant dein Coach höchstens einen harten Tag pro Woche. Harte Einheiten: ob du lieber ruhig trainierst oder gern mehr Intervalle und Tempo hast. Rund 80 Prozent bleiben immer locker.")
        }
    }

    // MARK: - Speichern

    private func update<Value>(_ keyPath: WritableKeyPath<AthleteProfile, Value>) -> Binding<Value> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { value in change { $0[keyPath: keyPath] = value } }
        )
    }

    private func change(_ edit: (inout AthleteProfile) -> Void) {
        var copy = profile
        edit(&copy)
        profile = copy
        store.save(copy)
    }
}
