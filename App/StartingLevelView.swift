import SwiftUI
import SwimInstructorCore

/// Startniveau je Sportart selbst angeben, wenn Health zu wenig zeigt (Training ohne Uhr, Pause, neues Gerät).
/// Jede Änderung wird sofort gespeichert und gilt ab dem nächsten Plan.
struct StartingLevelView: View {
    @EnvironmentObject private var loader: MultiSportTodayLoader
    @EnvironmentObject private var profileLoader: PerformanceProfileLoader

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
        .keyboardDoneButton()
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
                if let module = registry.module(for: sport) {
                    paceFields(level, module: module)
                }
                Text(StartingLevelFormatting.validity(level, now: Date()))
                    .font(.footnote)
                    .foregroundStyle(level.isValid(now: Date()) ? Color.secondary : Color.orange)
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
                Text("Gib an, was du zurzeit schaffst oder vor einer Pause geschafft hast. Der Plan rechnet mit dem höheren Wert aus Health und deiner Angabe. Nach einer Pause zählt nur ein Teil davon, beim Laufen vorsichtiger als beim Schwimmen und Radfahren. Tempo, Bestzeit und FTP sind freiwillig; dein Coach richtet danach das Tempo der Einheiten, bis ein Test oder ein Wert im Leistungsprofil vorliegt. Gilt ab dem nächsten Plan.")
            }
        }
    }

    /// Optional: übliches Tempo, Bestzeiten und beim Rad die FTP. Ein leeres Feld heißt "keine Angabe".
    @ViewBuilder
    private func paceFields(_ level: StartingLevel, module: any SportModule) -> some View {
        if let pace = module.startingPace {
            OptionalValueField(
                title: pace.target == .speed ? "Durchschnittstempo" : "Übliches Tempo",
                placeholder: pace.target == .speed ? "25" : "m:ss",
                unit: StartingLevelFormatting.paceUnit(pace),
                keyboard: pace.target == .speed ? .decimalPad : .numbersAndPunctuation,
                value: level.pace,
                format: { StartingLevelFormatting.paceText($0, pace: pace) },
                parse: { StartingLevelFormatting.parsePace($0, pace: pace) },
                commit: { value in update(level) { $0.pace = value } }
            )
        }
        ForEach(module.bestTimeDistances, id: \.self) { meters in
            OptionalValueField(
                title: "Bestzeit \(StartingLevelFormatting.distanceText(meters))",
                placeholder: meters >= 10_000 ? "h:mm:ss" : "mm:ss",
                unit: "",
                keyboard: .numbersAndPunctuation,
                value: level.bestTime(over: meters),
                format: StartingLevelFormatting.clockText,
                parse: StartingLevelFormatting.parseClock,
                commit: { value in update(level) { $0.setBestTime(value, over: meters) } }
            )
        }
        if module.performanceMetrics.contains(where: { $0.metric == PerformanceMetric.thresholdPower }) {
            let current = profileLoader.current(.thresholdPower, sport: module.id)
            OptionalValueField(
                title: "FTP, falls bekannt",
                placeholder: "250",
                unit: "W",
                keyboard: .numberPad,
                value: current?.source.isConfirmed == true ? current?.value : nil,
                format: { String(Int($0.rounded())) },
                parse: { Double($0) },
                commit: { value in
                    // Die FTP gehört ins Leistungsprofil; leer lassen ändert dort nichts.
                    guard let value else { return true }
                    if current?.value == value { return true }
                    return profileLoader.setManual(value, metric: .thresholdPower, sport: module.id)
                }
            )
        }
    }

    /// Ändert die Angabe, speichert sofort und setzt das Datum neu. `false`, wenn der Wert nicht zur Sportart passt.
    private func update(_ level: StartingLevel, _ change: (inout StartingLevel) -> Void) -> Bool {
        var changed = levels.first { $0.sport == level.sport } ?? level
        change(&changed)
        changed.reportedAt = Date()
        guard store.setLevel(changed) else { return false }
        levels = store.levels()
        return true
    }

    private func amountField(_ title: LocalizedStringKey, value: Binding<Double>, unit: PlanUnit) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
                    .inputField()
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

/// Ein freiwilliges Eingabefeld (Tempo, Bestzeit, FTP): übernimmt den Wert, sobald das Feld den Fokus verliert. Leer heißt
/// keine Angabe; passt der Text nicht, bleibt der alte Wert und das Feld sagt, was erwartet wird.
private struct OptionalValueField: View {
    let title: LocalizedStringKey
    let placeholder: String
    let unit: String
    let keyboard: UIKeyboardType
    let value: Double?
    let format: (Double) -> String
    let parse: (String) -> Double?
    let commit: @MainActor (Double?) -> Bool

    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                        .inputField()
                        .focused($focused)
                    if !unit.isEmpty {
                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if invalid {
                Text("Dieser Wert passt nicht, Beispiel: \(placeholder)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { text = value.map(format) ?? "" }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { save() }
        }
        .onDisappear { if focused { save() } }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            invalid = !commit(nil)
            return
        }
        guard let parsed = parse(trimmed) else {
            invalid = true
            return
        }
        invalid = !commit(parsed)
        if !invalid { text = format(parsed) }
    }
}
