import { addDays, DayTargetSchema, isRealDate, weekdayIndex, weekdayName, weekDates, WeekPlanSchema } from "../../src/plan/week";
import { day, goodWeek, WEEK_START } from "./weekFixtures";

describe("Datumshilfen", () => {
  it("erkennt echte Kalendertage und weist unmoegliche zurueck", () => {
    expect(isRealDate("2026-09-30")).toBe(true);
    expect(isRealDate("2028-02-29")).toBe(true);
    expect(isRealDate("2026-02-29")).toBe(false);
    expect(isRealDate("2026-13-01")).toBe(false);
    expect(isRealDate("30.09.2026")).toBe(false);
    expect(isRealDate("gestern")).toBe(false);
  });

  it("rechnet Tage ueber Monats-, Jahres- und Zeitumstellungsgrenzen", () => {
    expect(addDays("2026-09-30", 1)).toBe("2026-10-01");
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2026-10-25", 1)).toBe("2026-10-26");
    expect(addDays("2026-03-29", -1)).toBe("2026-03-28");
  });

  it("zaehlt die Wochentage ab Montag", () => {
    expect(weekdayIndex("2026-09-28")).toBe(0);
    expect(weekdayIndex("2026-09-30")).toBe(2);
    expect(weekdayIndex("2026-10-04")).toBe(6);
    expect(weekdayName("2026-09-30")).toBe("Mittwoch");
  });

  it("liefert die sieben Tage ab dem Montag", () => {
    const dates = weekDates(WEEK_START);

    expect(dates).toHaveLength(7);
    expect(dates[0]).toBe("2026-09-28");
    expect(dates[6]).toBe("2026-10-04");
  });
});

describe("Schemas", () => {
  it("nimmt einen gueltigen Wochenplan an", () => {
    expect(WeekPlanSchema.safeParse(goodWeek()).success).toBe(true);
  });

  it("weist einen unbekannten Einheitentyp zurueck", () => {
    expect(WeekPlanSchema.safeParse({ ...goodWeek(), days: [{ ...day("2026-09-30"), session_type: "wandern" }] }).success).toBe(false);
  });

  it("begrenzt die Vorgabe fuer einen Tag", () => {
    const valid = { session_type: "technique", intensity: "easy", target_distance_meters: 1000, focus: "Technik" };

    expect(DayTargetSchema.safeParse(valid).success).toBe(true);
    expect(DayTargetSchema.safeParse({ ...valid, target_distance_meters: -1 }).success).toBe(false);
    expect(DayTargetSchema.safeParse({ ...valid, target_distance_meters: 50_000 }).success).toBe(false);
    expect(DayTargetSchema.safeParse({ ...valid, focus: "x".repeat(121) }).success).toBe(false);
  });
});
