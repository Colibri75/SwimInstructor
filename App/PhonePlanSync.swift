import Combine
import Foundation
import SwimInstructorCore
import WatchConnectivity

/// Schickt den Tagesplan an die Watch. Die Watch hat kein eigenes Token, das iPhone ist die einzige
/// Stelle, die mit dem Server spricht. Bis T5 spielt die Watch nur Schwimmeinheiten ab: Sie bekommt den
/// Tagesplan im Format v1 (`watchPlan()`), an Tagen ohne Schwimmen einen Ruhetag mit Hinweis.
///
/// Jeder neue Plan landet als Application Context: WatchConnectivity hält davon nur den letzten
/// Stand vor und liefert ihn, sobald die Watch wieder erreichbar ist. Bittet die Watch aktiv um den
/// Plan, antwortet das iPhone sofort mit dem, was es hat, und fragt im Hintergrund nach einem
/// neueren; kommt einer, geht er wieder als Application Context raus.
@MainActor
final class PhonePlanSync: NSObject, ObservableObject {
    private let loader: MultiSportTodayLoader
    private let session: WCSession?
    private var subscription: AnyCancellable?

    init(loader: MultiSportTodayLoader) {
        self.loader = loader
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func start() {
        guard let session, subscription == nil else { return }
        session.delegate = self
        session.activate()
        subscription = loader.$response
            .compactMap { $0?.watchPlan() }
            .removeDuplicates()
            .sink { [weak self] response in self?.push(response) }
    }

    private func push(_ response: PlanResponse) {
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

    private func answerPlanRequest(_ replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = loader.response.flatMap { try? PlanSyncCodec.context(for: $0.watchPlan()) } ?? [:]
        replyHandler(reply)
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
            if let response = self.loader.response {
                self.push(response.watchPlan())
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
            if let response = self.loader.response {
                self.push(response.watchPlan())
            }
        }
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
