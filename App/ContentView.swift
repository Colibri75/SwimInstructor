import SwiftUI

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.pool.swim")
                .font(.system(size: 48))
            Text("SwimApp")
                .font(.title)
            statusText
            Button(isRequesting ? "Fragt an…" : "Health-Zugriff anfragen") {
                Task { await requestAccess() }
            }
            .disabled(isRequesting)
            .buttonStyle(.borderedProminent)
        }
        .padding()
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
        try? await healthKitManager.requestAuthorization()
    }
}

#Preview {
    ContentView()
}
