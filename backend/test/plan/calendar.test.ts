import { addDays, daysBetween, isRealDate, localDate, macroWeekStarts, MAX_MACRO_WEEKS, mondayOf, weekdayIndex, weekdayName, weekDates } from "../../src/plan/calendar";

const WEEK_START = "2026-09-28";

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

describe("Gesamtplan: Wochen", () => {
  it("rechnet den Montag der Woche", () => {
    expect(mondayOf("2026-09-30")).toBe("2026-09-28"); // Mittwoch
    expect(mondayOf("2026-09-28")).toBe("2026-09-28"); // Montag
    expect(mondayOf("2026-10-04")).toBe("2026-09-28"); // Sonntag
  });

  it("rechnet Tage zwischen zwei Kalendertagen, auch ueber die Zeitumstellung", () => {
    expect(daysBetween("2026-09-28", "2026-10-05")).toBe(7);
    expect(daysBetween("2026-10-20", "2026-10-31")).toBe(11);
    expect(daysBetween("2026-03-25", "2026-03-30")).toBe(5);
    expect(daysBetween("2026-10-05", "2026-09-28")).toBe(-7);
  });

  it("plant die Wochen vom Montag von heute bis zum Montag der Zielwoche", () => {
    // Ziel Donnerstag 12.11.: Zielwoche ab Montag 09.11.
    expect(macroWeekStarts("2026-09-30", "2026-11-12")).toEqual([
      "2026-09-28",
      "2026-10-05",
      "2026-10-12",
      "2026-10-19",
      "2026-10-26",
      "2026-11-02",
      "2026-11-09"
    ]);
  });

  it("reicht beim Standardziel bis zur Woche des 04.07.2027 (ein Sonntag)", () => {
    const weeks = macroWeekStarts("2026-10-02", "2027-07-04");

    expect(weeks[0]).toBe("2026-09-28");
    expect(weeks[weeks.length - 1]).toBe("2027-06-28");
    expect(weeks).toHaveLength(40);
  });

  it("hat nur die laufende Woche, wenn das Ziel heute oder in dieser Woche liegt oder vorbei ist", () => {
    expect(macroWeekStarts("2026-09-30", "2026-10-02")).toEqual(["2026-09-28"]);
    expect(macroWeekStarts("2026-09-30", "2026-09-30")).toEqual(["2026-09-28"]);
    expect(macroWeekStarts("2026-09-30", "2026-08-01")).toEqual(["2026-09-28"]);
  });

  it("begrenzt die Zahl der Wochen", () => {
    expect(macroWeekStarts("2026-09-30", "2031-01-01")).toHaveLength(MAX_MACRO_WEEKS);
    expect(macroWeekStarts("2026-09-30", "2031-01-01", 10)).toHaveLength(10);
  });
});

describe("localDate", () => {
  it("liefert den Kalendertag in der Zeitzone", () => {
    const instant = new Date("2026-09-30T23:30:00Z");

    expect(localDate(instant, "UTC")).toBe("2026-09-30");
    expect(localDate(instant, "Europe/Berlin")).toBe("2026-10-01");
    expect(localDate(instant, "America/Los_Angeles")).toBe("2026-09-30");
  });
});
