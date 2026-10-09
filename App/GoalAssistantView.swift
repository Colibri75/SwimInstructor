import SwiftUI
import SwimInstructorCore

/// Ziel-Assistent: Zielart wählen (Wettkampf, Zeit, Strecke, Fitness), beim Wettkampf auf Wunsch eine Vorlage
/// (Triathlon-Distanzen, Lauf, Schwimmen, Rad), dann Disziplinen mit Strecke und Zielzeit, Zieltag und der
/// Schwerpunkt je Sportart. Die Trainingszeit kommt aus dem Wochenraster.
///
/// In der Einrichtung wird ein gültiges Ziel sofort gespeichert. In den Einstellungen ist es ein Entwurf (P3): Die
/// Ansicht zeigt, was mit dem Gesamtplan passiert, und erst "Übernehmen" ändert das Ziel. Ein neues Ziel geht höchstens
/// alle 7 Tage; in der Sperre lässt es sich vormerken und wird an ihrem Ende übernommen.
struct GoalAssistantView: View {
    enum Mode {
        case onboarding, settings
    }

    @EnvironmentObject private var todayLoader: MultiSportTodayLoader

    private let store: TrainingGoalStoring
    private let scheduleStore: WeeklyScheduleStoring
    private let mode: Mode
    private let isValid: Binding<Bool>?
    private let sports = SportRegistry.standard

    @State private var goal = TrainingGoal.default
    @State private var loaded = false
    @State private var scheduleSummary = ""
    @State private var pending: TrainingGoal?
    @State private var message: String?

    init(
        store: TrainingGoalStoring = UserDefaultsTrainingGoalStore(),
        scheduleStore: WeeklyScheduleStoring = UserDefaultsWeeklyScheduleStore(),
        mode: Mode = .settings,
        isValid: Binding<Bool>? = nil
    ) {
        self.store = store
        self.scheduleStore = scheduleStore
        self.mode = mode
        self.isValid = isValid
    }

    /// In der Einrichtung ist der Wochenraster ein eigener Schritt.
    private var showsSchedule: Bool { mode == .settings }

