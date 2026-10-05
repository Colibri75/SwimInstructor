import Foundation

/// Eine Wiederholung eines Schritts, so wie die Uhr sie abarbeitet: "3. von 6 × 3 min".
public struct ProgressUnit: Equatable, Sendable {
    /// Woran eine Wiederholung endet.
    public enum Target: Equatable, Sendable {
        case meters(Double)
        case seconds(TimeInterval)
    }

    /// Stelle in der Einheit, ab 0.
    public let index: Int
    /// Index des Schritts in der Einheit.
    public let stepIndex: Int
    public let step: PlanStep
    /// 1-basiert.
    public let repetition: Int
    /// `nil`: Die Wiederholung endet nur von Hand (Schritt ohne Strecke und Dauer, etwa Kraftübungen).
    public let target: Target?
    /// Pause nach dieser Wiederholung in Sekunden; 0 nach der letzten Wiederholung der Einheit.
    public let restSeconds: Int

    public init(index: Int, stepIndex: Int, step: PlanStep, repetition: Int, target: Target?, restSeconds: Int) {
        self.index = index
        self.stepIndex = stepIndex
        self.step = step
        self.repetition = repetition
        self.target = target
        self.restSeconds = restSeconds
    }

    /// Alle Wiederholungen der Schritte hintereinander. Schritte ohne Wiederholung fallen weg, ebenso Schritte nach Strecke
    /// oder Zeit ohne Angabe. Nach jeder Wiederholung kommt die Pause des Schritts, nach der
    /// letzten der Einheit keine mehr.
    public static func units(for steps: [PlanStep]) -> [ProgressUnit] {
        var units: [ProgressUnit] = []
        for (stepIndex, step) in steps.enumerated() where step.repetitions > 0 {
            let target: Target?
            switch resolve(step) {
            case .skip: continue
            case .manual: target = nil
            case let .target(value): target = value
            }
            for repetition in 1...step.repetitions {
                units.append(ProgressUnit(
                    index: units.count,
                    stepIndex: stepIndex,
                    step: step,
                    repetition: repetition,
                    target: target,
                    restSeconds: max(step.restSeconds, 0)
                ))
            }
        }
        if let last = units.last {
            units[units.count - 1] = ProgressUnit(
                index: last.index, stepIndex: last.stepIndex, step: last.step, repetition: last.repetition, target: last.target, restSeconds: 0
            )
        }
        return units
    }

    private enum Resolution {
        case skip
        case manual
        case target(Target)
    }

    /// Ein Schritt nach Strecke oder Zeit ohne Angabe fällt weg; ein Schritt ohne Maß (oder mit einem unbekannten) endet
    /// bei seiner Strecke oder Zeit, ohne beides nur von Hand.
    private static func resolve(_ step: PlanStep) -> Resolution {
        let meters = step.distanceMeters.flatMap { $0 > 0 ? Double($0) : nil }
        let seconds = step.durationSeconds.flatMap { $0 > 0 ? TimeInterval($0) : nil }
        switch step.measure {
        case .distance?:
            return meters.map { Resolution.target(.meters($0)) } ?? .skip
        case .duration?:
            return seconds.map { Resolution.target(.seconds($0)) } ?? .skip
        case .repetitions?, nil:
            if let meters { return .target(.meters(meters)) }
            if let seconds { return .target(.seconds(seconds)) }
            return .manual
        }
    }
}

/// Eine Wiederholung, die zu Ende ist: wann sie lief (Laufzeit ohne Pausen der Aufzeichnung) und wie weit sie ging.
/// Grundlage für Rundenmarken und die Auswertung von Leistungstests.
public struct RecordedSegment: Equatable, Sendable {
    public let unit: ProgressUnit
    public let startElapsed: TimeInterval
    public let endElapsed: TimeInterval
    public let meters: Double
    /// Ob die Wiederholung ihr Ziel (Strecke, Zeit) erreicht hat. Eine von Hand beendete Wiederholung nach Strecke oder
    /// Zeit hat es nicht; eine ohne Ziel gilt mit dem Wechsel von Hand als erreicht.
    public let reachedTarget: Bool

    public init(unit: ProgressUnit, startElapsed: TimeInterval, endElapsed: TimeInterval, meters: Double, reachedTarget: Bool) {
        self.unit = unit
        self.startElapsed = startElapsed
        self.endElapsed = endElapsed
        self.meters = meters
        self.reachedTarget = reachedTarget
    }

    public var duration: TimeInterval { endElapsed - startElapsed }
}

/// Was beim Weiterrechnen passiert ist, für Haptik, Ansagen und Rundenmarken. In der Reihenfolge, in der es geschah.
public enum ProgressEvent: Equatable, Sendable {
    /// Eine Wiederholung beginnt (auch nach einer Pause oder einem Schritt zurück).
    case workStarted(ProgressUnit)
    /// Eine Wiederholung ist zu Ende.
    case workEnded(RecordedSegment)
    /// Die Pause nach dieser Wiederholung beginnt.
    case restStarted(ProgressUnit)
    /// Die letzte Wiederholung ist zu Ende.
    case completed
}

