import Foundation

/// Regel für die Wassersperre während einer Beckeneinheit: Sie ist an, solange die Einheit läuft. Wer
/// sie mit der Digital Crown aufhebt (etwa um zu pausieren), bekommt sie nach einer Weile ohne Eingabe
/// von selbst zurück.
///
/// Reine Logik ohne WatchKit, damit sie testbar ist. Der Aufrufer fragt regelmäßig den Zustand der
/// Sperre ab und führt die zurückgegebene Aktion aus.
public struct WaterLockControl: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Wassersperre wieder einschalten.
        case lock
    }

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

    /// Eine Eingabe nach dem Entsperren (Crown, Tippen) verlängert die Zeit bis zur automatischen Sperre.
    public mutating func noteInput(now: Date) {
        if unlockedAt != nil { lastInput = now }
    }
}
