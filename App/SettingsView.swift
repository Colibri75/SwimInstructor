import SwiftUI
import SwimInstructorCore

/// Server-Adresse und Token. Das Token steht nie im Code, es wird hier einmal eingegeben und
/// landet im Schlüsselbund.
struct SettingsView: View {
    @EnvironmentObject private var settings: BackendSettings
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var locationProvider: LocationProvider
    @EnvironmentObject private var calendarProvider: CalendarAvailabilityProvider
    @EnvironmentObject private var coach: BackgroundCoach
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
    @State private var trainingGoal = TrainingGoal.default
    private let trainingGoalStore = UserDefaultsTrainingGoalStore()
    @State private var startingLevels: [StartingLevel] = []
    private let startingLevelStore = UserDefaultsStartingLevelStore()
    @State private var scheduleSummary = ""
    private let scheduleStore = UserDefaultsWeeklyScheduleStore()
    @State private var pauseReport: PauseReport?
    private let pauseStore = UserDefaultsPauseReportStore()
    @State private var planning = PlanningPreferences.standard
    private let planningStore = UserDefaultsPlanningPreferencesStore()
    @State private var indoorOwned: Set<String> = []
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    private let indoorStore = UserDefaultsIndoorEquipmentStore()

    init(onSave: @escaping () -> Void = {}) {
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
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
                        Text("Dein persönlicher Token vom Server (beim Besitzer der Wert von API_TOKEN, sonst von ihm angelegt). Er wird nur im Schlüsselbund dieses iPhones gespeichert.")
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
                        // Auch beim Zurückkommen aus dem Ziel-Assistenten neu lesen.
                        .onAppear { trainingGoal = trainingGoalStore.goal() }

                    scheduleSection
                        .onAppear { scheduleSummary = scheduleStore.schedule(for: trainingGoalStore.goal()).summary }

                    startingLevelSection
                        .onAppear { startingLevels = startingLevelStore.levels() }

                    pauseSection
                        .onAppear { pauseReport = pauseStore.report() }

                    Section {
                        NavigationLink {
                            ProfileView()
                        } label: {
                            Label("Leistungswerte und Tests", systemImage: "gauge.with.dots.needle.67percent")
                        }
                    } header: {
                        Text("Leistungsprofil")
                    } footer: {
                        Text("Danach richten sich Zonen und Tempo im Plan. Hier trägst du Werte von Hand oder nach einem Test ein und stellst ein, ob und wie oft die App Tests einplant.")
                    }

                    planningSection

                    notificationSection

                    appearanceSection

                    Section {
                        ForEach(EquipmentItem.allCases) { item in
                            Toggle(item.title, isOn: equipmentBinding(for: item))
                        }
                        ForEach(SportRegistry.standard.indoorEquipment, id: \.id) { item in
                            Toggle(item.displayName, isOn: indoorBinding(for: item.id))
                        }
                        ForEach(SportRegistry.standard.openWaterVenues, id: \.id) { venue in
                            Toggle("Zugang zu \(venue.displayName) (See, Meer)", isOn: indoorBinding(for: venue.id))
                        }
                    } header: {
                        Text("Mein Equipment")
                    } footer: {
                        Text("Der Plan nutzt nur, was hier an ist. Mit Rolle oder Laufband plant er bei Unwetter drinnen. Mit Zugang zu Freiwasser plant er dort, wenn es warm genug ist, vor allem vor einem Ziel im Freiwasser. Die Auswahl gilt ab dem nächsten Plan (zum Aktualisieren auf Heute nach unten ziehen). Ohne Auswahl plant dein Coach ganz ohne Hilfsmittel.")
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
                .cardRows()
            }
            .themedList()
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
                indoorOwned = Set(indoorStore.ownedIndoorEquipment())
                planning = planningStore.preferences()
            }
        }
    }

    // MARK: - Planung

    private var planningSection: some View {
        Section {
            Stepper(value: planningBinding(\.supplements.strengthPerWeek), in: Supplements.strengthRange) {
                LabeledContent("Kraft", value: planning.supplements.strengthPerWeek == 0 ? "aus" : "\(planning.supplements.strengthPerWeek)× pro Woche")
            }
            Stepper(value: planningBinding(\.supplements.mobilityPerWeek), in: Supplements.mobilityRange) {
                LabeledContent("Mobilität", value: planning.supplements.mobilityPerWeek == 0 ? "aus" : "\(planning.supplements.mobilityPerWeek)× pro Woche")
            }
            Toggle("Wetter berücksichtigen", isOn: Binding(
                get: { planning.usesWeather },
                set: { isOn in
                    updatePlanning { $0.usesWeather = isOn }
                    if isOn { locationProvider.refresh() } else { locationProvider.forget() }
                }
            ))
            if planning.usesWeather, locationProvider.isDenied {
                Text("Ohne Ortsfreigabe gibt es kein Wetter. Erlaube sie in den Einstellungen des iPhones unter Datenschutz > Ortungsdienste.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Toggle("Kalender berücksichtigen", isOn: Binding(
                get: { planning.usesCalendar },
                set: { isOn in
                    updatePlanning { $0.usesCalendar = isOn }
                    if isOn { Task { await calendarProvider.requestAccess() } }
                }
            ))
            if planning.usesCalendar {
                if calendarProvider.isDenied {
                    Text("Ohne Kalenderzugriff zählt die freie Zeit nicht. Erlaube ihn in den Einstellungen des iPhones unter Datenschutz > Kalender.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Stepper(value: planningBinding(\.calendarStartHour), in: 0...(planning.calendarEndHour - 1)) {
                    LabeledContent("Training ab", value: "\(planning.calendarStartHour) Uhr")
                }
                Stepper(value: planningBinding(\.calendarEndHour), in: (planning.calendarStartHour + 1)...24) {
                    LabeledContent("Training bis", value: "\(planning.calendarEndHour) Uhr")
                }
            }
        } header: {
            Text("Planung")
        } footer: {
            Text("Kraft und Mobilität kommen als kurze Blöcke in die Woche, mit Übungen am Tag. Mit Wetter weicht der Plan bei Gewitter, Sturm oder Glätte nach drinnen aus (dein Ort geht auf etwa 10 km gerundet zum Server). Mit Kalender plant er an vollen Tagen weniger: Es zählt der längste freie Block im Trainingsfenster, Termine selbst bleiben auf dem iPhone.")
        }
    }

    // MARK: - Erscheinungsbild

    private var appearanceSection: some View {
        Section {
            Picker("Farbschema", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Erscheinungsbild")
        } footer: {
            Text("Hell ist der blaugraue Morgennebel, dunkel die Nacht aus dem Logo. Wie iPhone folgt der Einstellung des iPhones.")
        }
    }

    // MARK: - Mitteilungen

    private var notificationSection: some View {
        Section {
            Toggle("Plan am Morgen", isOn: notificationBinding(\.morningPlan))
            if coach.preferences.morningPlan {
                DatePicker("Uhrzeit", selection: morningTimeBinding, displayedComponents: .hourAndMinute)
            }
            Toggle("Nach dem Training fragen", isOn: notificationBinding(\.afterWorkout))
        } header: {
            Text("Mitteilungen")
        } footer: {
            Text("Ist dein Training erledigt, holt dein Coach im Hintergrund schon den Plan für morgen. Er kommt dann morgens zur gewählten Uhrzeit, und Aktuell zeigt ihn sofort. Nach einer Einheit fragt er, wie es war. Wann die App im Hintergrund arbeiten darf, entscheidet iOS; klappt es nicht, plant Aktuell beim Öffnen wie gewohnt.")
        }
    }

    private func notificationBinding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { coach.preferences[keyPath: keyPath] },
            set: { value in
                var copy = coach.preferences
                copy[keyPath: keyPath] = value
                coach.save(copy)
            }
        )
    }

    private var morningTimeBinding: Binding<Date> {
        Binding(
            get: {
                let preferences = coach.preferences
                return Calendar.current.date(bySettingHour: preferences.morningHour, minute: preferences.morningMinute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var copy = coach.preferences
                copy.morningHour = parts.hour ?? copy.morningHour
                copy.morningMinute = parts.minute ?? copy.morningMinute
                coach.save(copy)
            }
        )
    }

    private func planningBinding(_ keyPath: WritableKeyPath<PlanningPreferences, Int>) -> Binding<Int> {
        Binding(
            get: { planning[keyPath: keyPath] },
            set: { value in updatePlanning { $0[keyPath: keyPath] = value } }
        )
    }

    /// Ändert die Einstellungen der Planung und speichert sofort (über den Initialisierer, der die Bereiche einhält).
    private func updatePlanning(_ change: (inout PlanningPreferences) -> Void) {
        var copy = planning
        change(&copy)
        let checked = PlanningPreferences(
            supplements: Supplements(strengthPerWeek: copy.supplements.strengthPerWeek, mobilityPerWeek: copy.supplements.mobilityPerWeek),
            usesWeather: copy.usesWeather,
            usesCalendar: copy.usesCalendar,
            calendarStartHour: copy.calendarStartHour,
            calendarEndHour: copy.calendarEndHour
        )
        planning = checked
        planningStore.save(checked)
    }

    private func indoorBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { indoorOwned.contains(id) },
            set: { isOn in
                if isOn { indoorOwned.insert(id) } else { indoorOwned.remove(id) }
                indoorStore.setOwnedIndoorEquipment(indoorOwned)
            }
        )
    }

    // MARK: - Gesamtziel

    private var goalSection: some View {
        Section {
            NavigationLink {
                GoalAssistantView(store: trainingGoalStore)
            } label: {
                LabeledContent("Ziel", value: PlanFormatting.goalSummary(trainingGoal))
            }
            if let pending = trainingGoalStore.pendingGoal() {
                LabeledContent("Vorgemerkt", value: PlanFormatting.goalSummary(pending))
            }
        } header: {
            Text("Mein Ziel")
        } footer: {
            Text("Der Plan arbeitet auf dieses Ziel hin. Änderungen sind ein Entwurf, bis du sie übernimmst; ein neues Ziel geht höchstens alle 7 Tage.")
        }
    }

    // MARK: - Wochenraster

    private var scheduleSection: some View {
        Section {
            NavigationLink {
                WeeklyScheduleView(store: scheduleStore, goalStore: trainingGoalStore)
            } label: {
                LabeledContent("Wochenraster", value: scheduleSummary)
            }
        } footer: {
            Text("An welchen Tagen du trainierst, wann und wie lange höchstens. Gilt ab der nächsten Abstimmung der 14 Tage.")
        }
    }

    // MARK: - Startniveau

    private var startingLevelSection: some View {
        Section {
            NavigationLink {
                StartingLevelView(store: startingLevelStore)
            } label: {
                LabeledContent("Startniveau", value: StartingLevelFormatting.summary(startingLevels, now: Date()))
            }
        } footer: {
            Text("Wenn Health weniger zeigt, als du schaffst (Training ohne Uhr, Pause), gib hier deinen Wochenumfang und deine längste Einheit an. Die Angabe gilt 28 Tage.")
        }
    }

    // MARK: - Pause

    private var pauseSection: some View {
        Section {
            NavigationLink {
                PauseReportView(store: pauseStore)
            } label: {
                LabeledContent("Pause melden", value: pauseReport.map { $0.kind.title } ?? "")
            }
        } footer: {
            Text("Krank, verletzt oder im Urlaub? Ab 7 Tagen Pause schreibt die App den Gesamtplan gleich fort und steigt danach behutsam wieder ein.")
        }
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
