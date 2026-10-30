import SwiftUI
import SwimInstructorCore

// Bausteine, die das Hauptziel und jeder weitere Wettkampf gemeinsam haben, damit alle gleich aussehen und sich
// gleich bearbeiten lassen: Vorlage und je Sportart Strecke, Freiwasser und Zielzeit.

/// Vorlage (Triathlon-Distanzen, Lauf, Schwimmen, Rad) oder eigenes Ziel. `choose` bekommt `nil` für "eigenes".
struct GoalTemplateSection: View {
    let selection: String?
    let ownTitle: LocalizedStringKey
    let footer: LocalizedStringKey
    let choose: (GoalTemplate?) -> Void

    var body: some View {
        Section {
            Picker("Vorlage", selection: Binding(get: { selection }, set: { choose(GoalTemplate.template(id: $0)) })) {
                Text(ownTitle).tag(String?.none)
                ForEach(GoalTemplate.all) { template in
                    Text(template.displayName).tag(Optional(template.id))
                }
            }
        } footer: {
            Text(footer)
        }
    }
}

/// Je Sportart ein Abschnitt: an oder aus, Strecke, im Freiwasser (wo es das gibt) und Zielzeit.
struct DisciplineSections: View {
    let disciplines: [TrainingGoal.Discipline]
    /// Ohne bei "Strecke schaffen".
    var offersTargetTime = true
    /// Setzt die Disziplin einer Sportart oder nimmt sie heraus (`nil`).
    let update: (TrainingGoal.Discipline?, SportID) -> Void

    private let sports = SportRegistry.standard

    var body: some View {
        ForEach(sports.ids, id: \.self) { sport in
            section(sport)
        }
    }

    private func discipline(for sport: SportID) -> TrainingGoal.Discipline? {
        disciplines.first { $0.sport == sport }
    }

    private func section(_ sport: SportID) -> some View {
        Section {
            Toggle(isOn: disciplineBinding(sport)) {
                Label(sports.displayName(for: sport), systemImage: sports.symbolName(for: sport))
            }
            if let discipline = discipline(for: sport) {
                LabeledContent("Strecke") {
                    HStack {
                        TextField("Strecke", value: kilometersBinding(sport), format: .number.precision(.fractionLength(0...3)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                            .inputField()
                        Text("km")
                    }
                }
                if let venue = sports.module(for: sport)?.openWater {
                    Toggle("Im \(venue.displayName)", isOn: openWaterBinding(sport))
                }
                if offersTargetTime {
                    Toggle("Zielzeit", isOn: hasTimeBinding(sport))
                }
                if discipline.targetDurationSeconds != nil {
                    LabeledContent("Zeit") {
                        HStack {
                            TextField("h", value: timePartBinding(sport, hours: true), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .inputField(minWidth: 0)
                            Text("h")
                            TextField("min", value: timePartBinding(sport, hours: false), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .inputField(minWidth: 0)
                            Text("min")
                        }
                    }
                }
            }
        }
    }

    /// Ändert die vorhandene Disziplin einer Sportart.
    private func change(_ sport: SportID, _ body: (inout TrainingGoal.Discipline) -> Void) {
        guard var discipline = discipline(for: sport) else { return }
        body(&discipline)
        update(discipline, sport)
    }

    private func disciplineBinding(_ sport: SportID) -> Binding<Bool> {
        Binding(
            get: { discipline(for: sport) != nil },
            set: { isOn in update(isOn ? TrainingGoal.Discipline(sport: sport, distanceMeters: 5_000) : nil, sport) }
        )
    }

    private func kilometersBinding(_ sport: SportID) -> Binding<Double> {
        Binding(
            get: { (discipline(for: sport)?.distanceMeters ?? 0) / 1000 },
            set: { kilometers in change(sport) { $0.distanceMeters = (kilometers * 1000).rounded() } }
        )
    }

    /// Im Freiwasser: Der Plan bringt Einheiten dorthin (mit Zugang) oder Elemente davon ins Becken.
    private func openWaterBinding(_ sport: SportID) -> Binding<Bool> {
        Binding(
            get: { discipline(for: sport)?.openWater ?? false },
            set: { isOn in change(sport) { $0.openWater = isOn } }
        )
    }

    private func hasTimeBinding(_ sport: SportID) -> Binding<Bool> {
        Binding(
            get: { discipline(for: sport)?.targetDurationSeconds != nil },
            set: { isOn in change(sport) { $0.targetDurationSeconds = isOn ? 3600 : nil } }
        )
    }

    private func timePartBinding(_ sport: SportID, hours: Bool) -> Binding<Int> {
        Binding(
            get: {
                let total = Int(discipline(for: sport)?.targetDurationSeconds ?? 0) / 60
                return hours ? total / 60 : total % 60
            },
            set: { value in
                change(sport) { discipline in
                    let total = Int(discipline.targetDurationSeconds ?? 0) / 60
                    let newHours = hours ? max(0, value) : total / 60
                    let newMinutes = hours ? total % 60 : min(max(0, value), 59)
                    discipline.targetDurationSeconds = TimeInterval((newHours * 60 + newMinutes) * 60)
                }
            }
        )
    }
}
