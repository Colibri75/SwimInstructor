import Foundation

// Brücke zwischen Plan v1 (nur Schwimmen) und Plan v2. Sie steht unter Sports/, weil nur hier feste Sportarten stehen
// dürfen: Ein Plan v1 ist immer Schwimmen, und Watch-Apps vor T5 spielen nur Schwimmeinheiten ab.

public extension DayPlanV2Response {
    /// Ein Tagesplan aus der Zeit vor Plan v2 als Plan v2 mit einer Schwimmeinheit, damit Verlauf und "Plan gegen Ist"
    /// ihn weiter zeigen. Ein Ruhetag hat keine Einheit.
    init(legacy response: PlanResponse) {
        let plan = response.plan
        let sessions: [DaySession] = plan.isRestDay ? [] : [
            DaySession(
                sport: .swim,
                sessionType: plan.sessionType,
                intensity: plan.intensity,
                focus: "",
                amount: Double(plan.totalDistanceMeters),
                unit: .meters,
                distanceMeters: Double(plan.totalDistanceMeters),
                durationMinutes: Double(plan.estimatedDurationMinutes),
                steps: plan.sets.map { set in
                    PlanStep(
                        name: set.name,
                        repetitions: set.repetitions,
                        measure: .distance,
                        distanceMeters: set.distanceMeters,
                        targetType: set.targetPaceSecondsPerHundredMeters == nil ? nil : .pacePerHundredMeters,
                        targetValue: set.targetPaceSecondsPerHundredMeters,
                        restSeconds: set.restSeconds,
                        instructions: set.instructions,
                        cue: set.cue,
                        equipment: set.equipment
                    )
                }
            )
        ]
        self.init(
            planVersion: 1,
            source: response.source,
            date: response.date,
            generatedAt: response.generatedAt,
            stale: response.stale,
            plan: DayPlanV2(rationale: plan.rationale, sessions: sessions, coachNotes: plan.coachNotes),
            adjustments: response.adjustments,
            fallbackReason: response.fallbackReason,
            wishes: response.wishes
        )
    }

    /// Der Tagesplan im Format v1 für Watch-Apps vor T5: die Schwimmeinheit des Tages. Ohne Schwimmen ist der Tag für sie
    /// ein Ruhetag; die Begründung sagt, was stattdessen ansteht. Neuere Watch-Apps lesen den Plan v2 daneben.
    func watchPlan(registry: SportRegistry = .standard) -> PlanResponse {
        PlanResponse(
            source: source,
            date: date,
            generatedAt: generatedAt,
            stale: stale,
            plan: plan.sessions.first { $0.sport == .swim }.map { Self.trainingPlan($0, rationale: plan.rationale, notes: plan.coachNotes) }
                ?? Self.restPlan(others: plan.sessions, notes: plan.coachNotes, registry: registry),
            adjustments: adjustments,
            fallbackReason: fallbackReason,
            wishes: wishes
        )
    }

    private static func trainingPlan(_ session: DaySession, rationale: String, notes: [String]) -> TrainingPlan {
        let speed = SwimModule().typicalSpeedMetersPerSecond
        let sets = session.steps.map { step -> PlanSet in
            // Schwimmschritte haben eine Strecke; ein Schritt nach Dauer wird mit dem typischen Tempo umgerechnet.
            let meters = step.distanceMeters ?? Int((Double(step.durationSeconds ?? 0) * speed / 25).rounded()) * 25
            return PlanSet(
                name: step.name,
                repetitions: step.repetitions,
                distanceMeters: meters,
                targetPaceSecondsPerHundredMeters: step.targetType == .pacePerHundredMeters ? step.targetValue : nil,
                restSeconds: step.restSeconds,
                instructions: step.instructions,
                equipment: step.equipment,
                cue: step.cue
            )
        }
        return TrainingPlan(
            sessionType: session.sessionType,
            intensity: session.intensity,
            rationale: rationale,
            totalDistanceMeters: Int(session.distanceMeters.rounded()),
            estimatedDurationMinutes: Int(session.durationMinutes.rounded()),
            sets: sets,
            coachNotes: notes
        )
    }

    private static func restPlan(others: [DaySession], notes: [String], registry: SportRegistry) -> TrainingPlan {
        let rationale = others.isEmpty
            ? "Heute ist Ruhetag."
            : "Heute kein Schwimmen. Auf dem iPhone: "
                + others.map { PlanV2Formatting.sessionTitle(sport: $0.sport, amount: $0.amount, unit: $0.unit, registry: registry) }.joined(separator: ", ")
                + "."
        return TrainingPlan(
            sessionType: .rest,
            intensity: .rest,
            rationale: rationale,
            totalDistanceMeters: 0,
            estimatedDurationMinutes: 0,
            sets: [],
            coachNotes: notes
        )
    }
}
