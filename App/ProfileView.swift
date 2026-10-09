import SwiftUI
import SwimInstructorCore

/// Leistungsprofil: die Werte, nach denen Zonen und Tempo im Plan entstehen, je Sportart mit Herkunft und Verlauf. Werte
/// lassen sich von Hand ändern, Testergebnisse gelten erst nach Bestätigung. Dazu die Einstellungen für Leistungstests.
struct ProfileView: View {
    @EnvironmentObject private var profileLoader: PerformanceProfileLoader

    @State private var testSettings = TestSettings.standard
    @State private var resultTest: TestResultTarget?
    @State private var confirmsReset = false

    private let testSettingsStore = UserDefaultsTestSettingsStore()
    private let registry = SportRegistry.standard

    /// Sportarten mit Leistungswerten, in der Reihenfolge der Registry.
    private var sportIDs: [SportID] {
        registry.ids.filter { registry.module(for: $0)?.performanceMetrics.isEmpty == false }
    }

    var body: some View {
        List {
            Group {
                Section {
                    ForEach(profileLoader.entries(for: nil)) { entry in
                        entryLink(entry)
                    }
                } header: {
                    Text("Für alle Sportarten")
                }
                ForEach(sportIDs, id: \.self) { sport in
                    Section {
                        ForEach(profileLoader.entries(for: sport)) { entry in
                            entryLink(entry)
                        }
                        if !hasConfirmedValue(sport) {
                            Text(testSettings.offer
                                 ? "Noch kein Test. In der ersten Woche plant die App einen Einstiegstest ein, danach alle \(testSettings.intervalWeeks) Wochen einen Test."
                                 : "Noch kein Test. Die Werte sind aus deinen Einheiten geschätzt.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Label(registry.displayName(for: sport), systemImage: registry.symbolName(for: sport))
                    }
                }
                resultSection
                testSettingsSection
                Section {
                    Button("Alle bestätigten Werte löschen", role: .destructive) { confirmsReset = true }
                } footer: {
                    Text("Danach gelten wieder die Schätzungen aus Health.")
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Leistungsprofil")
        .onAppear { testSettings = testSettingsStore.settings() }
        .onChange(of: testSettings) { _, settings in testSettingsStore.save(settings) }
        .sheet(item: $resultTest) { target in
            TestResultSheet(sport: target.sport, testID: target.testID)
        }
        .confirmationDialog("Alle bestätigten Werte löschen?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { profileLoader.reset() }
        } message: {
            Text("Getestete und von dir eingetragene Werte samt Verlauf gehen verloren.")
        }
    }

    private func entryLink(_ entry: PerformanceProfileLoader.Entry) -> some View {
        NavigationLink {
            ProfileEntryDetailView(sport: entry.sport, metric: entry.definition.metric)
        } label: {
            ProfileEntryRow(entry: entry)
        }
    }

    private func tests(of sport: SportID) -> [PerformanceTest] {
        registry.module(for: sport)?.performanceTests ?? []
    }

    private func hasConfirmedValue(_ sport: SportID) -> Bool {
        profileLoader.entries(for: sport).contains { $0.current?.source.isConfirmed == true }
    }

    // MARK: - Testergebnis

    private var resultSection: some View {
        Section {
            Menu("Testergebnis eintragen") {
                ForEach(sportIDs, id: \.self) { sport in
                    ForEach(tests(of: sport).filter(\.maximalEffort)) { test in
                        Button("\(registry.displayName(for: sport)): \(test.displayName)") {
                            resultTest = TestResultTarget(sport: sport, testID: test.id)
                        }
                    }
                }
            }
        } footer: {
            Text("Nach einem Test trägst du hier oder im Tab Aktuell dein Ergebnis ein. Die App zeigt den Vergleich zum bisherigen Wert; übernommen wird erst nach deiner Bestätigung.")
        }
    }

    // MARK: - Leistungstests

    private var testSettingsSection: some View {
        Section {
            Toggle("Tests anbieten", isOn: $testSettings.offer)
            if testSettings.offer {
                Stepper(value: $testSettings.intervalWeeks, in: TestSettings.intervalRange) {
                    Text("Alle \(testSettings.intervalWeeks) Wochen")
                }
                ForEach(sportIDs, id: \.self) { sport in
                    if tests(of: sport).count > 1 {
                        Picker(registry.displayName(for: sport), selection: preferredBinding(for: sport)) {
                            Text("Standard").tag("")
                            ForEach(tests(of: sport)) { test in
                                Text(test.displayName).tag(test.id)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Leistungstests")
        } footer: {
            Text("Tests sind freiwillig. Mit Angebot plant die App in der ersten Woche Einstiegstests ein und wiederholt sie im eingestellten Abstand, nie in den letzten zwei Wochen vor dem Ziel. Ein Test ersetzt eine harte Einheit.")
        }
    }

    private func preferredBinding(for sport: SportID) -> Binding<String> {
        Binding(
            get: { testSettings.preferredTest(for: sport) ?? "" },
            set: { testSettings = testSettings.preferring($0.isEmpty ? nil : $0, for: sport) }
        )
    }
}

/// Ein Leistungswert in der Liste: Name, Wert, Herkunft und Datum.
private struct ProfileEntryRow: View {
    let entry: PerformanceProfileLoader.Entry

    var body: some View {
        LabeledContent {
            if let current = entry.current {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PlanV2Formatting.performanceValue(current.value, unit: entry.definition.unit))
                        .monospacedDigit()
                    Text("\(PlanV2Formatting.origin(current.source)), \(current.measuredAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("kein Wert")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(entry.definition.displayName)
        }
    }
}

/// Ein Leistungswert im Detail: aktueller Wert, Verlauf und Eingabe von Hand.
struct ProfileEntryDetailView: View {
    let sport: SportID?
    let metric: PerformanceMetric

    @EnvironmentObject private var profileLoader: PerformanceProfileLoader
    @State private var text = ""
    @State private var saved = false

    init(sport: SportID?, metric: PerformanceMetric) {
        self.sport = sport
        self.metric = metric
    }

    private var entry: PerformanceProfileLoader.Entry? {
        profileLoader.entries(for: sport).first { $0.definition.metric == metric }
    }

    var body: some View {
        List {
            Group {
                if let entry {
                    Section {
                        ProfileEntryRow(entry: entry)
                        if entry.current?.source.isConfirmed == false {
                            Text("Geschätzt aus deinen Einheiten. Ein Test oder ein Wert von dir geht immer vor.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    manualSection(entry.definition)
                    Section("Verlauf") {
                        if entry.history.isEmpty {
                            Text("Noch kein bestätigter Wert.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(entry.history.reversed().enumerated()), id: \.offset) { _, value in
                                LabeledContent {
                                    Text(PlanV2Formatting.performanceValue(value.value, unit: entry.definition.unit))
                                        .monospacedDigit()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(value.measuredAt.formatted(date: .abbreviated, time: .omitted))
                                        Text(PlanV2Formatting.origin(value.source))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(entry?.definition.displayName ?? String(localized: "Leistungswert"))
        .swipeClosesKeyboard()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func manualSection(_ definition: PerformanceMetricDefinition) -> some View {
        let isTime = PlanV2Formatting.isTimeUnit(definition.unit)
        return Section {
            HStack {
                TextField(isTime ? "m:ss" : definition.unit, text: $text)
                    .keyboardType(isTime ? .numbersAndPunctuation : .decimalPad)
                Button("Speichern") {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    let value = isTime ? PlanV2Formatting.parseTime(trimmed) : Double(trimmed.replacingOccurrences(of: ",", with: "."))
                    guard let value else {
                        saved = false
                        return
                    }
                    saved = profileLoader.setManual(value, metric: definition.metric, sport: sport)
                    if saved { text = "" }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error = profileLoader.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if saved {
                Label("Gespeichert, gilt ab dem nächsten Plan.", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Von Hand eintragen")
        } footer: {
            Text(isTime
                 ? "Als Minuten:Sekunden, z. B. 1:45. Erlaubt: \(PlanV2Formatting.performanceValue(definition.plausibleRange.lowerBound, unit: definition.unit)) bis \(PlanV2Formatting.performanceValue(definition.plausibleRange.upperBound, unit: definition.unit))."
                 : "Erlaubt: \(PlanV2Formatting.performanceValue(definition.plausibleRange.lowerBound, unit: definition.unit)) bis \(PlanV2Formatting.performanceValue(definition.plausibleRange.upperBound, unit: definition.unit)).")
        }
    }
}
