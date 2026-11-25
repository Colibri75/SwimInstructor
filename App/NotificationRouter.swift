import SwiftUI
import UserNotifications
import SwimInstructorCore

/// Was beim Antippen einer Mitteilung passiert: Die App merkt sich die Route der Mitteilung (`NotificationRoute`), und
/// `RootView` und `TodayView` öffnen das Passende ("Wie war's?" zur Einheit, die ganze Nachricht deines Coachs, Aktuell).
/// Bei offener App erscheinen Mitteilungen trotzdem oben als Banner.
///
/// Muss vor dem Ende des Starts Delegate der Mitteilungszentrale sein, sonst geht ein Tipp verloren, der die App erst
/// startet (`SwimInstructorApp.init`).
@MainActor
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Die Route der zuletzt angetippten Mitteilung, bis eine Ansicht sie erledigt (`finish`).
    @Published private(set) var pending: NotificationRoute?

    private override init() {
        super.init()
    }

    func finish() {
        pending = nil
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let request = response.notification.request
        guard let route = NotificationRoute(identifier: request.identifier, userInfo: request.content.userInfo) else { return }
        await MainActor.run { self.pending = route }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
