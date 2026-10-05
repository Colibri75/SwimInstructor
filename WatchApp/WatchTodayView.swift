import SwiftUI
import SwimInstructorCore

/// Startbildschirm der Watch: die Einheiten des Tages vom iPhone und freies Training in jeder Sportart.
struct WatchTodayView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var planStore: WatchPlanStore

    private let registry = SportRegistry.standard

    var body: some View {
        NavigationStack {
            List {
                planSections
                Section {
                    ForEach(registry.ids, id: \.self) { sport in
                        NavigationLink {
                            WatchStartView(sport: sport, session: nil)
                        } label: {
                            Label(registry.displayName(for: sport), systemImage: registry.symbolName(for: sport))
                        }
                    }
                } header: {
                    Text("Freies Training")
                }
                if !healthKitManager.isAuthorized {
                    Section {
                        Button("Health-Zugriff erlauben") {
                            Task { try? await healthKitManager.requestAuthorization() }
                        }
                    } footer: {
                        Text("Nötig, um Strecke, Puls und Bahnen aufzuzeichnen.")
                    }
                }
            }
            .navigationTitle("Heute")
        }
        // Einmal vorab fragen, damit der Health-Dialog nicht erst am Start erscheint.
        .task { try? await healthKitManager.requestAuthorization() }
    }

    // MARK: - Plan

    @ViewBuilder
    private var planSections: some View {
        if let response = planStore.response {
            let plan = response.plan
            if let notice = PlanV2Formatting.sourceNotice(response) ?? PlanV2Formatting.dayNotice(response, now: .now) {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            if plan.isRestDay {
                Section {
                    Text("Ruhetag")
                        .font(.headline)
                    if !plan.rationale.isEmpty {
                        Text(plan.rationale)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    refreshButton
                } header: {
                    Text("Plan")
                }
            } else {
                ForEach(Array(plan.sessions.enumerated()), id: \.offset) { index, session in
                    sessionSection(session, previous: index > 0 ? plan.sessions[index - 1].sport : nil)
                }
                Section {
                    ForEach(plan.coachNotes, id: \.self) { note in
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    refreshButton
                }
            }
        } else {
            Section {
                Text("Noch kein Plan. Öffne die App auf dem iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                refreshButton
            } header: {
                Text("Plan")
            }
        }
    }

    private func sessionSection(_ session: DaySession, previous: SportID?) -> some View {
        Section {
            NavigationLink {
                WatchStartView(sport: session.sport, session: session)
            } label: {
                Label(session.test.map { "Test starten: \($0.displayName)" } ?? "Starten", systemImage: registry.symbolName(for: session.sport))
                    .font(.headline)
            }
            .tint(.green)
            // Koppeltraining: gleich nach dem Ende der Einheit davor hier starten; drinnen ist der Ort vorgewählt.
            ForEach(PlanV2Formatting.sessionHints(brick: session.brick, indoor: session.indoor, sport: session.sport, previous: previous, registry: registry), id: \.self) { hint in
                Text(hint)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if !session.focus.isEmpty {
                Text(session.focus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !session.equipmentNeeded.isEmpty {
                Label("Mitnehmen: \(PlanFormatting.equipment(session.equipmentNeeded))", systemImage: "backpack")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                WatchStepRow(step: step)
            }
        } header: {
            Text("\(PlanV2Formatting.sessionTitle(sport: session.sport, amount: session.amount, unit: session.unit)) · \(PlanFormatting.intensity(session.intensity))")
        }
    }

    private var refreshButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(planStore.isRequesting ? "Wird geholt …" : "Vom iPhone holen") {
                planStore.requestPlan()
            }
            .disabled(planStore.isRequesting)
            if let message = planStore.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Ein Schritt im Plan: Name, Umfang, Ziel und Pause, Hilfsmittel, Anleitung.
struct WatchStepRow: View {
    let step: PlanStep

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.name)
                .font(.footnote.weight(.semibold))
            Text(PlanV2Formatting.stepVolume(step))
                .font(.body.monospacedDigit())
            let details = PlanV2Formatting.stepDetails(step)
            if !details.isEmpty {
                Text(details)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !step.equipment.isEmpty {
                Label(PlanFormatting.equipment(step.equipment), systemImage: "backpack")
                    .font(.footnote)
                    .foregroundStyle(.cyan)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !step.instructions.isEmpty {
                // Was genau zu tun ist, in voller Länge: Die Liste scrollt.
                Text(step.instructions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Vor dem Start: Sportart (vorbelegt aus dem Plan), Ort, Bahnlänge im Becken und Ansagen. Der Ort je Sportart bleibt
/// für das nächste Mal gespeichert.
struct WatchStartView: View {
    /// Die geplante Einheit, `nil` bei freiem Training.
    let session: DaySession?

    @EnvironmentObject private var workoutManager: WorkoutManager
    @State private var sport: SportID
    @State private var locationID: String
    @AppStorage("poolLengthMeters") private var poolLengthMeters = PoolLength.defaultMeters
    @AppStorage("announcements") private var announces = true

    private let registry = SportRegistry.standard

    init(sport: SportID, session: DaySession?) {
        self.session = session
        _sport = State(initialValue: sport)
        // Plant der Plan drinnen (Rolle, Laufband), ist "Drinnen" vorgewählt; sonst der zuletzt gewählte Ort.
        let indoor = session?.indoor == true
            ? SportRegistry.standard.module(for: sport)?.recording.locations.first { $0.isIndoor == true }?.id
            : nil
        _locationID = State(initialValue: indoor ?? Self.savedLocation(for: sport))
    }

    private var module: (any SportModule)? { registry.module(for: sport) }

    private var location: RecordingLocation? { module?.recording.location(id: locationID) }

    /// Die Einheit gilt nur für ihre Sportart; mit einer anderen startet ein Training ohne Plan.
    private var plannedSession: DaySession? {
        guard let session, session.sport == sport else { return nil }
        return session
    }

    var body: some View {
        List {
            Section {
                Button(action: start) {
                    Label("Los", systemImage: "play.fill")
                        .font(.headline)
                }
                .tint(.green)
                if let error = workoutManager.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } footer: {
                if let plannedSession {
                    Text(PlanV2Formatting.sessionTitle(sport: plannedSession.sport, amount: plannedSession.amount, unit: plannedSession.unit))
                } else if session != nil {
                    Text("Andere Sportart als geplant: Training ohne Plan.")
                }
            }
            Section {
                Picker("Sportart", selection: $sport) {
                    ForEach(registry.ids, id: \.self) { id in
                        Label(registry.displayName(for: id), systemImage: registry.symbolName(for: id))
                            .tag(id)
                    }
                }
                if let module, module.recording.locations.count > 1 {
                    Picker("Ort", selection: $locationID) {
                        ForEach(module.recording.locations) { location in
                            Label(location.displayName, systemImage: location.symbolName)
                                .tag(location.id)
                        }
                    }
                }
                if location?.usesLapLength == true {
                    NavigationLink {
                        PoolLengthView(meters: $poolLengthMeters)
                    } label: {
                        LabeledContent("Becken", value: "\(poolLengthMeters) m")
                    }
                }
                Toggle("Ansagen", isOn: $announces)
            }
        }
        .navigationTitle(registry.displayName(for: sport))
        .onChange(of: sport) { _, newSport in
            locationID = Self.savedLocation(for: newSport)
        }
    }

    private func start() {
        guard let location else { return }
        UserDefaults.standard.set(location.id, forKey: Self.locationKey(sport))
        workoutManager.beginCountdown(WorkoutStart(
            sport: sport,
            locationID: location.id,
            lapLengthMeters: poolLengthMeters,
            session: plannedSession,
            announces: announces
        ))
    }

    private static func locationKey(_ sport: SportID) -> String {
        "location.\(sport.rawValue)"
    }

    /// Der zuletzt gewählte Ort dieser Sportart, sonst der erste des Moduls.
    private static func savedLocation(for sport: SportID) -> String {
        let locations = SportRegistry.standard.module(for: sport)?.recording.locations ?? []
        let saved = UserDefaults.standard.string(forKey: locationKey(sport))
        return locations.first { $0.id == saved }?.id ?? locations.first?.id ?? ""
    }
}

/// Bahnlänge wählen: 25 m und 50 m direkt, alles andere mit der Digital Crown.
struct PoolLengthView: View {
    @Binding var meters: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(PoolLength.presets, id: \.self) { preset in
                Button {
                    meters = preset
                    dismiss()
                } label: {
                    HStack {
                        Text("\(preset) m")
                        Spacer()
                        if preset == meters {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Stepper(value: $meters, in: PoolLength.range) {
                Text("\(meters) m")
                    .font(.title3.monospacedDigit())
            }
        }
        .navigationTitle("Becken")
    }
}

#Preview {
    WatchTodayView()
        .environmentObject(HealthKitManager())
        .environmentObject(WatchPlanStore())
        .environmentObject(WorkoutManager(authorizer: HealthKitManager()))
}
