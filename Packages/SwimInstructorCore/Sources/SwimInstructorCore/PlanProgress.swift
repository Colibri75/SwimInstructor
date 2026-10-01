import Foundation

/// Wo im Tagesplan man gerade steht, gemessen an den geschwommenen Metern.
public struct PlanPosition: Equatable, Sendable {
    public let setIndex: Int
    public let set: PlanSet
    /// 1-basiert: die Wiederholung, die gerade läuft.
    public let repetition: Int
    public let metersIntoRepetition: Int

    public var metersRemainingInRepetition: Int { self.set.distanceMeters - metersIntoRepetition }
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
///
/// Mit `advancedAt` kann der Athlet das von Hand korrigieren: Jeder Eintrag ist die Strecke, bei der er
/// "nächster Abschnitt" ausgelöst hat. Der Abschnitt, in dem das passierte, gilt dort als beendet und
/// der nächste beginnt an dieser Stelle.
public enum PlanProgress {
    public static func state(sets: [PlanSet], swumMeters: Double, advancedAt: [Double] = []) -> PlanProgressState {
        let countable = sets.enumerated().filter { $0.element.repetitions > 0 && $0.element.distanceMeters > 0 }
        guard !countable.isEmpty else { return .noSets }

        let swum = max(0, swumMeters.rounded(.down))
        let advances = advancedAt.map { max(0, $0.rounded(.down)) }.sorted()
        var nextAdvance = 0
        var start = 0.0

        for (index, set) in countable {
            let autoEnd = start + Double(set.totalMeters)
            var end = autoEnd
            // Ein Druck, der vor dem automatischen Ende dieses Abschnitts kam, beendet ihn dort.
            // Spätere Drücke gehören zu späteren Abschnitten.
            if nextAdvance < advances.count, advances[nextAdvance] < autoEnd {
                end = max(advances[nextAdvance], start)
                nextAdvance += 1
            }
            if swum < end {
                let into = Int(swum - start)
                return .inProgress(PlanPosition(
                    setIndex: index,
                    set: set,
                    repetition: into / set.distanceMeters + 1,
                    metersIntoRepetition: into % set.distanceMeters
                ))
            }
            start = end
        }
        return .completed(extraMeters: Int(swum - start))
    }
}
