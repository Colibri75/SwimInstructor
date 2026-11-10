import Foundation
import WatchKit

/// Haptik, die man auch im Wasser und unterwegs spürt. Die einzelnen Muster der Watch sind kurz und beim Schwimmen
/// kaum zu merken; wichtige Wechsel spielen deshalb das kräftigste Muster (`.notification`) mehrmals hintereinander.
/// So bleibt auch unterscheidbar, was passiert: dreimal = es geht los, zweimal = Pause.
enum Haptics {
    /// Abstand zwischen zwei Impulsen: lang genug, dass sie nicht zu einem verschwimmen.
    static let interval: TimeInterval = 0.5

    /// Ein neuer Abschnitt oder eine neue Wiederholung beginnt (Satzwechsel), auch der Start nach dem Countdown.
    static func workStarts() {
        burst(.notification, times: 3)
    }

    /// Eine Pause beginnt.
    static func restStarts() {
        burst(.notification, times: 2)
    }

    /// Der Plan ist geschafft.
    static func completed() {
        WKInterfaceDevice.current().play(.success)
        burst(.notification, times: 2, delay: 0.8)
    }

    /// Die letzten Sekunden vor einem Wechsel (Countdown, Pause, Wiederholung nach Zeit): ein deutlicher Impuls je Sekunde.
    static func secondTick() {
        WKInterfaceDevice.current().play(.directionUp)
    }

    /// Der Athlet hat selbst gewechselt (Crown, Taste): Richtung spürbar, ein kräftiger Impuls zur Bestätigung.
    static func manualChange(forward: Bool) {
        WKInterfaceDevice.current().play(forward ? .directionUp : .directionDown)
        burst(.notification, times: 1, delay: interval)
    }

    /// Spielt `type` mehrmals im Abstand `interval`, auf dem Hauptthread.
    static func burst(_ type: WKHapticType, times: Int, delay: TimeInterval = 0) {
        for index in 0..<max(times, 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(index) * interval) {
                WKInterfaceDevice.current().play(type)
            }
        }
    }
}
