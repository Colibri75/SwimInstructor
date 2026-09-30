import Foundation

/// Format, in dem das iPhone den Tagesplan per WatchConnectivity an die Watch schickt.
///
/// Die Watch hat kein eigenes Token und fragt den Server nie selbst: Das iPhone legt den Plan als
/// Application Context ab (der jeweils letzte Stand kommt an, sobald die Watch erreichbar ist), und
/// die Watch kann ihn mit `planRequest` aktiv anfordern. Die Verbindungslogik selbst liegt in den
/// App-Targets, weil es WatchConnectivity auf dem Mac (`swift test`) nicht gibt.
public enum PlanSyncCodec {
    static let planKey = "plan"
    static let versionKey = "version"
    static let requestKey = "request"
    /// Hebt sich das Format einmal inkompatibel, ignoriert eine alte Watch neue Pläne, statt abzustürzen.
    static let formatVersion = 1

    /// Nachricht der Watch an das iPhone: "Schick mir den aktuellen Plan".
    public static var planRequest: [String: Any] { [requestKey: "plan"] }

    public static func isPlanRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "plan"
    }

    /// Plan als Application Context bzw. Antwort auf `planRequest` (nur Property-List-Typen).
    public static func context(for response: PlanResponse) throws -> [String: Any] {
        [
            planKey: try PlanResponse.jsonEncoder().encode(response),
            versionKey: formatVersion
        ]
    }

    /// `nil` bei leerem, fremdem oder kaputtem Inhalt: dann bleibt der bisherige Plan stehen.
    public static func response(from context: [String: Any]) -> PlanResponse? {
        guard context[versionKey] as? Int == formatVersion,
              let data = context[planKey] as? Data else { return nil }
        return try? PlanResponse.jsonDecoder().decode(PlanResponse.self, from: data)
    }
}
