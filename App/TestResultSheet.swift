import SwiftUI
import SwimInstructorCore

/// Ergebnis eines Leistungstests eintragen: Zeiten oder Werte eingeben, dann den neuen Wert mit dem bisherigen
/// vergleichen und erst nach "Übernehmen" ins Profil schreiben. Ein Sprung über 10 % ist als "bitte prüfen" markiert.
///
/// Mit einem Ergebnis von der Watch sind die Felder schon ausgefüllt und der Vergleich steht gleich da. Übernehmen oder
/// Verwerfen nimmt es aus dem Eingang; Abbrechen lässt es dort für später.
struct TestResultSheet: View {
    let sport: SportID
    let testID: String
    let watchResult: WatchTestResult?

    @EnvironmentObject private var profileLoader: PerformanceProfileLoader
    @EnvironmentObject private var testResultInbox: WatchTestResultInbox
    @Environment(\.dismiss) private var dismiss

    @State private var texts: [String: String] = [:]
    @State private var measuredAt = Date()
    @State private var didPrefill = false

    private let registry = SportRegistry.standard

    init(sport: SportID, testID: String, watchResult: WatchTestResult? = nil) {
        self.sport = sport
        self.testID = testID
        self.watchResult = watchResult
    }

    private var module: (any SportModule)? { registry.module(for: sport) }
    private var test: PerformanceTest? { module?.performanceTests.first { $0.id == testID } }

    /// Das vorgelegte Ergebnis, wenn es zu diesem Test gehört.
    private var pending: PerformanceProfileLoader.PendingResult? {
        guard let pending = profileLoader.pending, pending.sport == sport, pending.testID == testID else { return nil }
        return pending
    }

    var body: some View {
        NavigationStack {
            Form {
                if let test, let module {
                    if let pending {
                        resultSections(pending)
                    } else if test.maximalEffort {
                        inputSections(test, module: module)
                    } else {
                        Section {
                            Text(test.resultHint.isEmpty ? "Dieser Test ändert dein Profil nicht." : test.resultHint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("Diesen Test kennt die App nicht.")
                        .foregroundStyle(.secondary)
                }
                if let error = profileLoader.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle(test?.displayName ?? "Testergebnis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        profileLoader.discard()
                        dismiss()
                    }
                }
            }
        }
        .onAppear(perform: prefillFromWatch)
        // Ohne "Übernehmen" geschlossen: Das Ergebnis gilt als verworfen.
        .onDisappear {
            if pending != nil { profileLoader.discard() }
        }
    }

    /// Die Werte der Watch in die Felder (Zeiten als m:ss) und gleich auswerten.
    private func prefillFromWatch() {
        guard let watchResult, !didPrefill, let test, let module else { return }
        didPrefill = true
        for input in test.resultInputs(definitions: module.performanceMetrics) {
            guard let value = watchResult.entries[input.id] else { continue }
            texts[input.id] = PlanV2Formatting.isTimeUnit(input.unit) ? PlanFormatting.pace(value) : "\(Int(value.rounded()))"
        }
        measuredAt = watchResult.measuredAt
        profileLoader.propose(testID: testID, sport: sport, entries: watchResult.entries, measuredAt: watchResult.measuredAt)
    }

    /// Erledigt: Das Ergebnis der Watch verlässt den Eingang.
    private func finishWatchResult() {
        if let watchResult { testResultInbox.remove(watchResult.id) }
    }

    // MARK: - Eingabe

    @ViewBuilder
    private func inputSections(_ test: PerformanceTest, module: any SportModule) -> some View {
        let inputs = test.resultInputs(definitions: module.performanceMetrics)
        Section {
            ForEach(inputs) { input in
                LabeledContent(input.isOptional ? "\(input.label) (optional)" : input.label) {
                    TextField(placeholder(for: input), text: binding(for: input.id))
                        .keyboardType(PlanV2Formatting.isTimeUnit(input.unit) ? .numbersAndPunctuation : .decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
            DatePicker("Gemacht am", selection: $measuredAt, in: ...Date(), displayedComponents: .date)
        } header: {
            Text(registry.displayName(for: sport))
        } footer: {
            Text(test.resultHint)
        }
        Section {
            Button("Auswerten") {
                profileLoader.propose(testID: test.id, sport: sport, entries: values(for: inputs), measuredAt: measuredAt)
            }
            .disabled(!hasRequiredInputs(inputs))
        }
    }

    private func placeholder(for input: TestInput) -> String {
        if PlanV2Formatting.isTimeUnit(input.unit) { return "m:ss" }
        return input.unit
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { texts[id] ?? "" },
            set: { texts[id] = $0 }
        )
    }

    /// Zeiten als m:ss oder Sekunden, Zahlen auch mit Komma. Was sich nicht lesen lässt, fehlt.
    private func values(for inputs: [TestInput]) -> [String: Double] {
        var result: [String: Double] = [:]
        for input in inputs {
            let text = (texts[input.id] ?? "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let value = PlanV2Formatting.isTimeUnit(input.unit)
                ? PlanV2Formatting.parseTime(text)
                : Double(text.replacingOccurrences(of: ",", with: "."))
            if let value { result[input.id] = value }
        }
        return result
    }

    private func hasRequiredInputs(_ inputs: [TestInput]) -> Bool {
        let filled = inputs.filter { !(texts[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        let required = inputs.filter { !$0.isOptional }
        return !filled.isEmpty && required.allSatisfy { input in filled.contains { $0.id == input.id } }
    }

    // MARK: - Ergebnis

    @ViewBuilder
    private func resultSections(_ pending: PerformanceProfileLoader.PendingResult) -> some View {
        Section {
            ForEach(pending.proposals) { proposal in
                ProposalRow(proposal: proposal)
            }
        } header: {
            Text("Ergebnis vom \(pending.measuredAt.formatted(date: .abbreviated, time: .omitted))")
        } footer: {
            if pending.needsReview {
                Text("Ein Wert weicht um mehr als \(Int(PerformanceProfileLoader.reviewThresholdPercent)) % vom bisherigen ab. Das ist eher ein Tipp- oder Messfehler als echter Fortschritt: Prüf die Eingabe, bevor du übernimmst.")
            } else {
                Text("Nach dem Übernehmen richten sich Zonen und Tempo im Plan nach dem neuen Wert.")
            }
        }
        Section {
            Button("Übernehmen") {
                if profileLoader.accept() {
                    finishWatchResult()
                    dismiss()
                }
            }
            .bold()
            Button("Eingabe korrigieren") { profileLoader.discard() }
            Button("Verwerfen", role: .destructive) {
                profileLoader.discard()
                finishWatchResult()
                dismiss()
            }
        }
    }
}

/// Ein Wert aus dem Testergebnis neben dem bisherigen.
private struct ProposalRow: View {
    let proposal: PerformanceProfileLoader.Proposal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.definition.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(PlanV2Formatting.performanceValue(proposal.value, unit: proposal.definition.unit))
                    .font(.title3.monospacedDigit().bold())
            }
            if let previous = proposal.previous {
                HStack {
                    Text("Bisher \(PlanV2Formatting.performanceValue(previous.value, unit: proposal.definition.unit))")
                    Text("(\(PlanV2Formatting.origin(previous.source)), \(previous.measuredAt.formatted(date: .abbreviated, time: .omitted)))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let change = proposal.changePercent {
                        Text(PlanV2Formatting.changePercent(change))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
            } else {
                Text("Noch kein bisheriger Wert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if proposal.needsReview {
                Label("bitte prüfen", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
