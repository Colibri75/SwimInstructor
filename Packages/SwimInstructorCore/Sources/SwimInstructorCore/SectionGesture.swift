import Foundation

/// Erkennt "nächster Abschnitt" an der Tastenkombination, die auch bei Wassersperre funktioniert.
///
/// Apps bekommen die Seitentaste einer Apple Watch (Series, SE) nicht zu sehen. Eine Kombination meldet
/// das System aber doch: Digital Crown und Seitentaste gleichzeitig drücken pausiert die Einheit, ein
/// zweites Mal setzt sie fort, auch bei Wassersperre. Die App sieht davon nur "pausiert" und "läuft".
/// Wer **zweimal kurz hintereinander** drückt (Pause und gleich wieder Weiter), löst so den nächsten
/// Abschnitt aus. Eine echte Pause am Beckenrand dauert länger und bleibt eine Pause.
public struct SectionGesture: Equatable, Sendable {
    /// So kurz muss die Pause höchstens sein, damit sie als Geste zählt.
    public static let maxPause: TimeInterval = 3

    private var pausedAt: Date?

    public init() {}

    /// Die Einheit wurde pausiert. `byButtonOnScreen`: Der Athlet hat auf dem Bildschirm "Pause" getippt,
    /// das ist nie eine Geste.
    public mutating func didPause(at date: Date, byButtonOnScreen: Bool = false) {
        pausedAt = byButtonOnScreen ? nil : date
    }

    /// Die Einheit läuft wieder. `true`, wenn die Pause kurz genug war und von der Tastenkombination kam.
    public mutating func didResume(at date: Date) -> Bool {
        defer { pausedAt = nil }
        guard let pausedAt else { return false }
        let pause = date.timeIntervalSince(pausedAt)
        return pause >= 0 && pause <= Self.maxPause
    }

    /// Einheit beendet oder neu begonnen.
    public mutating func reset() {
        pausedAt = nil
    }
}
