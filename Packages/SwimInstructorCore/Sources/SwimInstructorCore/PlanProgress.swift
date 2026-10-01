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

public extension PlanProgressState {
    /// Nummer des laufenden Abschnitts (ab 0), `setCount` wenn der Plan geschafft ist, 0 ohne Abschnitte.
    func sectionIndex(setCount: Int) -> Int {
        switch self {
        case .noSets: return 0
        case let .inProgress(position): return position.setIndex
        case .completed: return setCount
        }
    }
}

/// Richtung eines Abschnittswechsels von Hand.
public enum SectionDirection: Equatable, Sendable {
    case next
    case previous
}

/// Ein Wechsel von Hand: bei welcher Strecke (Meter) und in welche Richtung.
public struct SectionMove: Equatable, Sendable {
    public let meters: Double
    public let direction: SectionDirection

    public init(meters: Double, direction: SectionDirection) {
        self.meters = meters
        self.direction = direction
    }
}

/// Ordnet die Strecke der Uhr den Abschnitten des Plans zu.
///
/// Bewusst nur über die Meter, nicht über Pausen oder Apples Satz-Erkennung: Die Uhr zählt Bahnen
/// zuverlässig, Pausen am Beckenrand dagegen nicht immer. Wer einen Abschnitt kürzt, sieht darum
/// einen Versatz; das ist einfacher zu verstehen als eine Zuordnung, die sich selbst korrigiert.
///
/// Mit `moves` kann der Athlet das von Hand korrigieren, in der Reihenfolge, in der er es getan hat:
/// "nächster" beendet den Abschnitt, in dem er bei dieser Strecke gerade war, und der nächste beginnt
/// dort; "vorheriger" beginnt den Abschnitt davor (oder den ersten von vorn) an dieser Stelle.
public enum PlanProgress {
    /// Wie `state(sets:swumMeters:moves:)`, nur mit Wechseln nach vorn: Jeder Eintrag ist die Strecke,
    /// bei der der Athlet "nächster Abschnitt" ausgelöst hat.
    public static func state(sets: [PlanSet], swumMeters: Double, advancedAt: [Double] = []) -> PlanProgressState {
        state(
            sets: sets,
            swumMeters: swumMeters,
            moves: advancedAt.map { SectionMove(meters: $0, direction: .next) }
        )
    }

    public static func state(sets: [PlanSet], swumMeters: Double, moves: [SectionMove]) -> PlanProgressState {
        let countable = sets.enumerated().filter { $0.element.repetitions > 0 && $0.element.distanceMeters > 0 }
        guard !countable.isEmpty else { return .noSets }

        let swum = max(0, swumMeters.rounded(.down))
        let ordered = moves
            .enumerated()
            .map { (offset: $0.offset, meters: max(0, $0.element.meters.rounded(.down)), direction: $0.element.direction) }
            .sorted { ($0.meters, $0.offset) < ($1.meters, $1.offset) }

        // `cursor` zeigt in `countable`; `countable.count` heißt: Plan geschafft. `start` ist die
        // Strecke, bei der der Abschnitt unter dem Cursor begann.
        var cursor = 0
        var start = 0.0

        /// Läuft von selbst bis zu den Metern `meters` weiter, solange Abschnitte regulär enden.
        func walk(to meters: Double) {
            while cursor < countable.count {
                let end = start + Double(countable[cursor].element.totalMeters)
                guard meters >= end else { return }
                start = end
                cursor += 1
            }
        }

        for move in ordered where move.meters <= swum {
            let meters = move.meters
            walk(to: meters)
            switch move.direction {
            case .next:
                // Nach dem Ende des Plans gibt es nichts mehr weiterzuschalten.
                guard cursor < countable.count else { continue }
                cursor += 1
            case .previous:
                cursor = max(cursor - 1, 0)
            }
            start = meters
        }
        walk(to: swum)

        guard cursor < countable.count else { return .completed(extraMeters: Int(swum - start)) }
        let (index, set) = countable[cursor]
        let into = Int(swum - start)
        return .inProgress(PlanPosition(
            setIndex: index,
            set: set,
            repetition: into / set.distanceMeters + 1,
            metersIntoRepetition: into % set.distanceMeters
        ))
    }
}
