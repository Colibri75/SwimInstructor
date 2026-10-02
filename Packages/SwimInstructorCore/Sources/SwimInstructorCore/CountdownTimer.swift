import Foundation

/// Wie lange der Countdown vor dem Training und die Pause zwischen den Sätzen dauern.
public enum TrainingTimers {
    /// Vor dem Training: Zeit, um ins Wasser zu kommen und die Uhr zu sperren.
    public static let startCountdownSeconds: TimeInterval = 30
    /// Nach jedem Wechsel zum nächsten Satz: Pause, bevor es weitergeht.
    public static let restBetweenSetsSeconds: TimeInterval = 30
    /// Die letzten Sekunden vor dem Ende geben bei jeder Sekunde einen Impuls.
    public static let warningSeconds = 3
}

/// Ein einfacher Countdown nach der Wanduhr. Er rechnet mit Zeitpunkten statt mit Takten, damit er auch
/// stimmt, wenn die App kurz nicht dran kommt.
public struct CountdownTimer: Equatable, Sendable {
    public let duration: TimeInterval
    private var startedAt: Date?

    public init(duration: TimeInterval) {
        self.duration = max(duration, 0)
    }

    public var isRunning: Bool { startedAt != nil }

    public mutating func start(at now: Date) {
        startedAt = now
    }

    public mutating func cancel() {
        startedAt = nil
    }

    /// Verbleibende ganze Sekunden (aufgerundet, also 30 zu Beginn und 0 erst am Ende); `nil`, wenn er
    /// nicht läuft.
    public func remainingSeconds(at now: Date) -> Int? {
        guard let startedAt else { return nil }
        let left = duration - now.timeIntervalSince(startedAt)
        return max(Int(left.rounded(.up)), 0)
    }

    /// Ist er gestartet und abgelaufen?
    public func isFinished(at now: Date) -> Bool {
        remainingSeconds(at: now) == 0
    }
}
