import Foundation
import SwimInstructorCore
import WatchConnectivity
import WidgetKit

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

    init(cache: DayPlanV2Caching = FileDayPlanV2Cache.standard()) {
        self.cache = cache
        self.session = WCSession.isSupported() ? WCSession.default : nil
        self.response = cache.load()
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
            message = String(localized: "Verbindung zum iPhone wird noch aufgebaut.")
            return
        }
        guard session.isReachable else {
            message = String(localized: "iPhone nicht erreichbar. Der Plan kommt, sobald die iPhone-App ihn geladen hat.")
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
                } else if PlanSyncCodec.isPreparing(reply) {
                    self.message = String(localized: "Dein Coach erstellt gerade den Plan für heute auf dem iPhone. Er kommt von selbst auf die Uhr.")
                } else {
                    self.message = String(localized: "Auf dem iPhone ist noch kein Plan. Öffne dort die App.")
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

    /// Ist der Plan auf der Uhr nicht von heute, gleich beim iPhone nachfragen, ohne dass jemand "Vom iPhone holen"
    /// drückt: beim Öffnen und sobald das iPhone erreichbar wird. Ist es nicht erreichbar, bleibt es still.
    func requestPlanIfOutdated(now: Date = .now) {
        guard !isRequesting, let session, session.activationState == .activated, session.isReachable else { return }
        if let response, response.date == PlanFormatting.isoDay(now) { return }
        requestPlan()
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
        updateComplication()
    }

    /// Die Komplikation zeigt den Plan vom iPhone (nur Tagespläne, keine Vorschau).
    func updateComplication() {
        guard let response else { return }
        let glance = PlanGlance.make(date: response.date, todayDone: false, plan: response.plan, now: Date())
        if PlanGlanceStore.shared().save(glance) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension WatchPlanStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Was das iPhone geschickt hat, während die Watch-App nicht lief.
        let response = PlanSyncCodec.dayPlan(from: session.receivedApplicationContext)
        Task { @MainActor in
            if let response { self.apply(response) }
            self.requestPlanIfOutdated()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestPlanIfOutdated() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let response = PlanSyncCodec.dayPlan(from: applicationContext) else { return }
        Task { @MainActor in self.apply(response) }
    }
}
