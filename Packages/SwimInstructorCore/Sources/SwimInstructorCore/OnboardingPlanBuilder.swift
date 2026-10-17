import Foundation

/// Der Ladebildschirm am Ende der Einrichtung: Health lesen, Gesamtplan, die nächsten 14 Tage und der Plan für heute,
/// nacheinander. Erst wenn alles steht, geht es in die App; scheitert ein Schritt, bleibt der Bildschirm mit dem Fehler
/// und "Nochmal versuchen" stehen, statt einen leeren Plan zu zeigen. Absichtlich ohne SwiftUI, damit der Ablauf per
/// Unit-Test prüfbar ist; was ein Schritt tut, steckt die App hinein.
@MainActor
public final class OnboardingPlanBuilder: ObservableObject {
    public enum Step: Int, CaseIterable, Sendable {
        case health, macro, days, today
    }

    /// Ein Schritt: erledigt ihn (oder merkt, dass er schon erledigt ist) und liefert `nil`, sonst den Fehler als Text.
    public typealias Action = @MainActor () async -> String?

    /// Der Schritt, der gerade läuft oder zuletzt gescheitert ist; `nil` vor dem Start.
    @Published public private(set) var step: Step?
    @Published public private(set) var isRunning = false
    /// Warum der letzte Durchlauf stehen blieb.
    @Published public private(set) var failure: String?
    @Published public private(set) var isFinished = false

    private let actions: [Step: Action]

    public init(health: @escaping Action, macro: @escaping Action, days: @escaping Action, today: @escaping Action) {
        actions = [.health: health, .macro: macro, .days: days, .today: today]
    }

    /// Ob ein Schritt schon geschafft ist (für die Liste auf dem Ladebildschirm).
    public func isDone(_ candidate: Step) -> Bool {
        if isFinished { return true }
        guard let step else { return false }
        return candidate.rawValue < step.rawValue
    }

    /// Alle Schritte von vorn. Jeder Schritt überspringt, was schon da ist; ein zweiter Versuch kostet also nur den
    /// gescheiterten Schritt und die danach.
    public func run() async {
        guard !isRunning, !isFinished else { return }
        isRunning = true
        failure = nil
        defer { isRunning = false }
        for candidate in Step.allCases {
            step = candidate
            if let problem = await actions[candidate]?() {
                failure = problem
                return
            }
        }
        isFinished = true
    }
}
