import Foundation

/// Regeln für Wassersperre und Digital Crown während einer Beckeneinheit.
///
/// Die Uhr sperrt den Bildschirm gegen Wassertropfen; Drehen der Crown entsperrt ihn. Dann gilt:
/// - Eine weitere Drehung der Crown schaltet den nächsten Abschnitt des Plans weiter und
///   sperrt den Bildschirm danach wieder.
/// - Die Drehung, die entsperrt hat, zählt nicht dazu (Beruhigungszeit nach dem Entsperren).
/// - Passiert nach dem Entsperren nichts, sperrt die Uhr nach einer Weile von selbst wieder.
///
/// Reine Logik ohne WatchKit, damit sie testbar ist. Der Aufrufer fragt regelmäßig den Zustand der
/// Sperre ab und führt die zurückgegebene Aktion aus.
public struct WaterLockControl: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Wassersperre wieder einschalten.
        case lock
    }

    /// So weit muss die Crown nach oben gedreht werden (Rastungen), bevor der nächste Abschnitt startet.
    public static let crownThreshold = 2.0
    /// So lange nach dem Entsperren wird die Crown ignoriert.
    public static let settleTime: TimeInterval = 1.0
    /// So lange darf der Bildschirm ohne Eingabe entsperrt bleiben, bevor die Uhr wieder sperrt.
    public static let idleRelockTime: TimeInterval = 20

    private var unlockedAt: Date?
    private var lastInput: Date?

    public init() {}

    /// Mit dem aktuellen Zustand aufrufen, etwa zweimal pro Sekunde, solange die Einheit läuft.
    /// - Parameters:
    ///   - isRunning: Die Einheit läuft (nicht pausiert, nicht beendet).
    ///   - isLocked: Die Wassersperre ist gerade an.
    public mutating func update(isRunning: Bool, isLocked: Bool, now: Date) -> Action? {
        guard isRunning, !isLocked else {
            unlockedAt = nil
            lastInput = nil
            return nil
        }
        guard let since = unlockedAt else {
            unlockedAt = now
            return nil
        }
        return now.timeIntervalSince(lastInput ?? since) >= Self.idleRelockTime ? .lock : nil
    }

    /// Darf die Crown jetzt einen Abschnitt weiterschalten? Nur wenn entsperrt und die Beruhigungszeit um ist.
    public func acceptsCrown(now: Date) -> Bool {
        guard let unlockedAt else { return false }
        return now.timeIntervalSince(unlockedAt) >= Self.settleTime
    }

    /// Eine Eingabe nach dem Entsperren (Crown, Tippen auf Pause) verlängert die Zeit bis zur automatischen Sperre.
    public mutating func noteInput(now: Date) {
        if unlockedAt != nil { lastInput = now }
    }

    /// Fortschritt der Crown-Drehung von 0 bis 1, für die Anzeige auf der Uhr.
    public static func progress(crownValue: Double) -> Double {
        min(abs(crownValue) / crownThreshold, 1)
    }

    /// `crownValue` ist der Wert der Crown seit dem letzten Zurücksetzen. Die Richtung zählt nicht:
    /// Welches Vorzeichen "nach oben" ist, ließ sich nicht verlässlich sagen, und beim ersten Versuch
    /// blieb die Drehung nach oben wirkungslos. Entsperrt ist die Uhr ohnehin nur nach einer
    /// bewussten Crown-Drehung, und die Beruhigungszeit fängt das Nachlaufen der entsperrenden
    /// Drehung ab.
    public static func isAdvance(crownValue: Double) -> Bool {
        abs(crownValue) >= crownThreshold
    }
}
