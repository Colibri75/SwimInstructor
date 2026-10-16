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
    static let statusKey = "status"
    /// Hebt sich das Format einmal inkompatibel, ignoriert eine alte Watch neue Pläne, statt abzustürzen.
    static let formatVersion = 1

    /// Nachricht der Watch an das iPhone: "Schick mir den aktuellen Plan".
    public static var planRequest: [String: Any] { [requestKey: "plan"] }

    public static func isPlanRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "plan"
    }

    /// Antwort des iPhones auf `planRequest`, wenn sein Plan nicht von heute ist: Es erstellt ihn gerade und schickt ihn
    /// danach als Application Context. So hält die Watch keinen alten Plan für den neuesten.
    public static var preparingReply: [String: Any] { [versionKey: formatVersion, statusKey: "preparing"] }

    public static func isPreparing(_ reply: [String: Any]) -> Bool {
        reply[versionKey] as? Int == formatVersion && reply[statusKey] as? String == "preparing"
    }

    /// Was das iPhone auf `planRequest` antwortet: den Plan von heute; einen Ersatzplan (mit eigenem Hinweis) oder,
    /// wenn es gar nicht planen kann (kein Token), den letzten Plan; sonst `preparingReply`, weil der Plan von heute
    /// gerade entsteht.
    public static func reply(for response: DayPlanV2Response?, today: String, canPlan: Bool) -> [String: Any] {
        if let response, response.date == today || response.source == .fallback || !canPlan {
            return (try? context(for: response)) ?? [:]
        }
        return canPlan ? preparingReply : [:]
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
