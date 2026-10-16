import BackgroundTasks
import HealthKit
import UIKit
import UserNotifications
import WidgetKit
import SwimInstructorCore

/// Der Coach arbeitet, ohne dass die App offen ist: Landet eine Einheit oder die Nacht in Health (Health weckt die App) oder
/// gibt iOS der App Zeit im Hintergrund, liest er Health neu, fragt mit einer Mitteilung "Wie war's?" und holt nach
/// erledigtem Training den Plan für morgen. Fehlt morgens der Plan für heute, holt er ihn mit der letzten Nacht. Steht der
/// Plan, kommt er morgens zur eingestellten Uhrzeit als Mitteilung, und Heute zeigt ihn beim Öffnen sofort.
///
/// Grenzen von iOS: Health lässt sich nur bei entsperrtem iPhone lesen, und wann die App im Hintergrund Zeit bekommt,
/// entscheidet das System. Der Plan für heute braucht länger als diese Zeit; die Anfrage läuft darum als Übertragung im
/// Hintergrund weiter (`BackgroundDayPlanFetcher`). Klappt es nicht, plant Heute beim Öffnen wie bisher.
@MainActor
final class BackgroundCoach: ObservableObject {
    static let refreshTaskID = "com.kellner.SwimInstructor.coach"
    /// Was nach einer Einheit nicht länger zurückliegt, bekommt noch eine Frage.
    static let feedbackWindow: TimeInterval = 6 * 3_600
    /// Ab dieser Stunde holt der Coach den Plan für heute vorab; davor fehlt noch die Nacht.
    static let todayAheadFromHour = 4
    /// So oft je Tag höchstens (ein Versuch kann an der Verbindung scheitern).
    static let todayAheadAttempts = 2
    private static let todayAheadKey = "coach.todayAhead"

    @Published private(set) var preferences: NotificationPreferences

    private let loader: MultiSportTodayLoader
    private let weekLoader: MultiSportWeekLoader
    private let feedbackBook: SessionFeedbackBook
    private let preferencesStore: NotificationPreferencesStoring
    private let log: NoticeLogging
    private let planClient: @MainActor () -> PlanAPIClient?
    private let fetcher = BackgroundDayPlanFetcher.shared
    private let defaults = UserDefaults.standard
    private let healthStore = HKHealthStore()
    private let center = UNUserNotificationCenter.current()
    private let weekCalendar = WeekCalendar()
    private var observers: [HKObserverQuery] = []
    private var isRunning = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(
        loader: MultiSportTodayLoader,
        weekLoader: MultiSportWeekLoader,
        feedbackBook: SessionFeedbackBook,
        planClient: @escaping @MainActor () -> PlanAPIClient?,
        preferencesStore: NotificationPreferencesStoring = UserDefaultsNotificationPreferencesStore(),
        log: NoticeLogging = UserDefaultsNoticeLog()
    ) {
        self.planClient = planClient
        self.loader = loader
        self.weekLoader = weekLoader
        self.feedbackBook = feedbackBook
        self.preferencesStore = preferencesStore
        self.log = log
        self.preferences = preferencesStore.preferences()
    }

    // MARK: - Start

