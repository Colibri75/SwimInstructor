import SwiftUI
import SwimInstructorCore

/// Eintrag im Gesamtplan: führt zum Plan für den Wettkampftag (nur bei einem Ziel mit Wettkampf oder Versuch).
struct RacePlanLinkSection: View {
    private let goalStore = UserDefaultsTrainingGoalStore()

    var body: some View {
        let goal = goalStore.goal()
        if goal.kind != .fitness {
            Section {
                NavigationLink {
                    RacePlanView()
                } label: {
                    Label(goal.kind == .race ? "Plan für den Wettkampftag" : "Plan für den Zieltag", systemImage: "flag.checkered")
                }
            } footer: {
                Text("Ablauf, Tempo je Disziplin, Wechsel, Verpflegung und Packliste, abgestimmt auf dein Ziel und deine Leistungswerte.")
            }
        }
    }
}

/// Der Plan für den Wettkampftag. Er entsteht auf Knopfdruck (ein Claude-Aufruf) und bleibt auf dem Gerät.
struct RacePlanView: View {
    @EnvironmentObject private var raceLoader: RacePlanLoader
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @EnvironmentObject private var locationProvider: LocationProvider

    @State private var knowsStartTime = false
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var notes = ""

    private let goalStore = UserDefaultsTrainingGoalStore()
    private let planningStore = UserDefaultsPlanningPreferencesStore()
    private let registry = SportRegistry.standard

    private var raceDay: String { PlanFormatting.isoDay(goalStore.goal().targetDate) }

    var body: some View {
        List {
            Group {
                inputSection
                if let response = raceLoader.response {
                    if !raceLoader.matches(raceDay: raceDay) {
                        Section {
                            Label("Dieser Plan gehört zu einem früheren Ziel (\(PlanFormatting.shortGermanDate(response.raceDay))). Erstell ihn neu.", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    overviewSection(response)
                    timelineSection(response)
                    disciplinesSection(response)
                    transitionsSection(response)
                    nutritionSection(response)
                    checklistSection(response)
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Wettkampftag")
        .navigationBarTitleDisplayMode(.inline)
        .swipeClosesKeyboard()
        .onAppear {
            if let response = raceLoader.response {
                notes = response.notes ?? ""
                if let time = response.startTime, let date = Self.date(fromClock: time) {
                    knowsStartTime = true
                    startTime = date
                }
            }
        }
    }

    // MARK: - Eingaben

    private var inputSection: some View {
        Section {
            LabeledContent("Zieltag", value: PlanFormatting.shortGermanDate(raceDay))
            Toggle("Startzeit bekannt", isOn: $knowsStartTime)
            if knowsStartTime {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
            }
            TextField("z. B. Gels nur mit Wasser, Wechselzone weit weg", text: $notes, axis: .vertical)
                .lineLimit(1...4)
                .onChange(of: notes) { _, text in
                    if text.count > RacePlanRequest.maxNotesLength { notes = String(text.prefix(RacePlanRequest.maxNotesLength)) }
                }
            Button {
                Task { await generate() }
            } label: {
                if raceLoader.isLoading {
                    HStack(spacing: 12) {
                        ForgeAnimation()
                        Text("Dein Coach plant den Wettkampftag …")
                    }
                } else {
                    Text(raceLoader.response == nil ? "Plan erstellen" : "Neu erstellen")
                }
            }
            .disabled(raceLoader.isLoading || todayLoader.reading == nil)
            if todayLoader.reading == nil {
                Text("Öffne zuerst den Tab Aktuell, damit die App deinen Zustand aus Health kennt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if raceLoader.needsConfiguration {
                Text("Noch kein Server-Token hinterlegt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = raceLoader.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Das Wetter fließt ein, wenn \"Wetter berücksichtigen\" an ist und der Tag höchstens 14 Tage entfernt ist.")
        }
    }

    private func generate() async {
        guard let snapshot = todayLoader.reading?.snapshot else { return }
        let preferences = planningStore.preferences()
        await raceLoader.generate(
            snapshot: snapshot,
            startTime: knowsStartTime ? Self.clock(startTime) : nil,
            notes: notes,
            location: preferences.usesWeather ? locationProvider.point : nil
        )
    }

    // MARK: - Plan

    private func overviewSection(_ response: RacePlanResponse) -> some View {
        Section("Strategie") {
            Text(response.plan.overview)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Zielzeit", value: PlanV2Formatting.duration(minutes: response.plan.totalMinutes))
            if let weather = response.weather {
                Label(weather.summary, systemImage: "cloud.sun")
                    .font(.footnote)
            }
            AdjustmentsDisclosure(adjustments: response.adjustments)
        }
    }

    @ViewBuilder
    private func timelineSection(_ response: RacePlanResponse) -> some View {
        if !response.plan.timeline.isEmpty {
            Section("Ablauf") {
                ForEach(response.plan.timeline) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(RacePlanLoader.clock(minutesFromStart: entry.minutesFromStart, startTime: response.startTime))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.semibold))
                            if !entry.details.isEmpty {
                                Text(entry.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func disciplinesSection(_ response: RacePlanResponse) -> some View {
        ForEach(response.plan.disciplines) { discipline in
            Section {
                ForEach(Array(discipline.pacing.enumerated()), id: \.offset) { _, pacing in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(pacing.segment).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let target = pacing.targetText {
                                Text(target).font(.subheadline.monospacedDigit())
                            }
                        }
                        if !pacing.instructions.isEmpty {
                            Text(pacing.instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !discipline.notes.isEmpty {
                    Text(discipline.notes)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Label(
                    "\(registry.displayName(for: discipline.sport)) · \(PlanFormatting.distance(discipline.distanceMeters)) · \(PlanV2Formatting.duration(minutes: discipline.targetMinutes))",
                    systemImage: registry.symbolName(for: discipline.sport)
                )
            }
        }
    }

    @ViewBuilder
    private func transitionsSection(_ response: RacePlanResponse) -> some View {
        ForEach(response.plan.transitions) { transition in
            if !transition.checklist.isEmpty {
                Section("Wechsel \(registry.displayName(for: transition.afterSport)) → \(registry.displayName(for: transition.beforeSport))") {
                    ForEach(Array(transition.checklist.enumerated()), id: \.offset) { index, item in
                        Text("\(index + 1). \(item)")
                    }
                }
            }
        }
    }

    private func nutritionSection(_ response: RacePlanResponse) -> some View {
        Section("Verpflegung") {
            ForEach(response.plan.nutrition.before, id: \.self) { item in
                Label(item, systemImage: "fork.knife")
            }
            ForEach(response.plan.nutrition.during) { fuel in
                VStack(alignment: .leading, spacing: 2) {
                    Text(registry.displayName(for: fuel.sport)).font(.subheadline.weight(.semibold))
                    Text(fuel.summary).font(.caption.monospacedDigit())
                    if !fuel.notes.isEmpty {
                        Text(fuel.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(response.plan.nutrition.after, id: \.self) { item in
                Label(item, systemImage: "cup.and.saucer")
            }
        }
    }

    @ViewBuilder
    private func checklistSection(_ response: RacePlanResponse) -> some View {
        if !response.plan.checklist.isEmpty {
            Section("Packliste") {
                ForEach(response.plan.checklist, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - Uhrzeit

    private static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 9, parts.minute ?? 0)
    }

    private static func date(fromClock clock: String) -> Date? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
    }
}
