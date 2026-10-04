import Foundation
import HealthKit
import SwimInstructorCore
import WatchKit

/// Was vor dem Start feststeht: Sportart, Ort, Bahnlänge und die Einheit aus dem Plan (`nil` bei freiem Training).
struct WorkoutStart: Equatable {
    let sport: SportID
    let locationID: String
    let lapLengthMeters: Int
    let session: DaySession?
    /// Ansagen der Schritte vorlesen.
    let announces: Bool
}

/// Zeichnet eine Einheit jeder Sportart auf: HKWorkoutSession mit der Konfiguration aus dem Sport-Modul, Live-Werte über
/// den HKLiveWorkoutBuilder, draußen die GPS-Strecke. Am Ende landet das Workout in Health; das iPhone sieht es beim
/// nächsten Öffnen, und der nächste Plan berücksichtigt es.
///
/// Der Manager hält auch den Stand im Plan (`progress`): Er läuft mit Strecke und Zeit mit, und der Athlet kann den
/// nächsten oder vorigen Schritt von Hand auslösen (Crown, Taste, Tastenkombination). Bei einem Leistungstest wertet er die
/// Aufzeichnung am Ende aus und schickt das Ergebnis ans iPhone, wo der Athlet es bestätigt.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Countdown vor dem Training (30 Sekunden), bevor die Aufzeichnung startet.
        case countdown
        case starting
        case running
        case paused
        case saving
        /// `saved == false`: aufgezeichnet, aber nicht in Health gelandet.
        case finished(saved: Bool)

        var isActive: Bool {
            switch self {
            case .countdown, .starting, .running, .paused, .saving: return true
            case .idle, .finished: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// Womit die laufende (oder zuletzt beendete) Einheit gestartet wurde.
    @Published private(set) var start: WorkoutStart?
    @Published private(set) var metrics = LiveWorkoutMetrics.zero
    @Published private(set) var errorMessage: String?
    /// Stand im Plan; ohne Plan ohne Schritte. Nicht `@Published`: Die Engine rechnet zweimal pro Sekunde weiter, die
    /// Ansichten lesen sie im Sekundentakt (`status(at:)`). Neu gezeichnet wird bei jedem Wechsel (`progressRevision`).
    private(set) var progress = SessionProgress(steps: [])
    @Published private(set) var progressRevision = 0
    /// Sekunden bis zum Start im Countdown vor dem Training; `nil` außerhalb.
    @Published private(set) var countdownRemaining: Int?
    /// Wassersperre an? Wird zweimal pro Sekunde aktualisiert.
    @Published private(set) var isWaterLocked = false
    /// Wie weit die Crown am Stück gedreht ist (0 bis 1). Zeigt auf der Uhr, ob Drehungen ankommen.
    @Published private(set) var crownProgress = 0.0
    /// Richtung der laufenden Crown-Drehung (hoch = weiter, runter = zurück), `nil` ohne Drehung.
    @Published private(set) var crownStep: CrownStep?
    /// Letztes Ereignis (Wechsel, Pause von der Uhr), als Kontrolle auf der Uhr.
    @Published private(set) var lastGestureNote = "noch nichts"
    /// Auswertung des Leistungstests nach dem Ende, `nil` ohne Test.
    @Published private(set) var testResult: RecordedTestResult?

    /// Bekommt ein gültiges Testergebnis, um es ans iPhone zu schicken.
    var onTestResult: ((WatchTestResult) -> Void)?

    private let registry = SportRegistry.standard
    private let healthStore = HKHealthStore()
    private let announcer = Announcer()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeRecorder: RouteRecorder?
    private var recording = WorkoutRecording()
    private var speedTracker = SportRecording.standard.speedSmoothing.makeTracker()
    private var lapEvents = 0
    private var waterLock = WaterLockControl()
    private var crown = CrownRotationTracker()
    private var sectionGesture = SectionGesture()
    private var pausedByButtonOnScreen = false
    private var tickTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    /// Wann die laufende Wiederholung begann, für die Rundenmarke eines Testabschnitts.
    private var segmentStartDate = Date()
    /// Zuletzt gemeldete Sekunde der Warn-Impulse vor dem Ende einer Pause oder Wiederholung nach Zeit.
    private var lastWarning: Int?

    // MARK: - Was gerade läuft

    var module: (any SportModule)? {
        start.flatMap { registry.module(for: $0.sport) }
    }

    var location: RecordingLocation? {
        guard let start, let module else { return nil }
        return module.recording.location(id: start.locationID)
    }

    var recordingProfile: SportRecording {
        module?.recording ?? .standard
    }

    /// Becken und Freiwasser: Wassersperre an, solange die Einheit läuft.
    var usesWaterLock: Bool { location?.usesWaterLock ?? false }

    /// Laufzeit ohne Pausen, für die sekündliche Anzeige.
    func elapsedTime(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? metrics.elapsed
    }

    /// Stand im Plan zum Zeitpunkt `date`.
    func status(at date: Date) -> ProgressStatus {
        progress.status(meters: progressMeters, elapsed: elapsedTime(at: date))
    }

    private var progressMeters: Double {
        metrics.progressMeters(lapLengthMeters: recording.lapLengthMeters)
    }

    // MARK: - Start

    /// Startet mit 30 Sekunden Countdown davor: Zeit, ins Wasser oder aufs Rad zu kommen. Der Countdown lässt sich
    /// überspringen (`skipCountdown`) oder abbrechen (`cancelCountdown`).
    func beginCountdown(_ start: WorkoutStart) {
        guard !phase.isActive else { return }
        errorMessage = nil
        testResult = nil
        self.start = start
        var timer = CountdownTimer(duration: TrainingTimers.startCountdownSeconds)
        timer.start(at: Date())
        countdownRemaining = timer.remainingSeconds(at: Date())
        phase = .countdown
        countdownTask?.cancel()
        countdownTask = Task { [weak self, timer] in
            var lastShown = -1
            while !Task.isCancelled {
                let remaining = timer.remainingSeconds(at: Date()) ?? 0
                if remaining != lastShown {
                    lastShown = remaining
                    guard let self, self.phase == .countdown else { return }
                    self.countdownRemaining = remaining
                    // Die letzten Sekunden geben jede Sekunde einen Impuls, am Ende der Start.
                    if remaining == 0 {
                        WKInterfaceDevice.current().play(.start)
                    } else if remaining <= TrainingTimers.warningSeconds {
                        WKInterfaceDevice.current().play(.click)
                    }
                }
                if remaining == 0 { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard !Task.isCancelled, let self, self.phase == .countdown else { return }
            await self.begin()
        }
    }

    /// Den Countdown überspringen und sofort starten.
    func skipCountdown() {
        guard phase == .countdown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        Task { await begin() }
    }

    func cancelCountdown() {
        guard phase == .countdown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
        start = nil
        phase = .idle
    }

    private func begin() async {
        guard phase == .countdown else { return }
        countdownRemaining = nil
        guard let start, let module, let location else {
            errorMessage = "Diese Sportart kennt die Uhr nicht."
            phase = .idle
            return
        }
        metrics = .zero
        lapEvents = 0
        progress = SessionProgress(steps: start.session?.steps ?? [])
        recording = WorkoutRecording(lapLengthMeters: module.lapLength(at: location, lapLengthMeters: start.lapLengthMeters))
        speedTracker = module.recording.speedSmoothing.makeTracker()
        waterLock = WaterLockControl()
        crown = CrownRotationTracker()
        sectionGesture.reset()
        pausedByButtonOnScreen = false
        lastGestureNote = "noch nichts"
        lastWarning = nil
        testResult = nil
        errorMessage = nil
        announcer.isEnabled = start.announces
        phase = .starting

        let configuration = module.workoutConfiguration(at: location, lapLengthMeters: start.lapLengthMeters)
        do {
            let shareTypes = HealthKitManager.workoutShareTypes
            let readTypes = HealthKitManager.readTypes.union(shareTypes.map { $0 as HKObjectType })
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            // Damit Health und Apples Fitness-App die Einheit so führen wie eine aus der eigenen App (Becken mit
            // Bahnlänge, Freiwasser, drinnen oder draußen).
            let metadata = module.workoutMetadata(at: location, lapLengthMeters: start.lapLengthMeters)
            if !metadata.isEmpty {
                try? await builder.addMetadata(metadata)
            }
            if location.recordsRoute {
                let recorder = RouteRecorder(healthStore: healthStore)
                recorder.onElevationGain = { [weak self] gain in self?.metrics.elevationGainMeters = gain }
                recorder.start()
                routeRecorder = recorder
            }
            phase = .running
            if usesWaterLock { lockWater() }
            startTicking()
            segmentStartDate = startDate
            if let unit = progress.current {
                announce(.workStarted(unit))
            }
        } catch {
            errorMessage = "Training konnte nicht starten: \(error.localizedDescription)"
            session?.end()
            session = nil
            builder = nil
            routeRecorder?.stop()
            routeRecorder = nil
            stopTicking()
            phase = .idle
        }
    }

    // MARK: - Steuerung

    func pause() {
        // Pause per Tippen auf dem Bildschirm ist nie die Tastengeste (Crown + Seitentaste).
        pausedByButtonOnScreen = true
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    /// Beendet die Sitzung; gespeichert wird, sobald HealthKit den Zustand `.ended` meldet.
    func end() {
        guard let session else { return }
        phase = .saving
        session.end()
    }

    /// Zurück zum Startbildschirm nach der Zusammenfassung.
    func reset() {
        guard !phase.isActive else { return }
        stopTicking()
        phase = .idle
        start = nil
        metrics = .zero
        progress = SessionProgress(steps: [])
        recording = WorkoutRecording()
        sectionGesture.reset()
        testResult = nil
        errorMessage = nil
    }

    /// Nächster Schritt von Hand.
    func advanceSection(source: String = "Taste") {
        moveSection(.next, source: source)
    }

    /// Wechsel von Hand: weiter beendet die Wiederholung oder die Pause, zurück beginnt die vorige Wiederholung neu.
    /// Funktioniert auch ohne Strecke aus Health und bei pausierter Einheit.
    func moveSection(_ direction: SectionDirection, source: String) {
        guard phase == .running || phase == .paused else {
            lastGestureNote = "\(source): Einheit läuft nicht"
            return
        }
        guard !progress.units.isEmpty else {
            lastGestureNote = "\(source): kein Plan"
            return
        }
        guard progress.canMove(direction) else {
            lastGestureNote = direction == .next ? "\(source): Plan schon geschafft" : "\(source): schon im ersten Schritt"
            return
        }
        let events = progress.move(direction, meters: progressMeters, elapsed: elapsedTime(at: Date()))
        handle(events, manual: direction)
        lastGestureNote = "\(source): \(direction == .next ? "weiter" : "zurück")"
        if phase == .running, usesWaterLock { lockWater() }
    }

    // MARK: - Fortschritt

    private func advanceProgress(now: Date = Date()) {
        guard phase == .running || phase == .paused, !progress.units.isEmpty else { return }
        handle(progress.update(meters: progressMeters, elapsed: elapsedTime(at: now)), manual: nil)
        warnBeforeEnd(now: now)
    }

    /// Haptik, Ansagen und Rundenmarken zu den Ereignissen der Engine.
    private func handle(_ events: [ProgressEvent], manual: SectionDirection?) {
        if !events.isEmpty { progressRevision += 1 }
        for event in events {
            switch event {
            case .workStarted:
                segmentStartDate = Date()
                lastWarning = nil
                WKInterfaceDevice.current().play(manual == .previous ? .directionDown : (manual == nil ? .start : .directionUp))
            case let .workEnded(segment):
                if segment.unit.step.isTestEffort {
                    addSegmentMarker(from: segmentStartDate, to: Date())
                }
            case .restStarted:
                lastWarning = nil
                WKInterfaceDevice.current().play(.stop)
            case .completed:
                WKInterfaceDevice.current().play(.success)
            }
            announce(event)
        }
    }

    private func announce(_ event: ProgressEvent) {
        guard let text = ProgressFormatting.announcement(event) else { return }
        announcer.say(text)
    }

    /// Die letzten Sekunden einer Pause oder einer Wiederholung nach Zeit geben jede Sekunde einen Impuls.
    private func warnBeforeEnd(now: Date) {
        let seconds: Int?
        switch status(at: now) {
        case let .rest(_, _, remaining):
            seconds = remaining
        case let .work(unit, _, remaining?):
            if case .seconds? = unit.target { seconds = Int(remaining.rounded(.up)) } else { seconds = nil }
        default:
            seconds = nil
        }
        guard let seconds, seconds > 0, seconds <= TrainingTimers.warningSeconds, seconds != lastWarning else { return }
        lastWarning = seconds
        WKInterfaceDevice.current().play(.click)
    }

    /// Rundenmarke für einen Testabschnitt: erscheint in Health als Abschnitt mit eigener Zeit.
    private func addSegmentMarker(from start: Date, to end: Date) {
        guard let builder, end > start else { return }
        let event = HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: start, end: end), metadata: nil)
        Task { try? await builder.addWorkoutEvents([event]) }
    }

    // MARK: - Wassersperre und Crown

    /// Wassersperre wie bei Apples Schwimm-App: Entsperren mit der Digital Crown. Sie ist an, solange die Einheit läuft,
    /// und geht nach Fortsetzen, nach einem Wechsel und nach einer Weile ohne Eingabe wieder an.
    private func lockWater() {
        WKInterfaceDevice.current().enableWaterLock()
    }

    /// Eigener Takt, unabhängig von den Ansichten: Läuft, solange eine Einheit aktiv ist, auch wenn der Athlet zwischen
    /// den Seiten wischt.
    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Erkennt das Entsperren, sperrt nach einer Weile ohne Eingabe wieder, lässt eine liegen gebliebene Crown-Drehung
    /// verfallen und rechnet den Plan weiter (Wiederholungen nach Zeit und Pausen enden auch ohne neue Messwerte).
    private func tick(now: Date = Date()) {
        let locked = usesWaterLock && WKInterfaceDevice.current().isWaterLockEnabled
        if locked != isWaterLocked { isWaterLocked = locked }
        crown.resetIfIdle(at: now)
        publishCrown(isLocked: locked)
        publishSpeed(atElapsed: elapsedTime(at: now))
        advanceProgress(now: now)
        if usesWaterLock, waterLock.update(isRunning: phase == .running, isLocked: locked, now: now) == .lock {
            lockWater()
        }
    }

    private func publishSpeed(atElapsed elapsed: TimeInterval) {
        let speed = speedTracker.speed(atElapsed: elapsed)
        if speed != metrics.currentSpeed { metrics.currentSpeed = speed }
    }

    /// Setzt nur Werte, die sich ändern, damit die Ansicht nicht ohne Grund neu zeichnet.
    private func publishCrown(isLocked: Bool) {
        let value = crown.progress(isLocked: isLocked)
        if value != crownProgress { crownProgress = value }
        let step = crown.step
        if step != crownStep { crownStep = step }
    }

    /// Die Crown wurde bewegt (neuer Wert seit dem letzten Zurücksetzen). Weit genug am Stück gedreht: nach oben der
    /// nächste, nach unten der vorige Schritt. `true`: Der Aufrufer setzt die Crown auf 0 zurück.
    func crownMoved(_ value: Double, now: Date = Date()) -> Bool {
        let locked = usesWaterLock && WKInterfaceDevice.current().isWaterLockEnabled
        waterLock.noteInput(now: now)
        let reached = crown.moved(to: value, isLocked: locked, at: now)
        publishCrown(isLocked: locked)
        if let reached {
            moveSection(reached.direction, source: "Krone")
        }
        let needsReset = reached != nil || abs(value) > 30
        if needsReset { crown.rebase() }
        return needsReset
    }

    // MARK: - Sitzung

    private func handle(_ state: HKWorkoutSessionState, date: Date) {
        let previousPhase = phase
        switch state {
        case .running:
            phase = .running
            // Auch nach "Weiter": Wer schwimmt, hat die Wassersperre an.
            if usesWaterLock { lockWater() }
            // Zweimal kurz Crown + Seitentaste (Pause und gleich Weiter): nächster Schritt.
            if sectionGesture.didResume(at: date) {
                advanceSection(source: "Tasten")
            } else if case .paused = previousPhase {
                lastGestureNote = "Weiter (Pause zu lang oder per Tippen)"
            }
        case .paused:
            phase = .paused
            lastGestureNote = pausedByButtonOnScreen ? "Pause per Tippen" : "Pause von der Uhr (Tasten)"
            sectionGesture.didPause(at: date, byButtonOnScreen: pausedByButtonOnScreen)
            pausedByButtonOnScreen = false
        case .ended:
            sectionGesture.reset()
            stopTicking()
            Task { await finish(at: date) }
        default:
            break
        }
    }

    private func finish(at date: Date) async {
        guard let builder else { return }
        phase = .saving
        announcer.stop()
        let elapsed = builder.elapsedTime(at: date)
        progress.finish(meters: progressMeters, elapsed: elapsed)
        evaluateTest()
        routeRecorder?.stop()
        var saved = false
        do {
            try await builder.endCollection(at: date)
            if metrics.elevationGainMeters > 0 {
                try? await builder.addMetadata([
                    HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: metrics.elevationGainMeters)
                ])
            }
            if let workout = try await builder.finishWorkout() {
                saved = true
                await routeRecorder?.finish(with: workout)
            }
        } catch {
            errorMessage = "Nicht in Health gespeichert: \(error.localizedDescription)"
        }
        metrics.elapsed = elapsed
        session = nil
        self.builder = nil
        routeRecorder = nil
        phase = .finished(saved: saved)
    }

    /// Bei einem Leistungstest: Auswertung aus der Aufzeichnung, ein gültiges Ergebnis geht ans iPhone.
    private func evaluateTest() {
        guard let start, let planned = start.session?.test, let module,
              let test = module.performanceTests.first(where: { $0.id == planned.id }) else { return }
        recording.segments = progress.segments
        let result = test.evaluate(recording: recording, definitions: module.performanceMetrics)
        testResult = result
        guard result.isValid else { return }
        onTestResult?(WatchTestResult(sport: start.sport, testID: test.id, entries: result.entries, measuredAt: Date()))
    }

    private func update(_ statistics: CollectedStatistics) {
        metrics.distanceMeters = statistics.distanceMeters
        metrics.activeEnergyKilocalories = statistics.activeEnergyKilocalories
        metrics.values.merge(statistics.values) { _, new in new }
        metrics.elapsed = statistics.elapsed
        if let heartRate = statistics.heartRate {
            metrics.heartRate = heartRate.value
            recording.recordHeartRate(heartRate.value, at: heartRate.elapsed)
        }
        if let power = statistics.power {
            recording.recordPower(power.value, at: power.elapsed)
        }
        recording.recordDistance(statistics.distanceMeters, at: statistics.elapsed)
        speedTracker.record(elapsed: statistics.elapsed, distanceMeters: statistics.distanceMeters)
        publishSpeed(atElapsed: statistics.elapsed)
        updateLaps()
    }

    private func updateLaps(_ laps: [LapTime] = []) {
        for lap in laps {
            recording.recordLap(start: lap.start, end: lap.end)
        }
        let lapLength = recording.lapLengthMeters ?? 0
        metrics.laps = lapLength > 0
            ? LiveSwimMetrics.laps(lapEvents: lapEvents, distanceMeters: metrics.distanceMeters, poolLengthMeters: lapLength)
            : 0
        advanceProgress()
    }
}

/// Werte aus dem Builder, gelesen auf dem Callback-Thread und dann an den Main Actor gereicht. Welche Messwerte zur
/// Sportart gehören, sagt das Modul zur Workout-Art des Builders.
private struct CollectedStatistics: Sendable {
    let distanceMeters: Double
    let heartRate: TimedValue?
    let power: TimedValue?
    let activeEnergyKilocalories: Double
    let values: [WorkoutMetric: Double]
    let elapsed: TimeInterval

    init(builder: HKLiveWorkoutBuilder) {
        let mapping = SportRegistry.standard.module(forActivityType: builder.workoutConfiguration.activityType)?.health
        func statistics(_ type: HKQuantityType?) -> HKStatistics? {
            type.flatMap { builder.statistics(for: $0) }
        }
        /// Der letzte Wert mit der Laufzeit seiner Messung.
        func mostRecent(_ type: HKQuantityType?, _ unit: HKUnit) -> TimedValue? {
            guard let collected = statistics(type), let quantity = collected.mostRecentQuantity() else { return nil }
            let measuredAt = collected.mostRecentQuantityDateInterval()?.end ?? Date()
            return TimedValue(elapsed: builder.elapsedTime(at: measuredAt), value: quantity.doubleValue(for: unit))
        }

        if let distance = mapping?.distance {
            distanceMeters = statistics(distance.quantityType)?.sumQuantity()?.doubleValue(for: distance.healthUnit) ?? 0
        } else {
            distanceMeters = 0
        }
        activeEnergyKilocalories = statistics(HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        heartRate = mostRecent(HKQuantityType(.heartRate), HKUnit.count().unitDivided(by: .minute()))

        var values: [WorkoutMetric: Double] = [:]
        for (metric, quantity) in mapping?.metrics ?? [:] {
            let collected = statistics(quantity.quantityType)
            let value = quantity.aggregation == .sum ? collected?.sumQuantity() : collected?.mostRecentQuantity()
            values[metric] = value?.doubleValue(for: quantity.healthUnit)
        }
        self.values = values
        power = mapping?.metrics[.averagePower].flatMap { mostRecent($0.quantityType, $0.healthUnit) }
        elapsed = builder.elapsedTime
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.handle(toState, date: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in self.errorMessage = "Aufzeichnung gestört: \(text)" }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let statistics = CollectedStatistics(builder: workoutBuilder)
        Task { @MainActor in self.update(statistics) }
    }

    /// Bahnen im Becken: Runden-Ereignisse der Uhr, mit Laufzeit von Beginn und Ende für die Testauswertung.
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        let laps = workoutBuilder.workoutEvents
            .filter { $0.type == .lap }
            .map {
                LapTime(
                    start: workoutBuilder.elapsedTime(at: $0.dateInterval.start),
                    end: workoutBuilder.elapsedTime(at: $0.dateInterval.end)
                )
            }
        Task { @MainActor in
            self.lapEvents = laps.count
            self.updateLaps(laps)
        }
    }
}
