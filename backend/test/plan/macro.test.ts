import { daysBetween, macroPhase, macroWeekStarts, mondayOf, MAX_MACRO_WEEKS } from "../../src/plan/macro";

describe("Gesamtplan: Wochen und Phasen", () => {
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

  it.each([
    ["2026-09-28", "base"],
    ["2027-03-29", "base"], // 13 Wochen vor der Zielwoche
    ["2027-04-05", "specific"], // 12 Wochen
    ["2027-06-07", "specific"], // 3 Wochen
    ["2027-06-14", "taper"], // 2 Wochen
    ["2027-06-21", "taper"], // 1 Woche
    ["2027-06-28", "goal_week"]
  ])("Woche ab %s: Phase %s", (weekStart, phase) => {
    // Das Ziel liegt am Sonntag 04.07.2027, die Zielwoche beginnt am 28.06.2027.
    expect(macroPhase(weekStart, "2027-07-04", "2026-09-30")).toBe(phase);
  });

  it("nennt nach dem Zieltag nur noch Erhalten", () => {
    expect(macroPhase("2026-09-28", "2026-08-01", "2026-09-30")).toBe("maintain");
  });
});
