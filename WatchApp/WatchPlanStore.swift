import Foundation
import SwimInstructorCore
import WatchConnectivity

/// Hält den Tagesplan auf der Watch, mit allen Einheiten des Tages. Er kommt ausschließlich vom iPhone (siehe
/// `PhonePlanSync`) und wird lokal gespeichert, damit er im Schwimmbad oder unterwegs auch ohne iPhone da ist.
///
/// In die andere Richtung schickt die Watch Testergebnisse ans iPhone; dort bestätigt der Athlet sie.
@MainActor
final class WatchPlanStore: NSObject, ObservableObject {
    @Published private(set) var response: DayPlanV2Response?
    @Published private(set) var isRequesting = false
    @Published private(set) var message: String?

    private let cache: DayPlanV2Caching
    private let session: WCSession?

    /// - Parameter legacyCache: Der Plan v1 aus der Zeit vor T5, bis der erste Plan v2 ankommt.
    init(cache: DayPlanV2Caching = FileDayPlanV2Cache.standard(), legacyCache: PlanCaching = FilePlanCache.standard()) {
        self.cache = cache
        self.session = WCSession.isSupported() ? WCSession.default : nil
        self.response = cache.load() ?? legacyCache.load().map(DayPlanV2Response.init(legacy:))
        super.init()
    }

    func start() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// "Vom iPhone holen": Das iPhone antwortet sofort mit seinem Plan; einen neueren schickt es nach, sobald er da ist.
    func requestPlan() {
        guard let session, session.activationState == .activated else {
            message = "Verbindung zum iPhone wird noch aufgebaut."
            return
        }
        guard session.isReachable else {
            message = "iPhone nicht erreichbar. Der Plan kommt, sobald die iPhone-App ihn geladen hat."
            return
        }
        isRequesting = true
        message = nil
        session.sendMessage(PlanSyncCodec.planRequest, replyHandler: { reply in
            let response = PlanSyncCodec.dayPlan(from: reply)
            Task { @MainActor in
                self.isRequesting = false
                if let response {
                    self.apply(response)
                } else {
                    self.message = "Auf dem iPhone ist noch kein Plan. Öffne dort die App."
                }
            }
        }, errorHandler: { error in
            let text = error.localizedDescription
            Task { @MainActor in
                self.isRequesting = false
                self.message = text
            }
        })
    }

    /// Ein Testergebnis ans iPhone. Die Übertragung wartet, bis das iPhone erreichbar ist, auch über einen Neustart der
    /// Watch-App hinweg.
    func send(_ result: WatchTestResult) {
        guard let session, let userInfo = try? TestResultSyncCodec.userInfo(for: result) else { return }
        session.transferUserInfo(userInfo)
    }

    private func apply(_ response: DayPlanV2Response) {
        self.response = response
        message = nil
        try? cache.save(response)
    }
}

extension WatchPlanStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Was das iPhone geschickt hat, während die Watch-App nicht lief.
        guard let response = PlanSyncCodec.dayPlan(from: session.receivedApplicationContext) else { return }
        Task { @MainActor in self.apply(response) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let response = PlanSyncCodec.dayPlan(from: applicationContext) else { return }
        Task { @MainActor in self.apply(response) }
    }
}