/// Der Stand für die Anzeige.
public enum ProgressStatus: Equatable, Sendable {
    /// Die Einheit hat keine Schritte (Ruhetag oder freies Training).
    case noUnits
    /// `done` und `remaining` in Metern bzw. Sekunden je nach Ziel; ohne Ziel zählt `done` die Sekunden, `remaining` ist `nil`.
    case work(ProgressUnit, done: Double, remaining: Double?)
    /// Pause nach `after`; `next` ist die Wiederholung danach.
    case rest(after: ProgressUnit, next: ProgressUnit?, remainingSeconds: Int)
    case completed
}

/// Der Stand in einer Einheit mit Schritten nach Strecke, Zeit oder von Hand, für jede Sportart.
///
/// Die Engine läuft mit: Sie bekommt laufend Strecke und Laufzeit (ohne Pausen der Aufzeichnung) und merkt sich, wo jede
/// Wiederholung begann.
///
/// - Eine Wiederholung nach Strecke endet bei ihrer Strecke, eine nach Zeit genau nach ihrer Dauer. Ohne Pause danach beginnt
///   die nächste genau dort; was über die Strecke hinaus gezählt wurde, gehört schon zu ihr.
/// - Die Pause zählt als Zeit. Was in der Pause an Strecke dazukommt (Auslaufen, eine Bahn vor dem Ende der Pause), zählt
///   nicht für die nächste Wiederholung. Im Becken meldet die Uhr die Strecke bahnweise, eine Bahn nach der Pause zählt also.
/// - Von Hand: "weiter" beendet die Wiederholung (dann folgt ihre Pause) oder die Pause; "zurück" beginnt die vorige
///   Wiederholung neu, in einer Pause die gerade beendete.
public struct SessionProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case work
        /// Pause nach der laufenden Wiederholung bis zur Laufzeit `endsAt`.
        case rest(endsAt: TimeInterval)
    }

    public let units: [ProgressUnit]
    /// Anzahl der Schritte im Plan, für "2/5".
    public let stepCount: Int
    /// Die laufende Wiederholung; `units.count`, wenn die Einheit geschafft ist.
    public private(set) var index = 0
    public private(set) var phase = Phase.work
    /// Die beendeten Wiederholungen in der Reihenfolge der Einheit; ein Schritt zurück verwirft die betroffenen.
    public private(set) var segments: [RecordedSegment] = []

    private var anchorMeters = 0.0
    private var anchorElapsed: TimeInterval = 0
    private var lastMeters = 0.0
    private var lastElapsed: TimeInterval = 0
    private var finished = false

    public init(steps: [PlanStep]) {
        units = ProgressUnit.units(for: steps)
        stepCount = steps.count
    }

    public var isCompleted: Bool { !units.isEmpty && index >= units.count }

    /// Die laufende Wiederholung (auch in der Pause danach); `nil` ohne Schritte oder am Ende.
    public var current: ProgressUnit? { index < units.count ? units[index] : nil }

    // MARK: - Mitlaufen

    /// Neuer Stand von Strecke und Laufzeit. Eine kleinere Strecke oder Zeit als zuletzt gilt als Messfehler und zählt als
    /// der letzte Stand.
    @discardableResult
    public mutating func update(meters: Double, elapsed: TimeInterval) -> [ProgressEvent] {
        guard !finished else { return [] }
        let before = lastMeters
        let meters = meters.isFinite ? max(meters, lastMeters) : lastMeters
        let elapsed = elapsed.isFinite ? max(elapsed, lastElapsed) : lastElapsed
        lastMeters = meters
        lastElapsed = elapsed

        var events: [ProgressEvent] = []
        while index < units.count {
            switch phase {
            case .work:
                switch units[index].target {
                case nil:
                    return events
                case let .meters(distance)?:
                    guard meters - anchorMeters >= distance else { return events }
                    let end = anchorMeters + distance
                    events += endWork(at: elapsed, metersAtEnd: end, reached: true)
                case let .seconds(seconds)?:
                    let end = anchorElapsed + seconds
                    guard elapsed >= end else { return events }
                    events += endWork(at: end, metersAtEnd: metersAt(end, elapsed: elapsed, meters: meters, before: before), reached: true)
                }
            case let .rest(endsAt):
                guard elapsed >= endsAt else { return events }
                // Was diese Meldung an Strecke dazubringt, gehört schon zur nächsten Wiederholung.
                events += startNext(meters: metersAt(endsAt, elapsed: elapsed, meters: meters, before: before), elapsed: endsAt)
            }
        }
        return events
    }

    /// Ob ein Wechsel von Hand in diese Richtung geht.
    public func canMove(_ direction: SectionDirection) -> Bool {
        guard !units.isEmpty, !finished else { return false }
        switch direction {
        case .next:
            return index < units.count
        case .previous:
            if index >= units.count { return true }
            if case .rest = phase { return true }
            return index > 0
        }
    }

    /// Wechsel von Hand beim aktuellen Stand. Rechnet vorher mit `meters` und `elapsed` weiter; leer, wenn der Wechsel
    /// nicht geht und dabei nichts passiert ist.
    @discardableResult
    public mutating func move(_ direction: SectionDirection, meters: Double, elapsed: TimeInterval) -> [ProgressEvent] {
        var events = update(meters: meters, elapsed: elapsed)
        guard canMove(direction) else { return events }
        switch (direction, phase) {
        case (.next, .work):
            events += endWork(at: lastElapsed, metersAtEnd: lastMeters, reached: units[index].target == nil)
        case (.next, .rest):
            events += startNext(meters: lastMeters, elapsed: lastElapsed)
        case (.previous, .rest):
            events += restart(index)
        case (.previous, .work):
            events += restart(index >= units.count ? units.count - 1 : index - 1)
        }
        return events
    }

    /// Die Aufzeichnung endet: Eine laufende Wiederholung kommt als nicht erreicht zu den Abschnitten. Danach ändert sich
    /// nichts mehr.
    public mutating func finish(meters: Double, elapsed: TimeInterval) {
        update(meters: meters, elapsed: elapsed)
        guard !finished else { return }
        finished = true
        guard index < units.count, phase == .work else { return }
        segments.append(RecordedSegment(
            unit: units[index],
            startElapsed: anchorElapsed,
            endElapsed: lastElapsed,
            meters: max(lastMeters - anchorMeters, 0),
            reachedTarget: false
        ))
    }

    // MARK: - Anzeige

    /// Wie weit die laufende Wiederholung oder Pause ist. `meters` und `elapsed` wie bei `update`; der Stand selbst ändert
    /// sich dadurch nicht.
    public func status(meters: Double, elapsed: TimeInterval) -> ProgressStatus {
        guard !units.isEmpty else { return .noUnits }
        guard index < units.count else { return .completed }
        let unit = units[index]
        switch phase {
        case let .rest(endsAt):
            let remaining = max(Int((endsAt - max(elapsed, lastElapsed)).rounded(.up)), 0)
            return .rest(after: unit, next: index + 1 < units.count ? units[index + 1] : nil, remainingSeconds: remaining)
        case .work:
            let seconds = max(max(elapsed, lastElapsed) - anchorElapsed, 0)
            switch unit.target {
            case nil:
                return .work(unit, done: seconds, remaining: nil)
            case let .meters(distance)?:
                let done = min(max(max(meters, lastMeters) - anchorMeters, 0), distance)
                return .work(unit, done: done, remaining: distance - done)
            case let .seconds(duration)?:
                let done = min(seconds, duration)
                return .work(unit, done: done, remaining: duration - done)
            }
        }
    }

    // MARK: - Intern

    /// Liegt die Grenze vor dieser Meldung, gilt die Strecke der vorigen Meldung (aber nie weniger als am Anfang der
    /// laufenden Wiederholung).
    private func metersAt(_ boundary: TimeInterval, elapsed: TimeInterval, meters: Double, before: Double) -> Double {
        boundary >= elapsed ? meters : max(before, anchorMeters)
    }

    private mutating func endWork(at end: TimeInterval, metersAtEnd: Double, reached: Bool) -> [ProgressEvent] {
        let unit = units[index]
        let segment = RecordedSegment(
            unit: unit,
            startElapsed: anchorElapsed,
            endElapsed: end,
            meters: max(metersAtEnd - anchorMeters, 0),
            reachedTarget: reached
        )
        segments.append(segment)
        guard unit.restSeconds > 0 else {
            return [.workEnded(segment)] + startNext(meters: metersAtEnd, elapsed: end)
        }
        phase = .rest(endsAt: end + TimeInterval(unit.restSeconds))
        return [.workEnded(segment), .restStarted(unit)]
    }

    private mutating func startNext(meters: Double, elapsed: TimeInterval) -> [ProgressEvent] {
        index += 1
        phase = .work
        anchorMeters = meters
        anchorElapsed = elapsed
        guard index < units.count else { return [.completed] }
        return [.workStarted(units[index])]
    }

    private mutating func restart(_ newIndex: Int) -> [ProgressEvent] {
        segments.removeAll { $0.unit.index >= newIndex }
        index = newIndex
        phase = .work
        anchorMeters = lastMeters
        anchorElapsed = lastElapsed
        return [.workStarted(units[newIndex])]
    }
}
