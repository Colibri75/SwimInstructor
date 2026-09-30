import Foundation

/// Wo im Tagesplan man gerade steht, gemessen an den geschwommenen Metern.
public struct PlanPosition: Equatable, Sendable {
    public let setIndex: Int
    public let set: PlanSet
    /// 1-basiert: die Wiederholung, die gerade läuft.
    public let repetition: Int
    public let metersIntoRepetition: Int

    public var metersRemainingInRepetition: Int { set.distanceMeters - metersIntoRepetition }
}

public enum PlanProgressState: Equatable, Sendable {
    /// Der Plan hat keine Abschnitte mit Strecke (z. B. Ruhetag).
    case noSets
    case inProgress(PlanPosition)
    /// Alle Abschnitte geschafft; `extraMeters` ist, was darüber hinaus geschwommen wurde.
    case completed(extraMeters: Int)
}

/// Ordnet die Strecke der Uhr den Abschnitten des Plans zu.
///
/// Bewusst nur über die Meter, nicht über Pausen oder Apples Satz-Erkennung: Die Uhr zählt Bahnen
/// zuverlässig, Pausen am Beckenrand dagegen nicht immer. Wer einen Abschnitt kürzt, sieht darum
/// einen Versatz; das ist einfacher zu verstehen als eine Zuordnung, die sich selbst korrigiert.
public enum PlanProgress {
    public static func state(sets: [PlanSet], swumMeters: Double) -> PlanProgressState {
        let countable = sets.enumerated().filter { $0.element.repetitions > 0 && $0.element.distanceMeters > 0 }
        guard !countable.isEmpty else { return .noSets }

        var remaining = max(0, Int(swumMeters.rounded(.down)))
        for (index, set) in countable {
            if remaining < set.totalMeters {
                return .inProgress(PlanPosition(
                    setIndex: index,
                    set: set,
                    repetition: remaining / set.distanceMeters + 1,
                    metersIntoRepetition: remaining % set.distanceMeters
                ))
            }
            remaining -= set.totalMeters
        }
        return .completed(extraMeters: remaining)
    }
}
