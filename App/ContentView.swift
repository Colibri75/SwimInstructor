import SwiftUI
import SwimAppCore

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var isRequesting = false
    @State private var workouts: [SwimWorkout] = []
    @State private var loadError: String?

    private let workoutRepository: SwimWorkoutRepository = HealthKitSwimWorkoutRepository()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "figure.pool.swim")
                            .font(.system(size: 48))
                        statusText
                        Button(isRequesting ? "Fragt an…" : "Health-Zugriff anfragen") {
                            Task { await requestAccess() }
                        }
                        .disabled(isRequesting)
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                }

                Section("Meine letzten Schwimmeinheiten") {
                    if let loadError {
                        Text("Fehler: \(loadError)").foregroundStyle(.red)
                    } else if workouts.isEmpty {
                        Text("Noch keine Schwimm-Workouts gefunden")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workouts) { workout in
                            SwimWorkoutRow(workout: workout)
                        }
                    }
                }
            }
            .navigationTitle("SwimApp")
        }
    }

    private var statusText: some View {
        Group {
            if let error = healthKitManager.lastError {
                Text("Fehler: \(error)").foregroundStyle(.red)
            } else if healthKitManager.isAuthorized {
                Text("Health-Zugriff angefragt ✓").foregroundStyle(.green)
            } else {
                Text("Noch kein Health-Zugriff angefragt")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private func requestAccess() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await healthKitManager.requestAuthorization()
            workouts = try await workoutRepository.fetchRecentSwimWorkouts(limit: 20)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct SwimWorkoutRow: View {
    let workout: SwimWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.startDate, style: .date)
                .font(.subheadline)
            HStack(spacing: 12) {
                if let distance = workout.totalDistanceMeters {
                    Text("\(Int(distance)) m")
                }
                Text(Duration.seconds(workout.duration).formatted(.units(allowed: [.minutes, .seconds])))
                if let pace = workout.averagePaceSecondsPer100m {
                    Text("\(Int(pace)) s/100m")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
