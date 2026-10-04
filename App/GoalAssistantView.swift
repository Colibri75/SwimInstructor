import SwiftUI
import SwimInstructorCore

/// Ziel-Assistent: Vorlage wählen (Triathlon-Distanzen, Lauf, Schwimmen, Rad) oder alles selbst einstellen.
/// Disziplinen mit Strecke und Zielzeit, Zieltag, Trainingstage, Stunden pro Woche und der Schwerpunkt je Sportart.
/// Ein gültiges Ziel wird sofort gespeichert.
struct GoalAssistantView: View {
    private let store: TrainingGoalStoring
    private let sports = SportRegistry.standard

    @State private var goal = TrainingGoal.default
    @State private var loaded = false

    init(store: TrainingGoalStoring = UserDefaultsTrainingGoalStore()) {
        self.store = store
    }

    var body: some View {
        Form {
            templateSection
            ForEach(sports.ids, id: \.self) { sport in
                disciplineSection(sport)
            }
            emphasisSection
            trainingSection
            statusSection
        }
        .navigationTitle("Mein Ziel")
        .swipeClosesKeyboard()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            goal = store.goal()
            loaded = true
        }
        .onChange(of: goal) { _, newGoal in
            guard loaded else { return }
            store.setGoal(newGoal, now: Date())
        }
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
                Toggle("Zielzeit", isOn: hasTimeBinding(sport))
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
        Section("Zieltag und Training") {
            DatePicker("Zieltag", selection: targetDayBinding, in: Date()..., displayedComponents: .date)
            Stepper(value: $goal.trainingDaysPerWeek, in: TrainingGoal.trainingDaysRange) {
                LabeledContent("Trainingstage", value: "\(goal.trainingDaysPerWeek) pro Woche")
            }
            Stepper(value: $goal.weeklyHours, in: TrainingGoal.weeklyHoursRange, step: 0.5) {
                LabeledContent("Trainingszeit", value: "\(goal.weeklyHours.formatted(.number.precision(.fractionLength(0...1)))) h pro Woche")
            }
        }
    }

    private var targetDayBinding: Binding<Date> {
        Binding(
            get: { goal.targetDate },
            set: { goal.targetDate = AthleteGoal.targetDate(onDayOf: $0) }
        )
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            if let problem = goal.problem(now: Date()) {
                Text("\(problem) Noch nicht gespeichert.")
                    .foregroundStyle(.red)
            } else {
                Text("Gespeichert. Der nächste Plan richtet sich danach (auf Heute nach unten ziehen, im Tab Plan neu planen).")
                    .foregroundStyle(.secondary)
            }
            Button("Auf das Standardziel zurücksetzen (3,8 km Schwimmen)") {
                store.resetGoal()
                goal = store.goal()
            }
        } footer: {
            Text("Bis zum nächsten großen Update plant der Server nur Schwimmen. Rad und Laufen gehen schon als Belastung in den Plan ein.")
        }
        .font(.footnote)
    }
}
