import BackgroundTasks
import HealthKit
import UIKit
import UserNotifications
import WidgetKit
import SwimInstructorCore

/// Der Coach arbeitet, ohne dass die App offen ist: Landet eine Einheit oder die Nacht in Health (Health weckt die App) oder
/// gibt iOS der App Zeit im Hintergrund, liest er Health neu, fragt mit einer Mitteilung "Wie war's?" und holt nach
/// erledigtem Training den Plan für morgen. Morgens stimmt er zuerst die nächsten 14 Tage ab (meldet, was sich spürbar
/// geändert hat und warum) und holt danach den Plan für heute mit der letzten Nacht. Steht der Plan, kommt er morgens zur
/// eingestellten Uhrzeit als Mitteilung, und Aktuell zeigt ihn beim Öffnen sofort.
///
/// Grenzen von iOS: Health lässt sich nur bei entsperrtem iPhone lesen, und wann die App im Hintergrund Zeit bekommt,
/// entscheidet das System. Beide Pläne brauchen länger als diese Zeit; die Anfragen laufen darum als Übertragung im
/// Hintergrund weiter (`BackgroundPlanFetcher`). Klappt es nicht, plant Aktuell beim Öffnen wie bisher.
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
    private static let replanKey = "coach.replanAhead"

    @Published private(set) var preferences: NotificationPreferences

    private let loader: MultiSportTodayLoader
    private let weekLoader: MultiSportWeekLoader
    private let feedbackBook: SessionFeedbackBook
    private let preferencesStore: NotificationPreferencesStoring
    private let log: NoticeLogging
    private let planClient: @MainActor () -> PlanAPIClient?
    private let replanStamp: @MainActor () -> String?
    private let todayWish: @MainActor () -> String?
    private let messages: CoachMessageStoring
    private let fetcher = BackgroundPlanFetcher.shared
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
        replanStamp: @escaping @MainActor () -> String?,
        todayWish: @escaping @MainActor () -> String?,
        messages: CoachMessageStoring = UserDefaultsCoachMessageStore(),
        preferencesStore: NotificationPreferencesStoring = UserDefaultsNotificationPreferencesStore(),
        log: NoticeLogging = UserDefaultsNoticeLog()
    ) {
        self.planClient = planClient
        self.replanStamp = replanStamp
        self.todayWish = todayWish
        self.messages = messages
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
        fetcher.onDayDelivery = { [weak self] plan, target in self?.receiveTodayAhead(plan, target: target) }
        fetcher.onWeekDelivery = { [weak self] plan, replan in self?.receiveReplan(plan, replan: replan) }
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
        if preferences.morningPlan || preferences.afterWorkout || preferences.planChanges { requestPermission() }
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
        // Auf der Watch bewertet: die Frage "Wie war's?" zur Einheit zurückziehen, auch wenn sie schon da ist.
        if #available(iOS 18.0, *) {
            observe(HKQuantityType(.workoutEffortScore), name: "Neue Bewertung") { coach in
                await coach.withdrawRatedFeedback()
            }
        }
    }

    private func observe(
        _ type: HKSampleType,
        name: String,
        work: @escaping @MainActor (BackgroundCoach) async -> Void = { await $0.run() }
    ) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            Task { @MainActor in
                if let self {
                    await self.runWithBackgroundTime(name: name) { await work(self) }
                }
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
    private func runWithBackgroundTime(name: String, work: () async -> Void) async {
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                Task { @MainActor in self?.endBackgroundTime() }
            }
        }
        await work()
        endBackgroundTime()
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Ein Durchgang

    /// Health lesen, nach neuen Einheiten fragen, morgens den Plan für heute anstoßen, nach erledigtem Training den Plan
    /// für morgen holen und die Morgen-Mitteilung stellen. Ist die App offen, läuft kein Durchgang: Dort entsteht ein neuer
    /// Plan nur auf Tipp (Runterziehen liest nur Health).
    func run() async {
        guard !isRunning, UIApplication.shared.applicationState != .active else { return }
        // Bei gesperrtem iPhone gibt Health nichts heraus.
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        isRunning = true
        defer { isRunning = false }

        await loader.readHealth()
        guard let reading = loader.reading else { return }
        let now = Date()
        await notifyNewWorkouts(reading.allWorkouts, now: now)
        // Die Bewertung kann nach der Frage angekommen sein (etwa bei gesperrtem iPhone).
        await withdrawRatedFeedback()

        let today = weekLoader.todayKey
        defer {
            scheduleMorningNotice()
            updateGlance()
        }
        // Morgens zuerst die 14 Tage: Der Plan für heute richtet sich danach und folgt auf ihre Antwort.
        if await requestReplan(now: now) { return }
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

    // MARK: - Die nächsten 14 Tage vorab

    /// Ab 4 Uhr, bevor du die App öffnest: Ist die tägliche Abstimmung der 14 Tage fällig (oder gibt es einen Anlass
    /// außer der Reihe), die Anfrage an iOS abgeben. Nicht, solange der Gesamtplan neu entstehen oder fortgeschrieben
    /// werden muss: Das macht das Öffnen, und danach stimmen sich die Tage ohnehin neu ab. `true`, wenn sie unterwegs ist.
    private func requestReplan(now: Date) async -> Bool {
        let today = weekLoader.todayKey
        guard Calendar.current.component(.hour, from: now) >= Self.todayAheadFromHour,
              attempts(Self.replanKey, on: today) < Self.todayAheadAttempts,
              let stamp = replanStamp(),
              let ahead = weekLoader.backgroundReplanRequest(wishes: todayWish(), stamp: stamp),
              let client = planClient() else { return false }
        guard !(await fetcher.hasPendingRequest()) else { return true }
        do {
            let request = try await client.weekPlanV2URLRequest(ahead.request)
            try fetcher.start(request, replan: ahead.replan)
            countAttempt(Self.replanKey, on: today)
            return true
        } catch {
            // Ohne Einwilligung oder Konfiguration stimmt Aktuell beim Öffnen ab.
            return false
        }
    }

    /// Die Antwort auf die 14 Tage: übernehmen, eine spürbare Änderung melden und gleich den Plan für heute holen.
    private func receiveReplan(_ plan: WeekPlanV2Response?, replan: BackgroundReplan) {
        guard let plan, let report = weekLoader.acceptBackgroundReplan(plan, replan: replan) else { return }
        updateGlance()
        notifyPlanChange(report, date: replan.fromDate)
        guard UIApplication.shared.applicationState != .active else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runWithBackgroundTime(name: "Plan für heute") {
                // iOS kann die App nur für die Antwort neu gestartet haben: Dann fehlt der gelesene Zustand.
                if self.loader.reading == nil, UIApplication.shared.isProtectedDataAvailable { await self.loader.readHealth() }
                guard let reading = self.loader.reading else { return }
                await self.requestTodayAhead(now: Date(), workouts: reading.allWorkouts)
                self.scheduleMorningNotice()
            }
        }
    }

    /// "Dein Coach hat deinen Plan angepasst": nur bei einer spürbaren Änderung oder einem Anlass außer der Reihe,
    /// nicht bei offener App (dort steht es in Aktuell). Nachts wartet sie bis zur Uhrzeit des Morgenplans.
    private func notifyPlanChange(_ report: PlanChangeReport, date: String) {
        guard preferences.planChanges,
              UIApplication.shared.applicationState != .active,
              let notice = CoachNotices.planChanged(report, on: date, calendar: weekCalendar) else { return }
        let now = Date()
        messages.save(CoachNotices.planChangedMessage(report, notice: notice, at: now, calendar: weekCalendar))
        post(
            notice,
            trigger: CoachNotices.morningDate(for: date, preferences: preferences, now: now).map(Self.calendarTrigger),
            route: .message(id: notice.id)
        )
    }

    private func attempts(_ key: String, on date: String) -> Int {
        let parts = (defaults.string(forKey: key) ?? "").split(separator: "|")
        guard parts.count == 2, parts[0] == date else { return 0 }
        return Int(parts[1]) ?? 0
    }

    private func countAttempt(_ key: String, on date: String) {
        defaults.set("\(date)|\(attempts(key, on: date) + 1)", forKey: key)
    }

    // MARK: - Plan für heute vorab

    /// Morgens, bevor du die App öffnest: Fehlt der Plan für heute, die Anfrage mit dem frisch gelesenen Zustand an iOS
    /// abgeben. Die Antwort kommt über `receiveTodayAhead`, auch wenn die App bis dahin wieder schläft.
    private func requestTodayAhead(now: Date, workouts: [Workout]) async {
        let today = weekLoader.todayKey
        guard Calendar.current.component(.hour, from: now) >= Self.todayAheadFromHour,
              attempts(Self.todayAheadKey, on: today) < Self.todayAheadAttempts,
              !isTrainingDone(today, workouts: workouts, now: now),
              let ahead = loader.todayAheadRequest(),
              let client = planClient() else { return }
        let pending = await fetcher.hasPendingRequest()
        guard !pending else { return }
        do {
            let request = try await client.dayPlanV2URLRequest(ahead.request)
            try fetcher.start(request, target: ahead.target)
            countAttempt(Self.todayAheadKey, on: today)
        } catch {
            // Ohne Einwilligung oder Konfiguration plant Heute beim Öffnen und fragt dort nach.
        }
    }

    /// Die Antwort auf den Plan für heute: als Plan von heute bereitlegen, Widget auffrischen und melden.
    private func receiveTodayAhead(_ plan: DayPlanV2Response?, target: DayTargetV2) {
        guard let plan, loader.acceptTodayAhead(plan, target: target) else { return }
        updateGlance()
        guard preferences.morningPlan,
              UIApplication.shared.applicationState != .active,
              let notice = CoachNotices.morningPlan(plan) else { return }
        // Vor der eingestellten Uhrzeit dann, danach sofort.
        post(notice, at: CoachNotices.morningDate(for: plan.date, preferences: preferences, now: Date()), route: .today)
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

    /// "Wie war's?" für Einheiten der letzten Stunden ohne Rückmeldung, je Einheit einmal. Nicht für Einheiten, die du
    /// auf der Watch schon bewertet hast; die Frage kommt darum frühestens `CoachNotices.feedbackDelay` nach dem Ende.
    private func notifyNewWorkouts(_ workouts: [Workout], now: Date) async {
        guard preferences.afterWorkout else { return }
        let fresh = feedbackBook.pending(workouts: workouts, now: now)
            .filter { now.timeIntervalSince($0.endDate) <= Self.feedbackWindow }
        for workout in fresh {
            let notice = CoachNotices.feedback(for: workout)
            if await hasOwnRating(start: workout.startDate, end: workout.endDate) {
                log.markSent(notice.id)
                withdraw(notice.id)
                continue
            }
            guard !log.wasSent(notice.id) else { continue }
            log.markSent(notice.id)
            post(
                notice,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: CoachNotices.feedbackDelay(after: workout.endDate, now: now), repeats: false),
                route: .feedback(start: workout.startDate, end: workout.endDate)
            )
        }
    }

    /// Neue Bewertung in Health: Fragen zu Einheiten, die jetzt bewertet sind, zurückziehen (geplant oder schon da).
    private func withdrawRatedFeedback() async {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications().map(\.request)
        for request in pending + delivered where CoachNotices.isFeedbackID(request.identifier) {
            guard case let .feedback(start, end)? = NotificationRoute(identifier: request.identifier, userInfo: request.content.userInfo) else { continue }
            if await hasOwnRating(start: start, end: end) {
                withdraw(request.identifier)
            }
        }
    }

    /// Ob es zur Einheit eine eigene Bewertung gibt (Watch oder Fitness-App), nicht nur Apples Schätzung.
    private func hasOwnRating(start: Date, end: Date) async -> Bool {
        guard #available(iOS 18.0, *) else { return false }
        let predicate = HKQuery.predicateForSamples(
            withStart: start.addingTimeInterval(-1),
            end: end.addingTimeInterval(1),
            options: [.strictStartDate, .strictEndDate]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.workoutEffortScore), predicate: predicate)],
            sortDescriptors: [],
            limit: 1
        )
        let samples = (try? await descriptor.result(for: healthStore)) ?? []
        return !samples.isEmpty
    }

    /// Nimmt eine Frage zurück: geplant und in der Mitteilungszentrale.
    func withdraw(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
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
        post(notice, at: date, route: .today)
    }

    private func post(_ notice: CoachNotice, at date: Date?, route: NotificationRoute) {
        post(notice, trigger: date.map(Self.calendarTrigger), route: route)
    }

    private static func calendarTrigger(_ date: Date) -> UNNotificationTrigger {
        UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
    }

    /// Ohne Auslöser sofort. Die Route sagt der App, was sie beim Antippen zeigt (`NotificationRouter`).
    private func post(_ notice: CoachNotice, trigger: UNNotificationTrigger?, route: NotificationRoute) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.userInfo = route.userInfo
        center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger)) { _ in }
    }
}
