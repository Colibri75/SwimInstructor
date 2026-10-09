import SwiftUI
import SwimInstructorCore

/// Wochenraster: je Wochentag, ob und wann trainiert wird, wie lange höchstens und auf Wunsch nur eine Sportart.
/// Ein gültiger Wochenraster wird sofort gespeichert und gilt ab der nächsten Abstimmung der 14 Tage.
struct WeeklyScheduleView: View {
    private let store: WeeklyScheduleStoring
    private let goalStore: TrainingGoalStoring
    private let registry = SportRegistry.standard

    @State private var schedule = WeeklySchedule(trainingDaysPerWeek: 4, weeklyHours: 6)
    @State private var goalSports: [SportID] = []
    @State private var loaded = false

    init(store: WeeklyScheduleStoring = UserDefaultsWeeklyScheduleStore(), goalStore: TrainingGoalStoring = UserDefaultsTrainingGoalStore()) {
        self.store = store
        self.goalStore = goalStore
    }

    var body: some View {
        Form {
            Group {
                ForEach(schedule.days) { day in
                    daySection(day)
                }
                statusSection
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Wochenraster")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Bei jedem Erscheinen neu: In der Einrichtung kann sich das Ziel davor geändert haben.
            let goal = goalStore.goal()
            goalSports = goal.sports
            if !loaded {
                schedule = store.schedule(for: goal)
                loaded = true
            }
        }
        .onChange(of: schedule) { _, newSchedule in
            guard loaded else { return }
            store.setSchedule(newSchedule)
        }
    }

    private func daySection(_ day: WeeklySchedule.Day) -> some View {
        Section {
            Toggle(day.name, isOn: binding(day.weekday, \.trains))
                .font(.headline)
            if day.trains {
                Picker("Tageszeit", selection: binding(day.weekday, \.timeOfDay)) {
                    Text("Egal").tag(WeeklySchedule.TimeOfDay?.none)
                    ForEach(WeeklySchedule.TimeOfDay.allCases) { time in
                        Text(time.title).tag(Optional(time))
                    }
                }
                Stepper(value: binding(day.weekday, \.maxMinutes), in: WeeklySchedule.minutesRange, step: WeeklySchedule.minutesStep) {
                    LabeledContent("Höchstens", value: String(localized: "\(day.maxMinutes) min"))
                }
                Picker("Sportart", selection: binding(day.weekday, \.sport)) {
                    Text("Wie es passt").tag(SportID?.none)
                    ForEach(sportChoices(for: day), id: \.self) { sport in
                        Text("Nur \(registry.displayName(for: sport))").tag(Optional(sport))
                    }
                }
            }
        }
    }

    /// Die Sportarten des Ziels, dazu eine schon gewählte, die nicht mehr im Ziel ist (der Server übergeht sie).
    private func sportChoices(for day: WeeklySchedule.Day) -> [SportID] {
        let wanted = Set(goalSports + [day.sport].compactMap { $0 })
        return registry.ids.filter { wanted.contains($0) }
    }

    private func binding<Value>(_ weekday: Int, _ keyPath: WritableKeyPath<WeeklySchedule.Day, Value>) -> Binding<Value> {
        Binding(
            get: { schedule.day(weekday)![keyPath: keyPath] },
            set: { value in
                guard var day = schedule.day(weekday) else { return }
                day[keyPath: keyPath] = value
                // Ein neuer Trainingstag startet mit einer Stunde.
                if (keyPath as AnyKeyPath) == (\WeeklySchedule.Day.trains as AnyKeyPath), day.trains, day.maxMinutes == 0 {
                    day.maxMinutes = 60
                }
                schedule = schedule.setting(day)
            }
        )
    }

    private var statusSection: some View {
        Section {
            if let problem = schedule.problem() {
                Text("\(problem) Noch nicht gespeichert.")
                    .foregroundStyle(.red)
            } else {
                LabeledContent("Zusammen", value: schedule.summary)
            }
        } footer: {
            Text("Der Plan legt Training nur auf deine Trainingstage und bleibt unter der Zeit des Tages. Mit einer festen Sportart gibt es an dem Tag nur diese. Änderungen gelten ab der nächsten Abstimmung der 14 Tage, der Gesamtplan bleibt.")
        }
        .font(.footnote)
    }
}
