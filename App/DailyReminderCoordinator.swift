import BackgroundTasks
import Combine
import Foundation
import SwimInstructorCore
import UserNotifications

/// Tägliche Erinnerung: eine Benachrichtigung zur eingestellten Uhrzeit und, soweit iOS es zulässt,
/// ein Plan, der vorher im Hintergrund entsteht.
///
/// Zwei Teile mit unterschiedlicher Verlässlichkeit:
/// - **Benachrichtigung:** kommt zur Uhrzeit, auch bei gesperrtem iPhone und beendeter App. Die App
///   legt dafür die nächsten 7 Tage einzeln an. Steht schon ein Plan bereit, nennt der Text ihn.
/// - **Vorbereitung im Hintergrund:** startet frühestens 30 Minuten vor der Uhrzeit. Wann genau (oder
///   ob überhaupt) iOS die App weckt, entscheidet das System. Bei gesperrtem iPhone sind die
///   Health-Daten geschützt, dann klappt das Lesen nicht und der Plan entsteht erst beim Öffnen.
@MainActor
final class DailyReminderCoordinator: ObservableObject {
    static let taskIdentifier = "com.kellner.SwimInstructor.plan-refresh"
    private static let notificationPrefix = "plan-reminder-"

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let settings: ReminderSettings
    private let loader: TodayPlanLoader
    private let center: UNUserNotificationCenter
    private var subscription: AnyCancellable?

    init(settings: ReminderSettings, loader: TodayPlanLoader, center: UNUserNotificationCenter = .current()) {
        self.settings = settings
        self.loader = loader
        self.center = center
    }

    /// Muss beim Start der App laufen, bevor sie fertig gestartet ist: iOS lehnt das Registrieren der
    /// Hintergrundaufgabe sonst ab.
    func start() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in self?.handle(refreshTask) }
        }
        // Kommt ein neuer Plan (beim Öffnen oder im Hintergrund), nennt ihn die nächste Benachrichtigung.
        subscription = loader.$response
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.scheduleNotifications() }
            }
    }

    /// Nach jeder Änderung der Einstellung und beim Öffnen der App.
    func apply() async {
        await refreshAuthorization()
        if settings.schedule.isEnabled && authorization == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
        await scheduleNotifications()
        scheduleBackgroundRefresh()
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    private var canNotify: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    // MARK: - Benachrichtigungen

    /// Ersetzt alle angelegten Erinnerungen durch die der nächsten 7 Tage.
    func scheduleNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.notificationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard settings.schedule.isEnabled else { return }
        await refreshAuthorization()
        guard canNotify else { return }

        let calendar = Calendar.current
        for fire in settings.schedule.upcomingFireDates(from: Date(), calendar: calendar) {
            let content = ReminderContentBuilder.content(for: loader.response, on: fire, calendar: calendar)
            let notification = UNMutableNotificationContent()
            notification.title = content.title
            notification.body = content.body
            notification.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = Self.notificationPrefix + PlanFormatting.isoDay(fire, calendar: calendar)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: notification, trigger: trigger))
        }
    }

    // MARK: - Hintergrund

    /// Plant den nächsten Lauf (höchstens eine Anfrage gleichzeitig). iOS kann ihn später oder gar
    /// nicht starten, darum hängt die Benachrichtigung nicht daran.
    func scheduleBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        guard let start = settings.schedule.nextPreparationDate(from: Date()) else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = start
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Im Simulator und bei abgeschalteter Hintergrundaktualisierung nicht möglich. Dann bleibt
            // es bei der Benachrichtigung mit dem Hinweis, die App zu öffnen.
            print("DailyReminderCoordinator: Hintergrundlauf nicht eingeplant: \(error.localizedDescription)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        // Zuerst den nächsten Lauf einplanen, sonst endet die Kette bei einem Abbruch.
        scheduleBackgroundRefresh()

        let finisher = TaskFinisher(task)
        let work = Task { @MainActor [weak self] in
            guard let self else {
                finisher.finish(success: false)
                return
            }
            let result = await self.loader.prepareInBackground()
            await self.scheduleNotifications()
            if case .ready = result {
                finisher.finish(success: true)
            } else {
                finisher.finish(success: false)
            }
        }
        task.expirationHandler = {
            work.cancel()
            finisher.finish(success: false)
        }
    }
}

/// `setTaskCompleted` darf nur einmal aufgerufen werden, der Ablauf-Handler kommt aber von einem
/// anderen Thread als die Arbeit.
private final class TaskFinisher: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var finished = false

    init(_ task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        task.setTaskCompleted(success: success)
    }
}
