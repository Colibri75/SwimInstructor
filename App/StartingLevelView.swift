import SwiftUI
import SwimInstructorCore

/// Startniveau je Sportart selbst angeben, wenn Health zu wenig zeigt (Training ohne Uhr, Pause, neues Gerät).
/// Jede Änderung wird sofort gespeichert und gilt ab dem nächsten Plan.
struct StartingLevelView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader

    private let store: StartingLevelStoring
    private let registry = SportRegistry.standard
    @State private var levels: [StartingLevel] = []
    @State private var goalSports: [SportID] = []

    init(store: StartingLevelStoring = UserDefaultsStartingLevelStore()) {
        self.store = store
    }

    var body: some View {
        Form {
            Group {
                ForEach(shownSports, id: \.self) { sport in
                    sportSection(sport)
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Startniveau")
        .navigationBarTitleDisplayMode(.inline)
        .swipeClosesKeyboard()
        .onAppear {
            levels = store.levels()
            goalSports = UserDefaultsTrainingGoalStore().goal().emphasis.filter { $0.percent > 0 }.map(\.sport)
        }
    }

    /// Die Sportarten des Ziels, dazu jede mit einer gespeicherten Angabe; in der Reihenfolge der Registry.
    private var shownSports: [SportID] {
        let wanted = Set(goalSports + levels.map(\.sport))
        return registry.ids.filter { wanted.contains($0) }
    }

    @ViewBuilder
    private func sportSection(_ sport: SportID) -> some View {
        let unit = registry.module(for: sport)?.planUnit ?? .minutes
        let health = loader.reading?.snapshot.sports?.first { $0.sport == sport }
        Section {
            if let level = levels.first(where: { $0.sport == sport }) {
                Picker("Trainingsstand", selection: binding(level, \.status)) {
                    ForEach(TrainingStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                amountField("Pro Woche", value: binding(level, \.weeklyAmount, range: StartingLevel.weeklyRange(for: unit)), unit: unit)
                amountField("Längste Einheit", value: binding(level, \.longestSession, range: StartingLevel.longestRange(for: unit)), unit: unit)
                Text(StartingLevelFormatting.validity(level, now: Date()))
                    .font(.footnote)
                    .foregroundStyle(level.isValid(now: Date()) ? Color.secondary : Theme.caution)
                Button("Angabe entfernen", role: .destructive) {
                    store.removeLevel(for: sport)
                    levels = store.levels()
                }
            } else {
                Button("Startniveau angeben") {
                    store.setLevel(StartingLevelFormatting.suggestion(sport: sport, state: health, unit: unit, now: Date()))
                    levels = store.levels()
                }
            }
            Text(StartingLevelFormatting.healthSummary(health, unit: unit))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label(registry.displayName(for: sport), systemImage: registry.symbolName(for: sport))
        } footer: {
            if sport == shownSports.last {
                Text("Gib an, was du zurzeit schaffst oder vor einer Pause geschafft hast. Der Plan rechnet mit dem höheren Wert aus Health und deiner Angabe. Nach einer Pause zählt nur ein Teil davon, beim Laufen vorsichtiger als beim Schwimmen und Radfahren. Gilt ab dem nächsten Plan.")
            }
        }
    }

    private func amountField(_ title: String, value: Binding<Double>, unit: PlanUnit) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text(unit == .meters ? "m" : "min")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Ein Umfang, auf den erlaubten Bereich begrenzt.
    private func binding(_ level: StartingLevel, _ keyPath: WritableKeyPath<StartingLevel, Double>, range: ClosedRange<Double>) -> Binding<Double> {
        let raw = binding(level, keyPath)
        return Binding(get: { raw.wrappedValue }, set: { raw.wrappedValue = min(max($0, range.lowerBound), range.upperBound) })
    }

    /// Ändert ein Feld der Angabe, speichert sofort und setzt das Datum neu (die Angabe gilt dann wieder 28 Tage).
    private func binding<Value>(_ level: StartingLevel, _ keyPath: WritableKeyPath<StartingLevel, Value>) -> Binding<Value> {
        Binding(
            get: { (levels.first { $0.sport == level.sport } ?? level)[keyPath: keyPath] },
            set: { newValue in
                var changed = levels.first { $0.sport == level.sport } ?? level
                changed[keyPath: keyPath] = newValue
                changed.reportedAt = Date()
                if store.setLevel(changed) { levels = store.levels() }
            }
        )
    }
}
