import SwiftUI
import SwimInstructorCore

/// Startbildschirm der Watch: Einheit starten und der Tagesplan vom iPhone.
struct WatchTodayView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var planStore: WatchPlanStore
    @EnvironmentObject private var workoutManager: SwimWorkoutManager
    @AppStorage("poolLengthMeters") private var poolLengthMeters = PoolLength.defaultMeters

    var body: some View {
        NavigationStack {
            List {
                startSection
                planSection
                if !healthKitManager.isAuthorized {
                    Section {
                        Button("Health-Zugriff erlauben") {
                            Task { try? await healthKitManager.requestAuthorization() }
                        }
                    } footer: {
                        Text("Nötig, um Bahnen und Züge aufzuzeichnen.")
                    }
                }
            }
            .navigationTitle("Heute")
        }
        // Einmal vorab fragen, damit der Health-Dialog nicht erst am Beckenrand erscheint.
        .task { try? await healthKitManager.requestAuthorization() }
    }

    // MARK: - Start

    private var startSection: some View {
        Section {
            Button {
                workoutManager.beginCountdown(poolLengthMeters: poolLengthMeters, plan: planStore.response?.plan)
            } label: {
                Label("Schwimmen", systemImage: "figure.pool.swim")
                    .font(.headline)
            }
            .tint(.blue)

            NavigationLink {
                PoolLengthView(meters: $poolLengthMeters)
            } label: {
                LabeledContent("Becken", value: "\(poolLengthMeters) m")
            }

            if let error = workoutManager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Plan

    @ViewBuilder
    private var planSection: some View {
        if let response = planStore.response {
            let plan = response.plan
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlanFormatting.sessionType(plan.sessionType))
                        .font(.headline)
                    if !plan.isRestDay {
                        Text("\(PlanFormatting.meters(plan.totalDistanceMeters)) · \(plan.estimatedDurationMinutes) min · \(PlanFormatting.intensity(plan.intensity))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let notice = PlanFormatting.sourceNotice(response) ?? PlanFormatting.dayNotice(response, now: .now) {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if !plan.equipmentNeeded.isEmpty {
                    Label("Mitnehmen: \(PlanFormatting.equipment(plan.equipmentNeeded))", systemImage: "backpack")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(plan.sets.enumerated()), id: \.offset) { _, set in
                    WatchPlanSetRow(set: set)
                }
                ForEach(plan.coachNotes, id: \.self) { note in
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                refreshButton
            } header: {
                Text("Plan")
            }
        } else {
            Section {
                Text("Noch kein Plan. Öffne SwimInstructor auf dem iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                refreshButton
            } header: {
                Text("Plan")
            }
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

struct WatchPlanSetRow: View {
    let set: PlanSet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.name)
                .font(.footnote.weight(.semibold))
            Text(PlanFormatting.setVolume(set))
                .font(.body.monospacedDigit())
            let details = PlanFormatting.setDetails(set)
            if !details.isEmpty {
                Text(details)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !set.equipment.isEmpty {
                Label(PlanFormatting.equipment(set.equipment), systemImage: "backpack")
                    .font(.footnote)
                    .foregroundStyle(.cyan)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !set.instructions.isEmpty {
                // Was genau zu tun ist (locker, Technikübung, ...), in voller Länge: Die Liste scrollt.
                Text(set.instructions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Beckenlänge wählen: 25 m und 50 m direkt, alles andere mit der Digital Crown.
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
        .environmentObject(SwimWorkoutManager())
}
