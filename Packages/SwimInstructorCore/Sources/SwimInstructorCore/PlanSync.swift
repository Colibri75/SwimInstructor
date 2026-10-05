import Foundation

/// Format, in dem das iPhone den Tagesplan per WatchConnectivity an die Watch schickt.
///
/// Die Watch hat kein eigenes Token und fragt den Server nie selbst: Das iPhone legt den Plan als
/// Application Context ab (der jeweils letzte Stand kommt an, sobald die Watch erreichbar ist), und
/// die Watch kann ihn mit `planRequest` aktiv anfordern. Die Verbindungslogik selbst liegt in den
/// App-Targets, weil es WatchConnectivity auf dem Mac (`swift test`) nicht gibt.
public enum PlanSyncCodec {
    /// Der Tagesplan mit allen Einheiten des Tages.
    static let planKey = "plan_v2"
    static let versionKey = "version"
    static let requestKey = "request"
    /// Hebt sich das Format einmal inkompatibel, ignoriert eine alte Watch neue Pläne, statt abzustürzen.
    static let formatVersion = 1

    /// Nachricht der Watch an das iPhone: "Schick mir den aktuellen Plan".
    public static var planRequest: [String: Any] { [requestKey: "plan"] }

    public static func isPlanRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "plan"
    }

    /// Tagesplan als Application Context bzw. Antwort auf `planRequest` (nur Property-List-Typen).
    public static func context(for response: DayPlanV2Response) throws -> [String: Any] {
        [
            planKey: try PlanCoding.jsonEncoder().encode(response),
            versionKey: formatVersion
        ]
    }

    /// Der Tagesplan aus dem Context; `nil` bei leerem, fremdem oder kaputtem Inhalt: dann bleibt der bisherige Plan stehen.
    public static func dayPlan(from context: [String: Any]) -> DayPlanV2Response? {
        guard context[versionKey] as? Int == formatVersion,
              let data = context[planKey] as? Data else { return nil }
        return try? PlanCoding.jsonDecoder().decode(DayPlanV2Response.self, from: data)
    }
}
