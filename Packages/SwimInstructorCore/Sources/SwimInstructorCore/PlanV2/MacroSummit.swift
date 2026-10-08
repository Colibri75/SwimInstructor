import Foundation

/// Der Weg zum Ziel als Berg (wie im Logo): Die Höhe ist das bis dahin geplante Training, Minuten aufsummiert, der
/// Gipfel ist das Ziel. Entlastungswochen steigen flacher, so entstehen die Serpentinen. Werte von 0 bis 1, die
/// Darstellung skaliert sie.
public struct MacroSummitProfile: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        /// 0 am Start, 1 am Ende der letzten Woche.
        public let x: Double
        /// 0 am Start, 1 am Gipfel.
        public let y: Double
    }

    /// Ein Abschnitt je Woche, für das Farbband der Phasen.
    public struct Segment: Equatable, Sendable {
        public let weekStart: String
        public let phase: MacroPhase
        public let fromX: Double
        public let toX: Double
    }

    /// Start und das Ende jeder Woche: eine Woche mehr Punkte als Wochen.
    public let points: [Point]
    public let segments: [Segment]
    /// Der Punkt, an dem die laufende Woche beginnt; `nil`, wenn sie nicht im Plan liegt.
    public let currentIndex: Int?

    public init(plan: MacroPlanV2, currentWeekStart: String) {
        let weeks = plan.weeks
        let count = max(weeks.count, 1)
        let total = weeks.reduce(0) { $0 + max($1.totalMinutes, 0) }
        var climbed = 0.0
        var points = [Point(x: 0, y: 0)]
        var segments: [Segment] = []
        for (index, week) in weeks.enumerated() {
            climbed += max(week.totalMinutes, 0)
            let fromX = Double(index) / Double(count)
            let toX = Double(index + 1) / Double(count)
            // Ohne Minuten (etwa nur Pausenwochen) steigt der Weg gleichmäßig.
            points.append(Point(x: toX, y: total > 0 ? climbed / total : toX))
            segments.append(Segment(weekStart: week.weekStart, phase: week.phase, fromX: fromX, toX: toX))
        }
        self.points = points
        self.segments = segments
        self.currentIndex = weeks.firstIndex { $0.weekStart == currentWeekStart }
    }
}
