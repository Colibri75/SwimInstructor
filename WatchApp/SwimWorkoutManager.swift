import Foundation
import HealthKit
import SwimInstructorCore
import WatchKit

/// Zeichnet eine Beckeneinheit auf: HKWorkoutSession mit Beckenlänge, Live-Werte über den
/// HKLiveWorkoutBuilder, am Ende wird das Workout in Health gespeichert. Das iPhone sieht es dann
/// beim nächsten Öffnen und der nächste Plan berücksichtigt es.
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

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lapEvents = 0

    func start(poolLengthMeters: Int) async {
        guard !phase.isActive else { return }
        let poolLength = PoolLength.clamped(poolLengthMeters)
        self.poolLengthMeters = poolLength
        metrics = .zero
        lapEvents = 0
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
            // Wassersperre wie bei Apples Schwimm-App: Entsperren mit der Digital Crown.
            WKInterfaceDevice.current().enableWaterLock()
        } catch {
            errorMessage = "Training konnte nicht starten: \(error.localizedDescription)"
            session?.end()
            session = nil
            builder = nil
            phase = .idle
        }
    }

    func pause() {
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
        phase = .idle
        metrics = .zero
        errorMessage = nil
    }

    /// Laufzeit ohne Pausen, für die sekündliche Anzeige.
    func elapsedTime(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? metrics.elapsed
    }

    private func handle(_ state: HKWorkoutSessionState, date: Date) {
        switch state {
        case .running:
            phase = .running
        case .paused:
            phase = .paused
        case .ended:
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
