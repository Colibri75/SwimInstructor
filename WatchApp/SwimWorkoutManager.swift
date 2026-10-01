import Foundation
import HealthKit
import SwimInstructorCore
import WatchKit

/// Zeichnet eine Beckeneinheit auf: HKWorkoutSession mit Beckenlänge, Live-Werte über den
/// HKLiveWorkoutBuilder, am Ende wird das Workout in Health gespeichert. Das iPhone sieht es dann
/// beim nächsten Öffnen und der nächste Plan berücksichtigt es.
///
/// Der Manager hält auch den Stand im Tagesplan (`progress`): Er läuft mit der Strecke mit, und der
/// Athlet kann den nächsten Abschnitt von Hand auslösen (Crown, Taste, Tastenkombination). Alle Ansichten
/// lesen diesen einen Stand, statt ihn selbst zu berechnen.
@MainActor
final class SwimWorkoutManager: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case paused
        case saving
        /// `saved == false`: aufgezeichnet, aber nicht in Health gelandet.
        case finished(saved: Bool)

        var isActive: Bool {
            switch self {
            case .starting, .running, .paused, .saving: return true
            case .idle, .finished: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var metrics = LiveSwimMetrics.zero
    @Published private(set) var poolLengthMeters = PoolLength.defaultMeters
    @Published private(set) var errorMessage: String?
    /// Die Abschnitte des Plans, mit dem diese Einheit gestartet wurde (leer ohne Plan).
    @Published private(set) var planSets: [PlanSet] = []
    /// Stand im Plan: läuft mit der Strecke mit und springt bei einem Wechsel von Hand. `nil` ohne Plan.
    @Published private(set) var progress: PlanProgressState?
    /// Abschnittswechsel von Hand (Strecke und Richtung), in der Reihenfolge, in der sie passierten.
    @Published private(set) var sectionMoves: [SectionMove] = []
    /// Wassersperre an? Wird zweimal pro Sekunde aktualisiert.
    @Published private(set) var isWaterLocked = true
    /// Wie weit die Crown am Stück gedreht ist (0 bis 1). Zeigt auf der Uhr, ob Drehungen ankommen.
    @Published private(set) var crownProgress = 0.0
    /// Richtung der laufenden Crown-Drehung (hoch = weiter, runter = zurück), `nil` ohne Drehung.
    @Published private(set) var crownStep: CrownStep?
    /// Letztes Ereignis (Wechsel, Pause von der Uhr), als Kontrolle auf der Uhr.
    @Published private(set) var lastGestureNote = "noch nichts"

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lapEvents = 0
    private var waterLock = WaterLockControl()
    private var crown = CrownRotationTracker()
    private var sectionGesture = SectionGesture()
    private var pausedByButtonOnScreen = false
    private var tickTimer: Timer?

    func start(poolLengthMeters: Int, plan: TrainingPlan? = nil) async {
        guard !phase.isActive else { return }
        let poolLength = PoolLength.clamped(poolLengthMeters)
        self.poolLengthMeters = poolLength
        metrics = .zero
        lapEvents = 0
        planSets = plan?.sets ?? []
        sectionMoves = []
        progress = nil
        recomputeProgress()
        waterLock = WaterLockControl()
        crown = CrownRotationTracker()
        sectionGesture.reset()
        pausedByButtonOnScreen = false
        lastGestureNote = "noch nichts"
        errorMessage = nil
        phase = .starting

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .swimming
        configuration.swimmingLocationType = .pool
        configuration.lapLength = HKQuantity(unit: .meter(), doubleValue: Double(poolLength))

        do {
            let readTypes = HealthKitManager.readTypes.union(HealthKitManager.workoutShareTypes.map { $0 as HKObjectType })
            try await healthStore.requestAuthorization(toShare: HealthKitManager.workoutShareTypes, read: readTypes)

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
            // Damit Health und Apples Fitness-App die Einheit als Beckenschwimmen mit dieser
            // Bahnlänge führen (wie bei Apples eigener Schwimm-App).
            try? await builder.addMetadata([
                HKMetadataKeyLapLength: HKQuantity(unit: .meter(), doubleValue: Double(poolLength)),
                HKMetadataKeySwimmingLocationType: NSNumber(value: HKWorkoutSwimmingLocationType.pool.rawValue)
            ])
            phase = .running
            lockWater()
            startTicking()
        } catch {
            errorMessage = "Training konnte nicht starten: \(error.localizedDescription)"
            session?.end()
            session = nil
            builder = nil
            stopTicking()
            phase = .idle
        }
    }

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

    /// Zurück zur Plananzeige nach der Zusammenfassung.
    func reset() {
        guard !phase.isActive else { return }
        stopTicking()
        phase = .idle
        metrics = .zero
        planSets = []
        sectionMoves = []
        progress = nil
        sectionGesture.reset()
        errorMessage = nil
    }

    /// Laufzeit ohne Pausen, für die sekündliche Anzeige.
    func elapsedTime(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? metrics.elapsed
    }

    // MARK: - Abschnitte

    /// Nächster Abschnitt von Hand: Der laufende gilt an der aktuellen Strecke als beendet.
    func advanceSection(source: String = "Taste") {
        moveSection(.next, source: source)
    }

    /// Wechsel von Hand in eine Richtung. Funktioniert auch ohne Streckenangabe aus Health (dann bei
    /// 0 m) und bei pausierter Einheit.
    func moveSection(_ direction: SectionDirection, source: String) {
        guard phase == .running || phase == .paused else {
            lastGestureNote = "\(source): Einheit läuft nicht"
            return
        }
        guard !planSets.isEmpty else {
            lastGestureNote = "\(source): kein Plan"
            return
        }
        guard canMove(direction) else {
            lastGestureNote = direction == .next ? "\(source): kein weiterer Abschnitt" : "\(source): schon im ersten Abschnitt"
            return
        }
        let meters = metrics.progressMeters(poolLengthMeters: poolLengthMeters)
        sectionMoves.append(SectionMove(meters: meters, direction: direction))
        recomputeProgress()
        let name = direction == .next ? "weiter" : "zurück"
        lastGestureNote = "\(source): \(name) bei \(Int(meters)) m"
        if phase == .running { lockWater() }
    }

    private func canMove(_ direction: SectionDirection) -> Bool {
        guard let progress else { return false }
        switch (direction, progress) {
        case (.next, .inProgress): return true
        case (.previous, .inProgress(let position)): return position.setIndex > firstCountableIndex
        case (.previous, .completed): return true
        default: return false
        }
    }

    /// Erster Abschnitt mit Strecke (Abschnitte ohne Meter zählen nicht).
    private var firstCountableIndex: Int {
        planSets.firstIndex { $0.repetitions > 0 && $0.distanceMeters > 0 } ?? 0
    }

    /// Rechnet den Stand im Plan aus Strecke und Wechseln von Hand neu. Springt der Abschnitt weiter,
    /// egal ob durch die Strecke oder von Hand, gibt es einen Haptik-Impuls.
    private func recomputeProgress() {
        guard !planSets.isEmpty else {
            if progress != nil { progress = nil }
            return
        }
        let new = PlanProgress.state(
            sets: planSets,
            swumMeters: metrics.progressMeters(poolLengthMeters: poolLengthMeters),
            moves: sectionMoves
        )
        guard new != progress else { return }
        let oldIndex = progress?.sectionIndex(setCount: planSets.count)
        progress = new
        if let oldIndex {
            let newIndex = new.sectionIndex(setCount: planSets.count)
            if newIndex != oldIndex {
                WKInterfaceDevice.current().play(newIndex > oldIndex ? .directionUp : .directionDown)
            }
        }
    }

    // MARK: - Wassersperre und Crown

    /// Wassersperre wie bei Apples Schwimm-App: Entsperren mit der Digital Crown. Sie ist an, solange
    /// die Einheit läuft, und geht nach Fortsetzen, nach einem Abschnittswechsel und nach einer Weile
    /// ohne Eingabe wieder an.
    private func lockWater() {
        WKInterfaceDevice.current().enableWaterLock()
    }

    /// Eigener Takt, unabhängig von den Ansichten: Läuft, solange eine Einheit aktiv ist, auch wenn der
    /// Athlet zwischen den Seiten wischt.
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

    /// Erkennt das Entsperren, sperrt nach einer Weile ohne Eingabe wieder und lässt eine liegen
    /// gebliebene Crown-Drehung verfallen. Setzt nur Werte, die sich ändern, damit die Ansicht nicht
    /// ohne Grund neu zeichnet.
    private func tick(now: Date = Date()) {
        let locked = WKInterfaceDevice.current().isWaterLockEnabled
        if locked != isWaterLocked { isWaterLocked = locked }
        crown.resetIfIdle(at: now)
        publishCrown(isLocked: locked)
        if waterLock.update(isRunning: phase == .running, isLocked: locked, now: now) == .lock {
            lockWater()
        }
    }

    /// Setzt nur Werte, die sich ändern, damit die Ansicht nicht ohne Grund neu zeichnet.
    private func publishCrown(isLocked: Bool) {
        let value = crown.progress(isLocked: isLocked)
        if value != crownProgress { crownProgress = value }
        let step = crown.step
        if step != crownStep { crownStep = step }
    }

    /// Die Crown wurde bewegt (neuer Wert seit dem letzten Zurücksetzen). Weit genug am Stück gedreht:
    /// nach oben der nächste, nach unten der vorherige Abschnitt, bei Wassersperre und entsperrt.
    /// `true`: Der Aufrufer setzt die Crown auf 0 zurück.
    func crownMoved(_ value: Double, now: Date = Date()) -> Bool {
        let locked = WKInterfaceDevice.current().isWaterLockEnabled
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
            lockWater()
            // Zweimal kurz Crown + Seitentaste (Pause und gleich Weiter): nächster Abschnitt.
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
        var saved = false
        do {
            try await builder.endCollection(at: date)
            saved = try await builder.finishWorkout() != nil
        } catch {
            errorMessage = "Nicht in Health gespeichert: \(error.localizedDescription)"
        }
        metrics.elapsed = builder.elapsedTime
        session = nil
        self.builder = nil
        phase = .finished(saved: saved)
    }

    private func update(_ statistics: CollectedStatistics) {
        metrics.distanceMeters = statistics.distanceMeters
        metrics.strokes = statistics.strokes
        metrics.activeEnergyKilocalories = statistics.activeEnergyKilocalories
        if let heartRate = statistics.heartRate {
            metrics.heartRate = heartRate
        }
        metrics.elapsed = statistics.elapsed
        updateLaps()
    }

    private func updateLaps() {
        metrics.laps = LiveSwimMetrics.laps(
            lapEvents: lapEvents,
            distanceMeters: metrics.distanceMeters,
            poolLengthMeters: poolLengthMeters
        )
        recomputeProgress()
    }
}

/// Werte aus dem Builder, gelesen auf dem Callback-Thread und dann an den Main Actor gereicht.
private struct CollectedStatistics: Sendable {
    let distanceMeters: Double
    let strokes: Double
    let heartRate: Double?
    let activeEnergyKilocalories: Double
    let elapsed: TimeInterval

    init(builder: HKLiveWorkoutBuilder) {
        func sum(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double {
            builder.statistics(for: HKQuantityType(identifier))?.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        distanceMeters = sum(.distanceSwimming, .meter())
        strokes = sum(.swimmingStrokeCount, .count())
        activeEnergyKilocalories = sum(.activeEnergyBurned, .kilocalorie())
        heartRate = builder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        elapsed = builder.elapsedTime
    }
}

extension SwimWorkoutManager: HKWorkoutSessionDelegate {
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

extension SwimWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let statistics = CollectedStatistics(builder: workoutBuilder)
        Task { @MainActor in self.update(statistics) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        let laps = workoutBuilder.workoutEvents.filter { $0.type == .lap }.count
        Task { @MainActor in
            self.lapEvents = laps
            self.updateLaps()
        }
    }
}
