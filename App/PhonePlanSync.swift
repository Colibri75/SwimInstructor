import Combine
import Foundation
import SwimInstructorCore
import WatchConnectivity

/// Schickt den Tagesplan an die Watch, mit allen Einheiten des Tages Die Watch
/// hat kein eigenes Token, das iPhone ist die einzige Stelle, die mit dem Server spricht. In die andere Richtung kommen
/// Testergebnisse der Watch; sie landen im Eingang (`WatchTestResultInbox`), bis der Athlet sie bestätigt.
///
/// Jeder neue Plan landet als Application Context: WatchConnectivity hält davon nur den letzten
/// Stand vor und liefert ihn, sobald die Watch wieder erreichbar ist. Bittet die Watch aktiv um den
/// Plan, antwortet das iPhone sofort mit dem von heute oder sagt, dass er gerade entsteht, und fragt im Hintergrund
/// nach einem neueren; kommt einer, geht er wieder als Application Context raus.
@MainActor
final class PhonePlanSync: NSObject, ObservableObject {
    private let loader: MultiSportTodayLoader
    private let inbox: WatchTestResultInbox
    private let session: WCSession?
    private var subscription: AnyCancellable?

    init(loader: MultiSportTodayLoader, inbox: WatchTestResultInbox) {
        self.loader = loader
        self.inbox = inbox
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func start() {
        guard let session, subscription == nil else { return }
        session.delegate = self
        session.activate()
        // Auch der im Hintergrund vorab geholte Plan von heute geht gleich raus, nicht erst beim Öffnen der App.
        // `@Published` meldet vor dem Setzen, darum erst danach auf der Hauptschlange lesen.
        subscription = loader.$response.combineLatest(loader.$previews)
            .receive(on: DispatchQueue.main)
            .compactMap { [weak self] _ in self?.watchPlan }
            .removeDuplicates()
            .sink { [weak self] response in self?.push(response) }
    }

    /// Was die Watch zeigen soll: der Plan von heute, auch der vorab geholte, solange die App ihn noch nicht übernommen
    /// hat; sonst der letzte.
    private var watchPlan: DayPlanV2Response? {
        loader.dayPlan(on: loader.todayKey) ?? loader.response
    }

    private func push(_ response: DayPlanV2Response) {
        guard let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(PlanSyncCodec.context(for: response))
        } catch {
            // Kein Grund, den Nutzer zu stören: Die Watch zeigt dann den vorherigen Plan und kann
            // ihn über "Vom iPhone holen" erneut anfordern.
            print("PhonePlanSync: Plan nicht übertragen: \(error.localizedDescription)")
        }
    }

    /// Ist der Plan hier nicht von heute (die App war seit Tagen nicht offen oder plant gerade), antwortet das iPhone
    /// "entsteht gerade" statt mit dem alten Plan; der neue kommt danach als Application Context.
    private func answerPlanRequest(_ replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(PlanSyncCodec.reply(for: watchPlan, today: loader.todayKey, canPlan: !loader.needsConfiguration))
        Task { await loader.refreshIfNeeded() }
    }
}

extension PhonePlanSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            if let response = self.watchPlan {
                self.push(response)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Nach einem Wechsel der Watch neu aktivieren, damit die neue Uhr den Plan bekommt.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            if let response = self.watchPlan {
                self.push(response)
            }
        }
    }

    /// Ein Testergebnis der Watch; kommt auch an, wenn die App erst später wieder läuft.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let result = TestResultSyncCodec.result(from: userInfo) else { return }
        Task { @MainActor in self.inbox.receive(result) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard PlanSyncCodec.isPlanRequest(message) else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            self.answerPlanRequest(replyHandler)
        }
    }
}