    /// Beim Start der App, bevor sie fertig geladen ist: Hintergrundaufgabe anmelden, auf neue Einheiten und die Nacht in
    /// Health hören (Health weckt die App dafür auch im Hintergrund) und Antworten auf den Plan für heute annehmen, auch
    /// wenn iOS die App nur dafür startet.
    func start() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { [weak self] task in
            Task { @MainActor in self?.handle(task) }
        }
        fetcher.onDelivery = { [weak self] plan, target in self?.receiveTodayAhead(plan, target: target) }
        observeHealth()
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
        updateGlance()
    }

    func save(_ preferences: NotificationPreferences) {
        self.preferences = preferences
        preferencesStore.save(preferences)
        if preferences.morningPlan || preferences.afterWorkout { requestPermission() }
        scheduleMorningNotice()
    }

    // MARK: - Wecken

    /// Neue Einheiten und der Schlaf der Nacht: Kommt der morgens von der Watch, ist das iPhone meist entsperrt, und der
    /// Plan für heute kann mit der Nacht entstehen.
    private func observeHealth() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        observe(HKObjectType.workoutType(), name: "Neue Einheit")
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            observe(sleep, name: "Neue Nacht")
        }
    }

    private func observe(_ type: HKSampleType, name: String) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            Task { @MainActor in
                await self?.runWithBackgroundTime(name: name)
                completion()
            }
        }
        healthStore.execute(query)
        observers.append(query)
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

    /// Health lesen, nach neuen Einheiten fragen, morgens den Plan für heute anstoßen, nach erledigtem Training den Plan
    /// für morgen holen und die Morgen-Mitteilung stellen. Ist die App offen, macht das Heute selbst.
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
        defer {
            scheduleMorningNotice()
            updateGlance()
        }
        await requestTodayAhead(now: now, workouts: reading.allWorkouts)
        // Erledigt oder heute nichts geplant (Ruhetag, keine Zeit): den Plan für morgen holen.
        let nothingToday = weekLoader.day(on: today).map { $0.sessions.isEmpty || $0.isUnavailable } ?? true
        guard let tomorrow = weekCalendar.addingDays(1, to: today), nothingToday || isTrainingDone(today, workouts: reading.allWorkouts, now: now) else {
            return
        }
        if loader.dayPlan(on: tomorrow) == nil, loader.canPreview(tomorrow), !Task.isCancelled {
            await loader.loadPreview(for: tomorrow)
        }
    }

    // MARK: - Plan für heute vorab

    /// Morgens, bevor du die App öffnest: Fehlt der Plan für heute, die Anfrage mit dem frisch gelesenen Zustand an iOS
    /// abgeben. Die Antwort kommt über `receiveTodayAhead`, auch wenn die App bis dahin wieder schläft.
    private func requestTodayAhead(now: Date, workouts: [Workout]) async {
        let today = weekLoader.todayKey
        guard Calendar.current.component(.hour, from: now) >= Self.todayAheadFromHour,
              todayAheadAttempts(on: today) < Self.todayAheadAttempts,
              !isTrainingDone(today, workouts: workouts, now: now),
              let ahead = loader.todayAheadRequest(),
              let client = planClient() else { return }
        let pending = await fetcher.hasPendingRequest()
        guard !pending else { return }
        do {
            let request = try await client.dayPlanV2URLRequest(ahead.request)
            try fetcher.start(request, target: ahead.target)
            defaults.set("\(today)|\(todayAheadAttempts(on: today) + 1)", forKey: Self.todayAheadKey)
        } catch {
            // Ohne Einwilligung oder Konfiguration plant Heute beim Öffnen und fragt dort nach.
        }
    }

    private func todayAheadAttempts(on date: String) -> Int {
        let parts = (defaults.string(forKey: Self.todayAheadKey) ?? "").split(separator: "|")
        guard parts.count == 2, parts[0] == date else { return 0 }
        return Int(parts[1]) ?? 0
    }

    /// Die Antwort auf den Plan für heute: als Plan von heute bereitlegen, Widget auffrischen und melden.
    private func receiveTodayAhead(_ plan: DayPlanV2Response?, target: DayTargetV2) {
        guard let plan, loader.acceptTodayAhead(plan, target: target) else { return }
        updateGlance()
        guard preferences.morningPlan,
              UIApplication.shared.applicationState != .active,
              let notice = CoachNotices.morningPlan(plan) else { return }
        // Vor der eingestellten Uhrzeit dann, danach sofort.
        post(notice, at: CoachNotices.morningDate(for: plan.date, preferences: preferences, now: Date()))
    }

    /// Alles, was heute geplant war, ist gemacht (wie in Aktuell).
    private func isTrainingDone(_ date: String, workouts: [Workout], now: Date) -> Bool {
        let status = MultiSportWeekProgressCalculator().statuses(
            plan: weekLoader.week(starting: weekLoader.currentWeekStart),
            weekStart: weekLoader.currentWeekStart,
            workouts: workouts,
            now: now
        ).first { $0.date == date }
        return status?.isTrainingDone == true
    }

    // MARK: - Widget

    /// Schreibt, was Widget und Sperrbildschirm zeigen: heute, nach erledigtem Training morgen; der konkrete Plan, sonst
    /// die Vorgabe der 14 Tage. Nur bei einer Änderung laden die Widgets neu.
    func updateGlance() {
        let now = Date()
        let today = weekLoader.todayKey
        let done = isTrainingDone(today, workouts: loader.reading?.allWorkouts ?? [], now: now)
        let date = done ? (weekCalendar.addingDays(1, to: today) ?? today) : today
        let glance: PlanGlance
        if let plan = loader.dayPlan(on: date) {
            glance = PlanGlance.make(date: date, todayDone: done, plan: plan.plan, now: now)
        } else if let day = weekLoader.day(on: date) {
            glance = PlanGlance.make(day: day, todayDone: done, now: now)
        } else {
            return
        }
        if PlanGlanceStore.shared().save(glance) {
            WidgetCenter.shared.reloadAllTimelines()
        }
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
