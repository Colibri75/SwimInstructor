import Foundation
@testable import SwimInstructorCore

/// Daten für die Tests zum Gesamtplan. "Heute" ist Mittwoch, der 30.09.2026 (TestFixtures.now).
enum MacroFixtures {
    /// Das Standardziel (3,8 km in 60 Minuten bis 04.07.2027), so wie es der Lader kennzeichnet.
    static let goalKey = AthleteGoal.default.key(calendar: TestFixtures.utc)

    static func week(_ start: String, meters: Int = 3500, sessions: Int = 3, deload: Bool = false, focus: String = "Ausdauer", phase: MacroPhase = .base) -> MacroWeek {
        MacroWeek(weekStart: start, targetMeters: meters, sessions: sessions, deload: deload, focus: focus, phase: phase)
    }

    /// Drei Wochen ab der laufenden (Montag 28.09.2026), mit Entlastung in der dritten.
    static func plan(goalKey: String = MacroFixtures.goalKey, weeks: [MacroWeek]? = nil) -> MacroPlan {
        MacroPlan(
            goalKey: goalKey,
            goalDay: "2027-07-04",
            generatedAt: TestFixtures.now,
            rationale: "40 Wochen bis zum Ziel.",
            adjustments: [],
            weeks: weeks ?? [
                week("2026-09-28", meters: 3500),
                week("2026-10-05", meters: 3800),
                week("2026-10-12", meters: 3000, deload: true, focus: "Entlastung")
            ]
        )
    }

    static let responseJSON = """
    {
      "goal_day": "2027-07-04",
      "generated_at": "2026-09-30T10:00:00.000Z",
      "adjustments": ["Woche ab 28.09.: Umfang von 6000 m auf 3900 m begrenzt (Grenze für die erste Woche)"],
      "plan": {
        "rationale": "40 Wochen bis zum Ziel.",
        "weeks": [
          { "week_start": "2026-09-28", "target_meters": 3500, "sessions": 3, "deload": false, "focus": "Ausdauer und Technik", "phase": "base" },
          { "week_start": "2026-10-05", "target_meters": 3800, "sessions": 3, "deload": false, "focus": "Ausdauer", "phase": "base" },
          { "week_start": "2026-10-12", "target_meters": 3000, "sessions": 3, "deload": true, "focus": "Entlastung", "phase": "base" },
          { "week_start": "2027-06-14", "target_meters": 3500, "sessions": 3, "deload": false, "focus": "Zuspitzen", "phase": "taper" },
          { "week_start": "2027-06-28", "target_meters": 3600, "sessions": 2, "deload": false, "focus": "Zielwoche", "phase": "goal_week" }
        ]
      }
    }
    """
}
