import SwiftUI
import SwimInstructorCore

/// Ziel-Assistent: Zielart wählen (Wettkampf, Zeit, Strecke, Fitness) und gleich darunter den Zieltag (Fitness hat
/// keinen), beim Wettkampf auf Wunsch eine Vorlage (Triathlon-Distanzen, Lauf, Schwimmen, Rad), dann Disziplinen mit
/// Strecke und Zielzeit und der Schwerpunkt je Sportart. Die Trainingszeit kommt aus dem Wochenraster.
///
/// Jeder weitere Wettkampf öffnet dieselbe Ansicht mit Tag, Vorlage und Disziplinen (`GoalDetailSections.swift`);
/// statt der Zielart wählt man dort, ob er Hauptziel, mit kurzem Zuspitzen oder als harte Einheit zählt.
///
/// In der Einrichtung wird ein gültiges Ziel sofort gespeichert. In den Einstellungen ist es ein Entwurf (P3): Die
/// Ansicht zeigt, was mit dem Gesamtplan passiert, und erst "Übernehmen" ändert das Ziel. Ein neues Ziel geht höchstens
/// alle 7 Tage; in der Sperre lässt es sich vormerken und wird an ihrem Ende übernommen.
struct GoalAssistantView: View {
    @AppStorage(Theme.greenWeakKey) private var greenWeak = false
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
                    GoalTemplateSection(
                        selection: goal.template,
                        ownTitle: "Eigenes Ziel",
                        footer: "Die Vorlage füllt Disziplinen, Strecken und Schwerpunkte vor. Danach kannst du alles ändern.",
                        choose: chooseTemplate
                    )
                }
                if goal.kind.hasDisciplines {
                    DisciplineSections(disciplines: goal.disciplines, offersTargetTime: goal.kind != .distance) { discipline, sport in
                        goal = goal.settingDiscipline(discipline, for: sport)
                    }
                } else {
                    sportsSection
                }
                secondaryRacesSection
                emphasisSection
                if showsSchedule {
                    scheduleSection
                }
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
        .keyboardDoneButton()
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
            if goal.kind.hasDisciplines {
                DatePicker(dateTitle, selection: targetDayBinding, in: Date()..., displayedComponents: .date)
            }
        } header: {
            Text("Hauptziel")
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

    /// Die Vorlage füllt Disziplinen und Schwerpunkte; Zieltag, Trainingszeit und weitere Wettkämpfe bleiben.
    private func chooseTemplate(_ template: GoalTemplate?) {
        guard let template else {
            goal.template = nil
            return
        }
        var filled = template.goal(targetDate: goal.targetDate, trainingDaysPerWeek: goal.trainingDaysPerWeek, weeklyHours: goal.weeklyHours)
        filled.secondaryRaces = goal.secondaryRaces
        goal = filled
    }

    // MARK: - Weitere Wettkämpfe

    private var secondaryRacesSection: some View {
        Section {
            ForEach(goal.secondaryRaces) { race in
                NavigationLink {
                    SecondaryRaceEditor(goal: $goal, raceID: race.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(race.date.formatted(.dateTime.day().month().year().locale(AppLocale.current)))
                        Text(race.summary() + " · " + race.priority.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in goal.secondaryRaces.remove(atOffsets: offsets) }
            if goal.secondaryRaces.count < SecondaryRace.maximumCount {
                Button {
                    goal.secondaryRaces.append(goal.newSecondaryRace(now: Date()))
                } label: {
                    Label("Wettkampf hinzufügen", systemImage: "plus")
                }
            }
        } header: {
            if goal.kind == .fitness {
                Text("Wettkämpfe")
            } else {
                Text("Weitere Wettkämpfe")
            }
        } footer: {
            if goal.kind == .fitness {
                Text("Wettkämpfe, die du nebenbei machst. Am Tag selbst plant dein Coach kein Training, davor und danach ruhiger. Zum Entfernen nach links wischen.")
            } else {
                Text("Kleinere Wettkämpfe auf dem Weg zum Ziel. Am Tag selbst plant dein Coach kein Training, davor und danach ruhiger. Zum Entfernen nach links wischen.")
            }
        }
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

    private var scheduleSection: some View {
        Section {
            NavigationLink {
                WeeklyScheduleView(store: scheduleStore, goalStore: store)
            } label: {
                LabeledContent("Wochenraster", value: scheduleSummary)
            }
        } header: {
            Text("Training")
        }
    }

    private var dateTitle: String {
        switch goal.kind {
        case .race: return String(localized: "Wettkampftag")
        case .time: return String(localized: "Tag des Versuchs")
        case .distance, .fitness: return String(localized: "Zieltag")
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
                    .foregroundStyle(Theme.done(greenWeak: greenWeak))
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

// MARK: - Ein weiterer Wettkampf

/// Ein weiterer Wettkampf in derselben Ansicht wie das Hauptziel: Art und Tag, Vorlage, je Sportart Strecke,
/// Freiwasser und Zielzeit. Als Art lässt er sich auch zum Hauptziel machen; das bisherige Ziel wird dann, wenn es
/// ein Wettkampf oder ein anderes Ziel mit Tag ist, ein weiterer Wettkampf mit kurzem Zuspitzen.
private struct SecondaryRaceEditor: View {
    @Binding var goal: TrainingGoal
    let raceID: SecondaryRace.ID

    @Environment(\.dismiss) private var dismiss

    /// Art des Wettkampfs in der Auswahl: Hauptziel oder eine Art von `SecondaryRace.Priority`.
    private enum Role: Hashable {
        case main
        case secondary(SecondaryRace.Priority)
    }

    private var race: SecondaryRace? {
        goal.secondaryRaces.first { $0.id == raceID }
    }

    var body: some View {
        Form {
            Group {
                if let race {
                    Section {
                        Picker("Art", selection: roleBinding(race)) {
                            Text("Hauptziel").tag(Role.main)
                            ForEach(SecondaryRace.Priority.allCases) { priority in
                                Text(priority.title).tag(Role.secondary(priority))
                            }
                        }
                        DatePicker("Wettkampftag", selection: dayBinding(race), in: Date()..., displayedComponents: .date)
                    } header: {
                        Text("Weiterer Wettkampf")
                    } footer: {
                        Text(race.priority.explanation + " " + String(localized: "Als Hauptziel tauscht er mit deinem Ziel: Ein bisheriges Ziel mit Tag wird dann ein weiterer Wettkampf mit kurzem Zuspitzen."))
                    }
                    GoalTemplateSection(
                        selection: race.template,
                        ownTitle: "Eigener Wettkampf",
                        footer: "Die Vorlage füllt Disziplinen und Strecken vor. Danach kannst du alles ändern."
                    ) { template in
                        change { race in
                            if let template {
                                race = race.applyingTemplate(template)
                            } else {
                                race.template = nil
                            }
                        }
                    }
                    DisciplineSections(disciplines: race.disciplines) { discipline, sport in
                        change { $0 = $0.settingDiscipline(discipline, for: sport) }
                    }
                    if let problem = race.problem() {
                        Section {
                            Text(problem)
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button("Wettkampf entfernen", role: .destructive) {
                            goal.secondaryRaces.removeAll { $0.id == raceID }
                            dismiss()
                        }
                    }
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Wettkampf")
        .navigationBarTitleDisplayMode(.inline)
        .swipeClosesKeyboard()
        .keyboardDoneButton()
    }

    private func change(_ body: (inout SecondaryRace) -> Void) {
        guard let index = goal.secondaryRaces.firstIndex(where: { $0.id == raceID }) else { return }
        body(&goal.secondaryRaces[index])
    }

    private func roleBinding(_ race: SecondaryRace) -> Binding<Role> {
        Binding(
            get: { .secondary(race.priority) },
            set: { role in
                switch role {
                case .main:
                    goal = goal.promotingSecondaryRace(raceID, now: Date())
                    dismiss()
                case .secondary(let priority):
                    change { $0.priority = priority }
                }
            }
        )
    }

    private func dayBinding(_ race: SecondaryRace) -> Binding<Date> {
        Binding(
            get: { race.date },
            set: { day in change { $0.date = AthleteGoal.targetDate(onDayOf: day) } }
        )
    }
}
