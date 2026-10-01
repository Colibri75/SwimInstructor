import SwiftUI
import SwimInstructorCore

/// Server-Adresse und Token. Das Token steht nie im Code, es wird hier einmal eingegeben und
/// landet im Schlüsselbund.
struct SettingsView: View {
    @EnvironmentObject private var settings: BackendSettings
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    /// Wird nach dem Speichern aufgerufen, damit der Heute-Bildschirm gleich einen Plan holt.
    private let onSave: () -> Void

    @State private var urlText = ""
    @State private var tokenText = ""
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isChecking = false
    @State private var ownedEquipment: Set<EquipmentItem> = []
    private let equipmentStore = UserDefaultsOwnedEquipmentStore()
    @State private var goalMeters = Int(AthleteGoal.default.distanceMeters)
    @State private var goalMinutes = Int(AthleteGoal.default.targetDurationSeconds / 60)
    @State private var goalDay = AthleteGoal.default.targetDate
    private let goalStore = UserDefaultsGoalStore()

    init(onSave: @escaping () -> Void = {}) {
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(settings.hasToken ? "Token gespeichert (leer lassen = behalten)" : "API-Token", text: $tokenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                } footer: {
                    Text("Das Token ist der Wert von API_TOKEN auf dem Server. Es wird nur im Schlüsselbund dieses iPhones gespeichert.")
                }

                Section {
                    Button(isChecking ? "Prüft …" : "Verbindung testen") {
                        Task { await checkConnection() }
                    }
                    .disabled(isChecking)
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(messageIsError ? .red : .green)
                    }
                }

                goalSection

                Section {
                    ForEach(EquipmentItem.allCases) { item in
                        Toggle(item.title, isOn: equipmentBinding(for: item))
                    }
                } header: {
                    Text("Mein Equipment")
                } footer: {
                    Text("Der Plan nutzt nur, was hier an ist. Die Auswahl gilt ab dem nächsten Plan (zum Aktualisieren auf Heute nach unten ziehen). Ohne Auswahl plant Claude ganz ohne Hilfsmittel.")
                }

                Section("Apple Health") {
                    Button("Health-Zugriff erneut anfragen") {
                        Task { try? await healthKitManager.requestAuthorization() }
                    }
                    if let error = healthKitManager.lastError {
                        Text("Fehler: \(error)").font(.footnote).foregroundStyle(.red)
                    }
                }

                if settings.hasToken {
                    Section {
                        Button("Token entfernen", role: .destructive) {
                            try? settings.removeToken()
                        }
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                }
            }
            .onAppear {
                urlText = settings.baseURL.absoluteString
                ownedEquipment = Set(equipmentStore.ownedEquipment().compactMap(EquipmentItem.init(rawValue:)))
                let goal = goalStore.goal()
                goalMeters = Int(goal.distanceMeters)
                goalMinutes = Int((goal.targetDurationSeconds / 60).rounded())
                goalDay = goal.targetDate
            }
        }
    }

    // MARK: - Gesamtziel

    /// Das Ziel, wie es gerade eingestellt ist (noch nicht unbedingt gültig).
    private var editedGoal: AthleteGoal {
        AthleteGoal(
            distanceMeters: Double(goalMeters),
            targetDurationSeconds: Double(goalMinutes * 60),
            targetDate: AthleteGoal.targetDate(onDayOf: goalDay)
        )
    }

    private var goalSection: some View {
        Section {
            Stepper(value: $goalMeters, in: 100...10_000, step: 100) {
                LabeledContent("Distanz", value: PlanFormatting.meters(goalMeters))
            }
            .onChange(of: goalMeters) { _, _ in saveGoal() }
            Stepper(value: $goalMinutes, in: AthleteGoal.durationMinutesRange) {
                LabeledContent("Zielzeit", value: "\(goalMinutes) min")
            }
            .onChange(of: goalMinutes) { _, _ in saveGoal() }
            DatePicker("Zieltag", selection: $goalDay, in: Date()..., displayedComponents: .date)
                .onChange(of: goalDay) { _, _ in saveGoal() }
            if let problem = editedGoal.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                LabeledContent("Zielpace", value: "\(PlanFormatting.pace(editedGoal.targetPaceSecondsPerHundredMeters)) /100 m")
                    .font(.footnote)
            }
            Button("Auf 3,8 km in 60 min bis 04.07.2027 zurücksetzen") {
                goalStore.resetGoal()
                let goal = goalStore.goal()
                goalMeters = Int(goal.distanceMeters)
                goalMinutes = Int(goal.targetDurationSeconds / 60)
                goalDay = goal.targetDate
            }
            .font(.footnote)
        } header: {
            Text("Mein Ziel")
        } footer: {
            Text("Der Plan arbeitet auf dieses Ziel hin: Distanz, Zielzeit und Zieltag gehen in jede Plananfrage ein. Es bleibt gespeichert, bis du es änderst. Nach einer Änderung auf Heute nach unten ziehen und im Tab Woche neu planen.")
        }
    }

    /// Merkt das Ziel sofort, wenn es gültig ist (unabhängig von "Sichern").
    private func saveGoal() {
        goalStore.setGoal(editedGoal)
    }

    /// Schaltet ein Hilfsmittel an oder aus und merkt es sofort (unabhängig von "Sichern").
    private func equipmentBinding(for item: EquipmentItem) -> Binding<Bool> {
        Binding(
            get: { ownedEquipment.contains(item) },
            set: { isOn in
                if isOn {
                    ownedEquipment.insert(item)
                } else {
                    ownedEquipment.remove(item)
                }
                equipmentStore.setOwnedEquipment(ownedEquipment)
            }
        )
    }

    private func save() {
        do {
            try settings.save(baseURLString: urlText, token: tokenText)
            dismiss()
            onSave()
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    /// Prüft mit den eingegebenen Werten, ohne sie zu speichern; kostet keinen Claude-Aufruf.
    private func checkConnection() async {
        guard let url = BackendSettings.validatedURL(urlText) else {
            show(BackendSettingsError.invalidURL.localizedDescription, isError: true)
            return
        }
        // Leeres Feld: mit dem gespeicherten Token prüfen.
        let typed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = typed.isEmpty ? settings.configuration?.token : typed else {
            show(BackendSettingsError.missingToken.localizedDescription, isError: true)
            return
        }
        let configuration = BackendConfiguration(baseURL: url, token: token)

        isChecking = true
        defer { isChecking = false }
        do {
            try await PlanAPIClient(configuration: configuration).checkConnection()
            show("Verbindung ok, Token gültig.", isError: false)
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func show(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
    }
}
