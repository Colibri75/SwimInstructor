import SwiftUI
import SwimInstructorCore

/// Server-Adresse und Token. Das Token steht nie im Code, es wird hier einmal eingegeben und
/// landet im Schlüsselbund.
struct SettingsView: View {
    @EnvironmentObject private var settings: BackendSettings
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var reminderSettings: ReminderSettings
    @EnvironmentObject private var reminder: DailyReminderCoordinator
    @Environment(\.dismiss) private var dismiss

    /// Wird nach dem Speichern aufgerufen, damit der Heute-Bildschirm gleich einen Plan holt.
    private let onSave: () -> Void

    @State private var urlText = ""
    @State private var tokenText = ""
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isChecking = false

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

                reminderSection

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
            .onAppear { urlText = settings.baseURL.absoluteString }
        }
    }

    // MARK: - Erinnerung

    @ViewBuilder
    private var reminderSection: some View {
        Section {
            Toggle("Plan morgens vorbereiten", isOn: reminderEnabledBinding)
            if reminderSettings.schedule.isEnabled {
                DatePicker("Uhrzeit", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
            }
            if reminderSettings.schedule.isEnabled && reminder.authorization == .denied {
                Text("Benachrichtigungen sind für die App ausgeschaltet. Erlaube sie in den iOS-Einstellungen, sonst kommt keine Erinnerung.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("iOS-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Tägliche Erinnerung")
        } footer: {
            Text("Zur eingestellten Uhrzeit kommt eine Benachrichtigung, auch bei gesperrtem iPhone. Das iPhone bereitet den Plan ab etwa 30 Minuten vorher im Hintergrund vor. Ob und wann iOS das erlaubt, entscheidet das System. Bei gesperrtem iPhone kann die App Health nicht lesen: Dann nennt die Benachrichtigung den Plan noch nicht, und er entsteht beim Öffnen der App.")
        }
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { reminderSettings.schedule.isEnabled },
            set: { isOn in
                reminderSettings.schedule.isEnabled = isOn
                Task { await reminder.apply() }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderSettings.schedule.hour,
                    minute: reminderSettings.schedule.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderSettings.schedule.hour = parts.hour ?? reminderSettings.schedule.hour
                reminderSettings.schedule.minute = parts.minute ?? reminderSettings.schedule.minute
                Task { await reminder.apply() }
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
