import Foundation
@testable import SwimInstructorCore

/// Gemeinsame Daten für die Wochenplan-Tests. "Heute" ist Mittwoch, der 30.09.2026 (TestFixtures.now).
enum WeekFixtures {
    static let weekStart = "2026-09-28"
    static let today = "2026-09-30"

    static func content(
        _ type: SessionType = .endurance,
        _ intensity: PlanIntensity = .moderate,
        meters: Int = 1500,
        minutes: Int = 40,
        focus: String = "Ausdauer"
    ) -> WeekDayContent {
        WeekDayContent(sessionType: type, intensity: intensity, targetDistanceMeters: meters, estimatedDurationMinutes: minutes, focus: focus)
    }

    static func day(_ date: String, _ content: WeekDayContent = content()) -> WeekDayPlan {
        WeekDayPlan(date: date, content: content)
    }

    static func restDay(_ date: String) -> WeekDayPlan {
        WeekDayPlan(date: date, content: .rest())
    }

    /// Mi 1500 Ausdauer, Do Ruhe, Fr 1000 Technik, Sa 2000 Schwelle, So Ruhe (ab Mittwoch geplant).
    static func plan(days: [WeekDayPlan]? = nil) -> WeekPlan {
        WeekPlan(
            weekStart: weekStart,
            generatedAt: TestFixtures.now,
            rationale: "Test",
            adjustments: [],
            wishes: nil,
            days: days ?? [
                day("2026-09-30"),
                restDay("2026-10-01"),
                day("2026-10-02", content(.technique, .easy, meters: 1000, minutes: 35, focus: "Technik")),
                day("2026-10-03", content(.threshold, .hard, meters: 2000, minutes: 55, focus: "Schwelle")),
                restDay("2026-10-04")
            ]
        )
    }

    static let responseJSON = """
    {
      "week_start": "2026-09-28",
      "generated_at": "2026-09-30T10:00:00.000Z",
      "adjustments": ["Samstag: harte Einheit gesenkt"],
      "wishes": "mehr Technik",
      "plan": {
        "rationale": "Solide Woche.",
        "total_distance_meters": 2500,
        "days": [
          {
            "date": "2026-09-30",
            "session_type": "endurance",
            "intensity": "moderate",
            "target_distance_meters": 1500,
            "estimated_duration_minutes": 40,
            "focus": "Ausdauer"
          },
          {
            "date": "2026-10-01",
            "session_type": "rest",
            "intensity": "rest",
            "target_distance_meters": 0,
            "estimated_duration_minutes": 0,
            "focus": "Ruhetag"
          },
          {
            "date": "2026-10-02",
            "session_type": "technique",
            "intensity": "easy",
            "target_distance_meters": 1000,
            "estimated_duration_minutes": 35,
            "focus": "Technik mit Pull Buoy"
          }
        ]
      }
    }
    """

    /// Antwort des rollenden Plans über zwei Kalenderwochen: Sa 03.10. bis Di 06.10.
    static let responseAcrossTwoWeeksJSON = """
    {
      "week_start": "2026-09-30",
      "generated_at": "2026-09-30T10:00:00.000Z",
      "adjustments": [],
      "plan": {
        "rationale": "Zwei Wochen.",
        "total_distance_meters": 3000,
        "days": [
          { "date": "2026-10-03", "session_type": "endurance", "intensity": "moderate", "target_distance_meters": 1500, "estimated_duration_minutes": 40, "focus": "Ausdauer" },
          { "date": "2026-10-04", "session_type": "rest", "intensity": "rest", "target_distance_meters": 0, "estimated_duration_minutes": 0, "focus": "Ruhetag" },
          { "date": "2026-10-05", "session_type": "technique", "intensity": "easy", "target_distance_meters": 1000, "estimated_duration_minutes": 35, "focus": "Technik" },
          { "date": "2026-10-06", "session_type": "endurance", "intensity": "easy", "target_distance_meters": 500, "estimated_duration_minutes": 20, "focus": "Locker" }
        ]
      }
    }
    """
}

