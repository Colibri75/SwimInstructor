import Foundation

/// Zählt, wie weit die Digital Crown am Stück gedreht wurde, und meldet, wann der nächste Abschnitt
/// des Plans beginnen soll.
///
/// Die Richtung ist egal (ob "nach oben" bei dieser Uhr ein positiver oder negativer Wert ist, ließ
/// sich nicht verlässlich sagen). Eine Pause in der Drehung setzt den Zähler zurück: Ein kurzes
/// Anstoßen beim Tragen löst nichts aus, "weiterdrehen, bis der Kreis voll ist" schon.
///
/// Bei Wassersperre ist die Schwelle höher. Das System entsperrt mit einer Drehung der Crown, und
/// diese Drehung soll noch nicht den Abschnitt wechseln.
public struct CrownRotationTracker: Equatable, Sendable {
    /// Crown-Einheiten bis zum Wechsel bei entsperrter Uhr.
    public static let unlockedThreshold = 3.0
    /// Crown-Einheiten bis zum Wechsel bei Wassersperre.
    public static let lockedThreshold = 8.0
    /// So lange darf die Drehung ruhen, bevor von vorn gezählt wird.
    public static let idleReset: TimeInterval = 1.2
    /// Sprünge über diesen Wert sind das Zurücksetzen der Crown durch die Ansicht, keine Drehung.
    public static let resetJump = 25.0

    /// Bisher am Stück gedrehte Strecke in Crown-Einheiten.
    public private(set) var travel = 0.0
    private var lastValue = 0.0
    private var lastMove: Date?

    public init() {}

    public static func threshold(isLocked: Bool) -> Double {
        isLocked ? lockedThreshold : unlockedThreshold
    }

    /// Fortschritt von 0 bis 1 für die Anzeige.
    public func progress(isLocked: Bool) -> Double {
        min(travel / Self.threshold(isLocked: isLocked), 1)
    }

    /// Neuer Wert der Crown. `true`: weit genug gedreht, der Zähler steht danach wieder auf 0.
    public mutating func moved(to value: Double, isLocked: Bool, at now: Date) -> Bool {
        let delta = value - lastValue
        lastValue = value
        guard abs(delta) <= Self.resetJump else { return false }
        resetIfIdle(at: now)
        guard delta != 0 else { return false }

        lastMove = now
        travel += abs(delta)
        guard travel >= Self.threshold(isLocked: isLocked) else { return false }
        travel = 0
        lastMove = nil
        return true
    }

    /// Regelmäßig aufrufen: Lässt die Drehung nach, springt die Anzeige zurück auf 0.
    public mutating func resetIfIdle(at now: Date) {
        guard let lastMove, now.timeIntervalSince(lastMove) > Self.idleReset else { return }
        travel = 0
        self.lastMove = nil
    }

    /// Die Ansicht hat die Crown auf 0 zurückgesetzt: Der Sprung dorthin zählt nicht als Drehung.
    public mutating func rebase() {
        lastValue = 0
    }
}
