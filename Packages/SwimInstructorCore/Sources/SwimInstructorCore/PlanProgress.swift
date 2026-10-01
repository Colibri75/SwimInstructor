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

/// Richtung eines Wechsels von Hand.
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

public extension PlanProgressState {
    /// Zählt jeden Satz (jede Wiederholung) einzeln: wächst mit jedem Schritt im Plan, am Ende `Int.max`.
    /// Zum Erkennen eines Wechsels, auch innerhalb eines Abschnitts.
    var stepKey: Int {
        switch self {
        case .noSets: return 0
        case let .inProgress(position): return position.setIndex * 10_000 + position.repetition
        case .completed: return Int.max
        }
    }
}

/// Ordnet die Strecke der Uhr den Abschnitten und Sätzen des Plans zu. Ein Satz ist eine Wiederholung
/// eines Abschnitts: "6 × 200 m" hat sechs Sätze.
///
/// Bewusst nur über die Meter, nicht über Pausen oder Apples Satz-Erkennung: Die Uhr zählt Bahnen
/// zuverlässig, Pausen am Beckenrand dagegen nicht immer. Wer einen Satz kürzt, sieht darum
/// einen Versatz; das ist einfacher zu verstehen als eine Zuordnung, die sich selbst korrigiert.
///
/// Mit `moves` kann der Athlet das von Hand korrigieren, in der Reihenfolge, in der er es getan hat:
/// "nächster" beendet den Satz, in dem er bei dieser Strecke gerade war, und der nächste Satz beginnt
/// dort (nach dem letzten Satz eines Abschnitts also der nächste Abschnitt); "vorheriger" beginnt den
/// Satz davor (oder den ersten von vorn) an dieser Stelle.
public enum PlanProgress {
    /// Wie `state(sets:swumMeters:moves:)`, nur mit Wechseln nach vorn: Jeder Eintrag ist die Strecke,
    /// bei der der Athlet "nächster Satz" ausgelöst hat.
    public static func state(sets: [PlanSet], swumMeters: Double, advancedAt: [Double] = []) -> PlanProgressState {
        state(
            sets: sets,
            swumMeters: swumMeters,
            moves: advancedAt.map { SectionMove(meters: $0, direction: .next) }
        )
    }

    public static func state(sets: [PlanSet], swumMeters: Double, moves: [SectionMove]) -> PlanProgressState {
        // Alle Sätze hintereinander: (Index des Abschnitts, Abschnitt, Nummer des Satzes ab 1).
        var units: [(setIndex: Int, set: PlanSet, repetition: Int)] = []
        for (index, set) in sets.enumerated() where set.repetitions > 0 && set.distanceMeters > 0 {
            for repetition in 1...set.repetitions {
                units.append((index, set, repetition))
            }
        }
        guard !units.isEmpty else { return .noSets }

        let swum = max(0, swumMeters.rounded(.down))
        let ordered = moves
            .enumerated()
            .map { (offset: $0.offset, meters: max(0, $0.element.meters.rounded(.down)), direction: $0.element.direction) }
            .sorted { ($0.meters, $0.offset) < ($1.meters, $1.offset) }

        // `cursor` zeigt in `units`; `units.count` heißt: Plan geschafft. `start` ist die Strecke,
        // bei der der Satz unter dem Cursor begann.
        var cursor = 0
        var start = 0.0

        /// Läuft von selbst bis zu den Metern `meters` weiter, solange Sätze regulär enden.
        func walk(to meters: Double) {
            while cursor < units.count {
                let end = start + Double(units[cursor].set.distanceMeters)
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
                guard cursor < units.count else { continue }
                cursor += 1
            case .previous:
                cursor = max(cursor - 1, 0)
            }
            start = meters
        }
        walk(to: swum)

        guard cursor < units.count else { return .completed(extraMeters: Int(swum - start)) }
        let unit = units[cursor]
        return .inProgress(PlanPosition(
            setIndex: unit.setIndex,
            set: unit.set,
            repetition: unit.repetition,
            metersIntoRepetition: Int(swum - start)
        ))
    }
}