    var body: some View {
        Form {
            Group {
                kindSection
                if goal.kind == .race {
                    templateSection
                }
                if goal.kind.hasDisciplines {
                    ForEach(sports.ids, id: \.self) { sport in
                        disciplineSection(sport)
                    }
                } else {
                    sportsSection
                }
                emphasisSection
                trainingSection
                if mode == .settings {
                    applySection
                } else {
                    statusSection
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Mein Ziel")
        .swipeClosesKeyboard()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Auch nach der Rückkehr aus dem Wochenraster.
            scheduleSummary = scheduleStore.schedule(for: store.goal()).summary
            guard !loaded else { return }
            goal = store.goal()
            pending = store.pendingGoal()
            loaded = true
            isValid?.wrappedValue = goal.problem(now: Date()) == nil
        }
        .onChange(of: goal) { _, newGoal in
            guard loaded else { return }
            message = nil
            if mode == .onboarding {
                store.setGoal(newGoal, now: Date())
            }
            isValid?.wrappedValue = newGoal.problem(now: Date()) == nil
        }
    }

    // MARK: - Zielart

    private var kindSection: some View {
        Section {
            Picker("Zielart", selection: kindBinding) {
                ForEach(GoalKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        } footer: {
            Text(goal.kind.explanation)
        }
    }

    private var kindBinding: Binding<GoalKind> {
        Binding(
            get: { goal.kind },
            set: { goal = goal.settingKind($0, now: Date()) }
        )
    }

    /// Beim Fitnessziel: welche Sportarten zum Training gehören.
    private var sportsSection: some View {
        Section {
            ForEach(sports.ids, id: \.self) { sport in
                Toggle(isOn: sportBinding(sport)) {
                    Label(sports.displayName(for: sport), systemImage: sports.symbolName(for: sport))
                }
            }
        } header: {
            Text("Sportarten")
        } footer: {
            Text("Mindestens eine Sportart bleibt.")
        }
    }

    private func sportBinding(_ sport: SportID) -> Binding<Bool> {
        Binding(
            get: { goal.percent(for: sport) > 0 },
            set: { goal = goal.settingSport(sport, included: $0) }
        )
    }

    // MARK: - Vorlage

    private var templateSection: some View {
        Section {
            Picker("Vorlage", selection: templateBinding) {
                Text("Eigenes Ziel").tag(String?.none)
                ForEach(GoalTemplate.all) { template in
                    Text(template.displayName).tag(Optional(template.id))
                }
            }
        } footer: {
            Text("Die Vorlage füllt Disziplinen, Strecken und Schwerpunkte vor. Danach kannst du alles ändern.")
        }
    }

    private var templateBinding: Binding<String?> {
        Binding(
            get: { goal.template },
            set: { id in
                guard let template = GoalTemplate.template(id: id) else {
                    goal.template = nil
                    return
                }
                goal = template.goal(targetDate: goal.targetDate, trainingDaysPerWeek: goal.trainingDaysPerWeek, weeklyHours: goal.weeklyHours)
            }
        )
    }

    // MARK: - Disziplinen

    private func disciplineSection(_ sport: SportID) -> some View {
        Section {
            Toggle(isOn: disciplineBinding(sport)) {
                Label(sports.displayName(for: sport), systemImage: sports.symbolName(for: sport))
            }
            if let discipline = goal.discipline(for: sport) {
                LabeledContent("Strecke") {
                    HStack {
                        TextField("Strecke", value: kilometersBinding(sport), format: .number.precision(.fractionLength(0...3)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("km")
                    }
                }
                if let venue = sports.module(for: sport)?.openWater {
                    Toggle("Im \(venue.displayName)", isOn: openWaterBinding(sport))
                }
                if goal.kind != .distance {
                    Toggle("Zielzeit", isOn: hasTimeBinding(sport))
                }
                if discipline.targetDurationSeconds != nil {
                    LabeledContent("Zeit") {
                        HStack {
                            TextField("h", value: timePartBinding(sport, hours: true), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 50)
                            Text("h")
                            TextField("min", value: timePartBinding(sport, hours: false), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 50)
                            Text("min")
                        }
                    }
                }
            }
        }
    }

    private func disciplineBinding(_ sport: SportID) -> Binding<Bool> {
        Binding(
            get: { goal.discipline(for: sport) != nil },
            set: { isOn in
                goal = goal.settingDiscipline(isOn ? TrainingGoal.Discipline(sport: sport, distanceMeters: 5_000) : nil, for: sport)
            }
        )
    }

    private func kilometersBinding(_ sport: SportID) -> Binding<Double> {
        Binding(
            get: { (goal.discipline(for: sport)?.distanceMeters ?? 0) / 1000 },
            set: { kilometers in
                guard var discipline = goal.discipline(for: sport) else { return }
                discipline.distanceMeters = (kilometers * 1000).rounded()
                goal = goal.settingDiscipline(discipline, for: sport)
            }
        )
    }

    /// Im Freiwasser: Der Plan bringt Einheiten dorthin (mit Zugang) oder Elemente davon ins Becken.
    private func openWaterBinding(_ sport: SportID) -> Binding<Bool> {
        Binding(
            get: { goal.discipline(for: sport)?.openWater ?? false },
            set: { isOn in
                guard var discipline = goal.discipline(for: sport) else { return }
                discipline.openWater = isOn
                goal = goal.settingDiscipline(discipline, for: sport)
            }
        )
    }

    private func hasTimeBinding(_ sport: SportID) -> Binding<Bool> {
        Binding(
            get: { goal.discipline(for: sport)?.targetDurationSeconds != nil },
            set: { isOn in
                guard var discipline = goal.discipline(for: sport) else { return }
                discipline.targetDurationSeconds = isOn ? 3600 : nil
                goal = goal.settingDiscipline(discipline, for: sport)
            }
        )
    }

    private func timePartBinding(_ sport: SportID, hours: Bool) -> Binding<Int> {
        Binding(
            get: {
                let total = Int(goal.discipline(for: sport)?.targetDurationSeconds ?? 0) / 60
                return hours ? total / 60 : total % 60
            },
            set: { value in
                guard var discipline = goal.discipline(for: sport) else { return }
                let total = Int(discipline.targetDurationSeconds ?? 0) / 60
                let newHours = hours ? max(0, value) : total / 60
                let newMinutes = hours ? total % 60 : min(max(0, value), 59)
                discipline.targetDurationSeconds = TimeInterval((newHours * 60 + newMinutes) * 60)
                goal = goal.settingDiscipline(discipline, for: sport)
            }
        )
    }

    // MARK: - Schwerpunkte und Trainingszeit

    private var emphasisSection: some View {
        Section {
            ForEach(sports.ids, id: \.self) { sport in
                VStack(alignment: .leading) {
                    LabeledContent(sports.displayName(for: sport), value: "\(goal.percent(for: sport)) %")
                    Slider(value: emphasisBinding(sport), in: 0...100, step: 5)
                }
            }
        } header: {
            Text("Schwerpunkte")
        } footer: {
            Text("Wie sich dein Training auf die Sportarten verteilt. Ziehst du eine hoch, werden die anderen im Verhältnis kleiner; zusammen sind es immer 100 %.")
        }
    }

    private func emphasisBinding(_ sport: SportID) -> Binding<Double> {
        Binding(
            get: { Double(goal.percent(for: sport)) },
            set: { goal = goal.settingEmphasis(Int($0.rounded()), for: sport) }
        )
    }

    private var trainingSection: some View {
        Section {
            DatePicker(dateTitle, selection: targetDayBinding, in: Date()..., displayedComponents: .date)
            if showsSchedule {
                NavigationLink {
                    WeeklyScheduleView(store: scheduleStore, goalStore: store)
                } label: {
                    LabeledContent("Wochenraster", value: scheduleSummary)
                }
            }
        } header: {
            Text(goal.kind == .fitness ? "Zeitraum und Training" : "Zieltag und Training")
        } footer: {
            if goal.kind == .fitness {
                Text("Bis zu diesem Tag plant die App. Danach legst du einfach einen neuen Zeitraum fest.")
            }
        }
    }

    private var dateTitle: String {
        switch goal.kind {
        case .race: return String(localized: "Wettkampftag")
        case .time: return String(localized: "Tag des Versuchs")
        case .distance: return String(localized: "Zieltag")
        case .fitness: return String(localized: "Planen bis")
        }
    }

    private var targetDayBinding: Binding<Date> {
        Binding(
            get: { goal.targetDate },
            set: { goal.targetDate = AthleteGoal.targetDate(onDayOf: $0) }
        )
    }

    // MARK: - Status

    /// Einrichtung: gespeichert oder was fehlt.
    private var statusSection: some View {
        Section {
            if let problem = goal.problem(now: Date()) {
                Text("\(problem) Noch nicht gespeichert.")
                    .foregroundStyle(.red)
            } else {
                Text("Gespeichert.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }

    // MARK: - Übernehmen (Einstellungen)

    private var applySection: some View {
        let now = Date()
        let change = store.goal().change(to: goal)
        let lockedUntil = change == .newGoal ? store.lockedUntil(now: now) : nil
        return Section {
            if let problem = goal.problem(now: now) {
                Text(problem)
                    .foregroundStyle(.red)
            } else {
                switch change {
                case .none:
                    Text("Keine Änderung am Plan.")
                        .foregroundStyle(.secondary)
                case .fineTuning:
                    Text("Feinjustierung: Der Gesamtplan bleibt. Die Änderung fließt in die nächste Fortschreibung, spätestens in zwei Wochen; die laufende Woche bleibt.")
                    Button("Übernehmen") { apply(now: now) }
                case .newGoal:
                    if let lockedUntil {
                        Text("Neues Ziel: Es gibt einen neuen Gesamtplan. Das letzte neue Ziel ist keine 7 Tage her, deshalb geht es erst ab \(Self.day(lockedUntil)).")
                        Button("Vormerken bis \(Self.day(lockedUntil))") {
                            store.setPendingGoal(goal)
                            pending = goal
                            message = String(localized: "Vorgemerkt. Am \(Self.day(lockedUntil)) wird es übernommen und der neue Gesamtplan erstellt.")
                        }
                    } else {
                        Text("Neues Ziel: Die App erstellt einen neuen Gesamtplan vom aktuellen Stand aus; die laufende Woche bleibt. Danach ist 7 Tage lang kein weiteres neues Ziel möglich.")
                        Button("Übernehmen") { apply(now: now) }
                    }
                }
            }
            if change != .none {
                Button("Entwurf verwerfen", role: .destructive) {
                    goal = store.goal()
                }
            }
            if let pending {
                LabeledContent("Vorgemerkt", value: PlanFormatting.goalSummary(pending))
                Button("Vorgemerktes Ziel verwerfen", role: .destructive) {
                    store.setPendingGoal(nil)
                    self.pending = nil
                }
            }
            if let message {
                Text(message)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Übernehmen")
        }
        .font(.footnote)
    }

    private func apply(now: Date) {
        switch store.apply(goal, now: now) {
        case .unchanged:
            message = nil
        case .fineTuned:
            message = String(localized: "Übernommen. Der Gesamtplan bleibt, die nächste Fortschreibung rechnet damit.")
            pending = store.pendingGoal()
        case .newGoal:
            message = String(localized: "Übernommen. Der neue Gesamtplan entsteht jetzt im Hintergrund.")
            pending = store.pendingGoal()
            Task { await todayLoader.refreshIfNeeded() }
        case .locked(let until):
            message = String(localized: "Gesperrt bis \(Self.day(until)).")
        case .invalid(let problem):
            message = problem
        }
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(AppLocale.current))
    }
}
