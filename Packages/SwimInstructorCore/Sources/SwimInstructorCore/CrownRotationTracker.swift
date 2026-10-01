import Foundation

/// Was eine lange genug gehaltene Crown-Drehung auslöst.
public enum CrownStep: Equatable, Sendable {
    /// Nach oben gedreht: nächster Abschnitt.
    case next
    /// Nach unten gedreht: vorheriger Abschnitt.
    case previous

    public var direction: SectionDirection {
        switch self {
        case .next: return .next
        case .previous: return .previous
        }
    }
}

/// Zählt, wie weit die Digital Crown am Stück in eine Richtung gedreht wurde, und meldet, wann der
/// Satz des Plans wechseln soll: nach oben weiter, nach unten zurück.
///
/// Eine Pause in der Drehung oder ein Richtungswechsel setzt den Zähler zurück: Ein kurzes Anstoßen
/// beim Tragen löst nichts aus, "weiterdrehen, bis der Balken voll ist" schon. Nach einem Wechsel
/// zählt die Crown erst wieder, wenn sie kurz stillstand (`settleTime`): Wer weiterdreht, löst nicht
/// gleich den nächsten Wechsel aus.
///
/// Bei Wassersperre ist die Schwelle höher. Das System entsperrt mit einer Drehung der Crown, und
/// diese Drehung soll noch nicht den Abschnitt wechseln.
public struct CrownRotationTracker: Equatable, Sendable {
    /// Crown-Einheiten bis zum Wechsel bei entsperrter Uhr.
    public static let unlockedThreshold = 8.0
    /// Crown-Einheiten bis zum Wechsel bei Wassersperre.
    public static let lockedThreshold = 14.0
    /// So lange darf die Drehung ruhen, bevor von vorn gezählt wird.
    public static let idleReset: TimeInterval = 1.5
    /// Nach einem Wechsel muss die Crown so lange ruhen, bevor die nächste Drehung zählt. Dreht der
    /// Athlet weiter, verlängert sich die Wartezeit.
    public static let settleTime: TimeInterval = 0.8
    /// Sprünge über diesen Wert sind das Zurücksetzen der Crown durch die Ansicht, keine Drehung.
    public static let resetJump = 25.0
    /// Wenn "nach oben drehen" bei dieser Uhr negative Werte liefert: hier auf `false` stellen.
    public static let upIsPositive = true

    /// Bisher am Stück gedrehte Strecke in Crown-Einheiten, mit Vorzeichen des Crown-Werts.
    public private(set) var travel = 0.0
    private var lastValue = 0.0
    private var lastMove: Date?
    /// Gerade ein Wechsel ausgelöst: Drehungen zählen nicht, bis die Crown ruht.
    private var settling = false

    /// Läuft nach einem Wechsel noch die Wartezeit?
    public var isSettling: Bool { settling }

    public init() {}

    public static func threshold(isLocked: Bool) -> Double {
        isLocked ? lockedThreshold : unlockedThreshold
    }

    /// Richtung der laufenden Drehung, `nil` wenn nichts gedreht wird.
    public var step: CrownStep? {
        guard travel != 0 else { return nil }
        return (travel > 0) == Self.upIsPositive ? .next : .previous
    }

    /// Fortschritt von 0 bis 1 für die Anzeige.
    public func progress(isLocked: Bool) -> Double {
        min(abs(travel) / Self.threshold(isLocked: isLocked), 1)
    }

    /// Neuer Wert der Crown. Weit genug in eine Richtung gedreht: die Richtung; der Zähler steht
    /// danach wieder auf 0.
    public mutating func moved(to value: Double, isLocked: Bool, at now: Date) -> CrownStep? {
        let delta = value - lastValue
        lastValue = value
        guard abs(delta) <= Self.resetJump else { return nil }
        resetIfIdle(at: now)
        guard delta != 0 else { return nil }
        if settling {
            // Die Crown dreht noch: Wartezeit verlängern.
            lastMove = now
            return nil
        }

        // Andere Richtung als bisher: von vorn zählen.
        if travel != 0, (travel > 0) != (delta > 0) { travel = 0 }
        lastMove = now
        travel += delta
        guard abs(travel) >= Self.threshold(isLocked: isLocked) else { return nil }
        let reached = step
        travel = 0
        lastMove = now
        settling = true
        return reached
    }

    /// Regelmäßig aufrufen: Lässt die Drehung nach, springt die Anzeige zurück auf 0.
    public mutating func resetIfIdle(at now: Date) {
        guard let lastMove else { return }
        let idle = now.timeIntervalSince(lastMove)
        if settling {
            if idle > Self.settleTime {
                settling = false
                self.lastMove = nil
            }
            return
        }
        guard idle > Self.idleReset else { return }
        travel = 0
        self.lastMove = nil
    }

    /// Die Ansicht hat die Crown auf 0 zurückgesetzt: Der Sprung dorthin zählt nicht als Drehung.
    public mutating func rebase() {
        lastValue = 0
    }
}
