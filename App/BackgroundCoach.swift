import BackgroundTasks
import HealthKit
import UIKit
import UserNotifications
import SwimInstructorCore

/// Der Coach arbeitet, ohne dass die App offen ist: Landet eine Einheit in Health (Health weckt die App) oder gibt iOS der
/// App Zeit im Hintergrund, liest er Health neu, fragt mit einer Mitteilung "Wie war's?" und holt nach erledigtem
/// Training den Plan für morgen. Steht der, kommt er morgens zur eingestellten Uhrzeit als Mitteilung, und Heute zeigt ihn
/// beim Öffnen sofort.
///
/// Grenzen von iOS: Health lässt sich nur bei entsperrtem iPhone lesen, und wann die App im Hintergrund Zeit bekommt,
/// entscheidet das System. Klappt es nicht, plant Heute beim Öffnen wie bisher.
@MainActor
final class BackgroundCoach: ObservableObject {
    static let refreshTaskID = "com.kellner.SwimInstructor.coach"
    /// Was nach einer Einheit nicht länger zurückliegt, bekommt noch eine Frage.
    static let feedbackWindow: TimeInterval = 6 * 3_600

    @Published private(set) var preferences: NotificationPreferences

    private let loader: MultiSportTodayLoader
    private let weekLoader: MultiSportWeekLoader
    private let feedbackBook: SessionFeedbackBook
    private let preferencesStore: NotificationPreferencesStoring
    private let log: NoticeLogging
    private let healthStore = HKHealthStore()
    private let center = UNUserNotificationCenter.current()
    private let weekCalendar = WeekCalendar()
    private var observer: HKObserverQuery?
    private var isRunning = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(
        loader: MultiSportTodayLoader,
        weekLoader: MultiSportWeekLoader,
        feedbackBook: SessionFeedbackBook,
        preferencesStore: NotificationPreferencesStoring = UserDefaultsNotificationPreferencesStore(),
        log: NoticeLogging = UserDefaultsNoticeLog()
    ) {
        self.loader = loader
        self.weekLoader = weekLoader
        self.feedbackBook = feedbackBook
        self.preferencesStore = preferencesStore
        self.log = log
        self.preferences = preferencesStore.preferences()
    }

    // MARK: - Start

    /// Beim Start der App, bevor sie fertig geladen ist: Hintergrundaufgabe anmelden und auf neue Einheiten in Health
    /// hören (Health weckt die App dafür auch im Hintergrund).
    func start() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { [weak self] task in
            Task { @MainActor in self?.handle(task) }
        }
        observeWorkouts()
        scheduleRefresh()
    }

    /// Einmal fragen, ob der Coach Mitteilungen schicken darf.
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Die App geht in den Hintergrund: nächste Hintergrundzeit anmelden und die Morgen-Mitteilung zum Stand bringen.
    func didEnterBackground() {
        scheduleRefresh()
        scheduleMorningNotice()
    }

    func save(_ preferences: NotificationPreferences) {
        self.preferences = preferences
        preferencesStore.save(preferences)
        if preferences.morningPlan || preferences.afterWorkout { requestPermission() }
        scheduleMorningNotice()
    }

    // MARK: - Wecken

    private func observeWorkouts() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            Task { @MainActor in
                await self?.runWithBackgroundTime(name: "Neue Einheit")
                completion()
            }
        }
        healthStore.execute(query)
        observer = query
        healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(3_600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGTask) {
        scheduleRefresh()
        let work = Task { @MainActor in
            await run()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Für das Wecken durch Health: um die halbe Minute bitten, die iOS dafür gibt.
    private func runWithBackgroundTime(name: String) async {
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                Task { @MainActor in self?.endBackgroundTime() }
            }
        }
        await run()
        endBackgroundTime()
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Ein Durchgang

    /// Health lesen, nach neuen Einheiten fragen, nach erledigtem Training den Plan für morgen holen und die
    /// Morgen-Mitteilung stellen. Ist die App offen, macht das Heute selbst.
    func run() async {
        guard !isRunning, UIApplication.shared.applicationState != .active else { return }
        // Bei gesperrtem iPhone gibt Health nichts heraus.
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        isRunning = true
        defer { isRunning = false }

        await loader.readHealth()
        guard let reading = loader.reading else { return }
        let now = Date()
        notifyNewWorkouts(reading.allWorkouts, now: now)

        let today = weekLoader.todayKey
        guard let tomorrow = weekCalendar.addingDays(1, to: today), isDayDone(today, workouts: reading.allWorkouts, now: now) else {
            scheduleMorningNotice()
            return
        }
        if loader.dayPlan(on: tomorrow) == nil, loader.canPreview(tomorrow), !Task.isCancelled {
            await loader.loadPreview(for: tomorrow)
        }
        scheduleMorningNotice()
    }

    /// Erledigt: alles Geplante gemacht, oder heute ist nichts geplant (Ruhetag, keine Zeit).
    private func isDayDone(_ date: String, workouts: [Workout], now: Date) -> Bool {
        guard let day = weekLoader.day(on: date), !day.sessions.isEmpty else { return true }
        let status = MultiSportWeekProgressCalculator().statuses(
            plan: weekLoader.week(starting: weekLoader.currentWeekStart),
            weekStart: weekLoader.currentWeekStart,
            workouts: workouts,
            now: now
        ).first { $0.date == date }
        return status?.isTrainingDone == true
    }

    // MARK: - Mitteilungen

    /// "Wie war's?" für Einheiten der letzten Stunden ohne Rückmeldung, je Einheit einmal.
    private func notifyNewWorkouts(_ workouts: [Workout], now: Date) {
        guard preferences.afterWorkout else { return }
        let fresh = feedbackBook.pending(workouts: workouts, now: now)
            .filter { now.timeIntervalSince($0.endDate) <= Self.feedbackWindow }
        for workout in fresh {
            let notice = CoachNotices.feedback(for: workout)
            guard !log.wasSent(notice.id) else { continue }
            log.markSent(notice.id)
            post(notice, at: nil)
        }
    }

    /// Steht der Plan für morgen fest, kommt er morgen zur eingestellten Uhrzeit; sonst keine Morgen-Mitteilung.
    func scheduleMorningNotice() {
        guard let tomorrow = weekCalendar.addingDays(1, to: weekLoader.todayKey) else { return }
        let id = CoachNotices.morningID(for: tomorrow)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard preferences.morningPlan,
              let plan = loader.dayPlan(on: tomorrow),
              let notice = CoachNotices.morningPlan(plan),
              let date = CoachNotices.morningDate(for: tomorrow, preferences: preferences, now: Date()) else { return }
        post(notice, at: date)
    }

    private func post(_ notice: CoachNotice, at date: Date?) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        let trigger = date.map {
            UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0),
                repeats: false
            )
        }
        center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger)) { _ in }
    }
}
