import SwiftUI
import SwimAppCore

struct WatchTodayView: View {
    @StateObject private var healthKitManager = HealthKitManager()

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.pool.swim")
                .font(.title2)
            Text("SwimApp")
                .font(.headline)
            Text(healthKitManager.isAuthorized ? "Health verbunden ✓" : "Health-Zugriff nötig")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !healthKitManager.isAuthorized {
                Button("Zugriff erlauben") {
                    Task { try? await healthKitManager.requestAuthorization() }
                }
            }
        }
        .padding()
    }
}

#Preview {
    WatchTodayView()
}
