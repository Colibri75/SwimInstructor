import { macroWeekStarts } from "../../../src/plan/macro";
import { dayLimits, phaseOf, taperWeeks, testBlackoutReason } from "../../../src/plan/multi/limits";
import { sanitizeMacroV2 } from "../../../src/plan/multi/macroSanity";
import { buildDayUserMessageV2, buildMacroUserMessageV2, buildWeekUserMessageV2, goalSectionV2 } from "../../../src/plan/multi/prompts";
import { fixedSport, goalKind, scheduleDayText, trainingDaysPerWeek, weeklyMinutes } from "../../../src/plan/multi/schedule";
import { sanitizeWeekV2, WeekContextV2, weekLimitsV2 } from "../../../src/plan/multi/weekSanity";
import { ScheduleDay, SnapshotSchema, SnapshotV2 } from "../../../src/plan/snapshot";
import { contractSnapshot, macroPlan, multiSnapshot, SnapshotPatch, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

/** Der Wochenraster aus contracts/wire/snapshot-v2.json: Montag und Freitag Ruhetag, Dienstag und Donnerstag Schwimmen. */
const SCHEDULE: ScheduleDay[] = [
  { weekday: 1, trains: false, max_minutes: 0 },
  { weekday: 2, trains: true, time_of_day: "evening", max_minutes: 60, sport: "swim" },
  { weekday: 3, trains: true, time_of_day: "morning", max_minutes: 45 },
  { weekday: 4, trains: true, time_of_day: "evening", max_minutes: 60, sport: "swim" },
  { weekday: 5, trains: false, max_minutes: 0 },
  { weekday: 6, trains: true, time_of_day: "morning", max_minutes: 180 },
  { weekday: 7, trains: true, time_of_day: "morning", max_minutes: 105 }
];

// TODAY (2026-09-30) ist ein Mittwoch.
const THURSDAY = "2026-10-01";
const FRIDAY = "2026-10-02";
const SATURDAY = "2026-10-03";

const rested = { load: { days_since_last_hard_session: 5 }, sports: { swim: { meters_last_seven_days: 1000 }, bike: { minutes_last_seven_days: 30 } } };

function scheduled(patch: SnapshotPatch = {}): SnapshotV2 {
  return multiSnapshot({ ...rested, ...patch, goal: { weekly_schedule: SCHEDULE, ...patch.goal } });
}

function fitness(daysUntilGoal = 182): SnapshotV2 {
  return multiSnapshot({ ...rested, daysUntilGoal, goal: { kind: "fitness", disciplines: [], template: undefined } });
}

const context = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent: [], ...patch });

describe("Zielart und Wochenraster im Snapshot", () => {
  const parse = (goal: Record<string, unknown>) => {
    const base = contractSnapshot("wire/snapshot-v2.json");
    return SnapshotSchema.safeParse({ ...base, training_goal: { ...base.training_goal, ...goal } });
  };

  it("nimmt den Vertrag mit Zielart und Wochenraster an, und ein Ziel ohne beides", () => {
    const snapshot = contractSnapshot("wire/snapshot-v2.json");
    expect(snapshot.training_goal.kind).toBe("race");
    expect(snapshot.training_goal.weekly_schedule).toEqual(SCHEDULE);
    expect(goalKind(contractSnapshot())).toBe("race");
    expect(parse({ kind: "fitness", disciplines: [] }).success).toBe(true);
  });

  it.each([
    ["Fitnessziel mit Disziplin", { kind: "fitness" }],
    ["Wettkampf ohne Disziplin", { kind: "race", disciplines: [] }],
    ["Ziel ohne Art und ohne Disziplin", { kind: undefined, disciplines: [] }],
    ["unbekannte Zielart", { kind: "marathon" }],
    ["sechs Tage", { weekly_schedule: SCHEDULE.slice(0, 6) }],
    ["Wochentag doppelt", { weekly_schedule: [...SCHEDULE.slice(0, 6), SCHEDULE[0]] }],
    ["kein Trainingstag", { weekly_schedule: SCHEDULE.map((day) => ({ ...day, trains: false })) }],
    ["Trainingstag unter 15 min", { weekly_schedule: SCHEDULE.map((day) => (day.weekday === 3 ? { ...day, max_minutes: 10 } : day)) }],
    ["Tag ueber 10 Stunden", { weekly_schedule: SCHEDULE.map((day) => (day.weekday === 6 ? { ...day, max_minutes: 601 } : day)) }],
    ["unbekannte Tageszeit", { weekly_schedule: SCHEDULE.map((day) => (day.weekday === 3 ? { ...day, time_of_day: "night" } : day)) }],
    ["unbekannte feste Sportart", { weekly_schedule: SCHEDULE.map((day) => (day.weekday === 3 ? { ...day, sport: "kayak" } : day)) }]
  ])("lehnt ab: %s", (_why, goal) => {
    expect(parse(goal).success).toBe(false);
  });
});

describe("Wochenraster", () => {
  it("bestimmt Trainingstage, Minuten und den Text je Tag", () => {
    const snapshot = scheduled();
    expect(trainingDaysPerWeek(snapshot)).toBe(5);
    expect(weeklyMinutes(snapshot)).toBe(450);
    expect(scheduleDayText(snapshot, THURSDAY)).toBe("abends, höchstens 60 min, nur Schwimmen");
    expect(scheduleDayText(snapshot, FRIDAY)).toBe("Ruhetag laut Wochenraster");
    expect(scheduleDayText(snapshot, TODAY)).toBe("morgens, höchstens 45 min");
    // Ohne Wochenraster: Tage und Stunden des Ziels.
    expect(trainingDaysPerWeek(multiSnapshot({ goal: { training_days_per_week: 4, weekly_hours: 6 } }))).toBe(4);
    expect(weeklyMinutes(multiSnapshot({ goal: { training_days_per_week: 4, weekly_hours: 6 } }))).toBe(360);
    expect(scheduleDayText(multiSnapshot(), TODAY)).toBeNull();
  });

  it("ignoriert eine feste Sportart ohne Schwerpunkt", () => {
    const snapshot = scheduled({ goal: { emphasis: [{ sport: "swim", percent: 0 }, { sport: "bike", percent: 60 }, { sport: "run", percent: 40 }] } });
    expect(fixedSport(snapshot, THURSDAY)).toBeUndefined();
    expect(scheduleDayText(snapshot, THURSDAY)).toBe("abends, höchstens 60 min");
  });

  it("macht einen freien Tag zum Ruhetag, begrenzt die Minuten und erlaubt am festen Tag nur dessen Sportart", () => {
    const snapshot = scheduled();
    expect(dayLimits(snapshot, FRIDAY).restReason).toBe("Ruhetag laut Wochenraster");
    expect(dayLimits(snapshot, TODAY)).toMatchObject({ restReason: null, maxMinutes: 45 });
    const thursday = dayLimits(snapshot, THURSDAY);
    expect(thursday.maxMinutes).toBe(60);
    expect(thursday.sports.get("swim")?.blockedReason).toBeNull();
    expect(thursday.sports.get("bike")?.blockedReason).toBe("laut Wochenraster heute nur Schwimmen");
    expect(thursday.sports.get("run")?.blockedReason).toBe("laut Wochenraster heute nur Schwimmen");
    // Schlechte Erholung kuerzt auch die Minuten des Wochenrasters.
    expect(dayLimits(scheduled({ recovery: { status: "poor" } }), SATURDAY).maxMinutes).toBe(90);
  });

  it("haelt den Wochenplan im Wochenraster", () => {
    const raw = weekPlan([
      [weekSession("bike", 40)],
      [weekSession("swim", 2000), weekSession("run", 20)],
      [weekSession("run", 30)],
      [weekSession("bike", 240)],
      [weekSession("swim", 2000)],
      [weekSession("bike", 60)],
      [weekSession("swim", 2500)]
    ]);
    const snapshot = scheduled();
    const result = sanitizeWeekV2(raw, snapshot, context());
    const week = weekLimitsV2(snapshot, context());

    expect(week).toMatchObject({ maxTrainingDays: 5, maxMinutes: 450 });
    expect(week.dayMinutes.get(SATURDAY)).toBe(180);
    expect(result.plan.days.map((day) => day.sessions.map((item) => item.sport))).toEqual([["bike"], ["swim"], [], ["bike"], ["swim"], [], ["swim"]]);
    expect(result.plan.days[2].focus).toBe("Ruhetag");
    expect(result.plan.days[3].sessions[0].minutes).toBeLessThanOrEqual(180);
    for (const day of result.plan.days) {
      expect(day.sessions.reduce((sum, item) => sum + item.minutes, 0)).toBeLessThanOrEqual(week.dayMinutes.get(day.date) ?? Infinity);
    }
    expect(result.adjustments).toEqual(
      expect.arrayContaining([
        "Donnerstag, 01.10.: laut Wochenraster nur Schwimmen, andere Sportarten gestrichen",
        "Freitag, 02.10.: Ruhetag laut Wochenraster",
        "Montag, 05.10.: Ruhetag laut Wochenraster"
      ])
    );
  });

  it("nennt den Wochenraster in den Nutzernachrichten", () => {
    const snapshot = scheduled();
    const week = buildWeekUserMessageV2({ snapshot, context: context() });
    expect(week).toContain(`- Donnerstag ${THURSDAY} (abends, höchstens 60 min, nur Schwimmen)`);
    expect(week).toContain(`- Freitag ${FRIDAY} (Ruhetag laut Wochenraster)`);
    expect(week).toContain("an einem Tag höchstens die Minuten des Wochenrasters (bei den Tagen oben), zusammen höchstens 450 min.");
    expect(goalSectionV2(snapshot, TODAY)).toContain(
      "- Wochenraster (vom Athleten festgelegt, verbindlich): Montag Ruhetag laut Wochenraster; Dienstag abends, höchstens 60 min, nur Schwimmen; " +
        "Mittwoch morgens, höchstens 45 min; Donnerstag abends, höchstens 60 min, nur Schwimmen; Freitag Ruhetag laut Wochenraster; " +
        "Samstag morgens, höchstens 180 min; Sonntag morgens, höchstens 105 min. Zusammen 5 Trainingstage und höchstens 7,5 h pro Woche."
    );
    expect(buildDayUserMessageV2({ snapshot, date: TODAY })).toContain("- Wochenraster für heute: morgens, höchstens 45 min.");
    expect(buildDayUserMessageV2({ snapshot, date: FRIDAY })).toContain("Heute ist ein Ruhetag vorgeschrieben (Ruhetag laut Wochenraster): keine Einheiten.");
    expect(buildDayUserMessageV2({ snapshot, date: FRIDAY })).not.toContain("Wochenraster für heute");
    const macro = buildMacroUserMessageV2(snapshot, { today: TODAY, goalDay: "2027-07-04", weeks: macroWeekStarts(TODAY, "2027-07-04") });
    expect(macro).toContain("- Über alle Sportarten höchstens 450 min pro Woche (Summe des Wochenrasters) und höchstens 10 Einheiten.");
    // Ohne Wochenraster wie bisher.
    expect(goalSectionV2(multiSnapshot(), TODAY)).toContain("- 5 Trainingstage und etwa 7,5 h pro Woche.");
  });
});

describe("Fitnessziel", () => {
  it("hat kein Zuspitzen, keine Zielwoche und keine Testsperre vor dem Ende", () => {
    const snapshot = fitness(20);
    expect(taperWeeks(snapshot)).toBe(0);
    const weeks = macroWeekStarts(TODAY, "2026-10-20");
    expect(weeks.map((week) => phaseOf(snapshot, week, TODAY))).toEqual(weeks.map(() => "base"));
    expect(testBlackoutReason(snapshot, "2026-10-19")).toBeNull();
    expect(phaseOf(fitness(-3), "2026-09-28", TODAY)).toBe("maintain");
  });

  it("plant den Gesamtplan ohne Zuspitzen bis zum Ende des Planungszeitraums", () => {
    const snapshot = fitness();
    const goalDay = "2027-03-31";
    const weeks = macroWeekStarts(TODAY, goalDay);
    const message = buildMacroUserMessageV2(snapshot, { today: TODAY, goalDay, weeks });
    expect(message).toContain(`Erstelle den Gesamtplan bis zum Ende des Planungszeitraums am ${goalDay}.`);
    expect(message).toContain("- Zielart: fit werden und bleiben, ohne Wettkampf und ohne Zuspitzen.");
    expect(message).toContain("Kein Zuspitzen: steigere bis zu den Wochenminuten unten und halte sie dann.");
    expect(message).not.toContain("Zuspitzen: je Sportart");
    expect(message).not.toContain(": taper");

    const raw = macroPlan(weeks, () => ({ swim: 3000, bike: 100, run: 40 }));
    const result = sanitizeMacroV2(raw, snapshot, { today: TODAY, goalDay, weeks });
    expect(result.blocked).toBeNull();
    expect(new Set(result.plan.weeks.map((week) => week.phase))).toEqual(new Set(["base"]));
  });

  it("nennt Zeit und Strecke ohne Wettkampf als eigenen Versuch", () => {
    expect(goalSectionV2(multiSnapshot({ goal: { kind: "time" } }), TODAY)).toContain("- Zielart: Zeit über eine Strecke, ohne Wettkampf: am Zieltag ein eigener Zeitversuch.");
    expect(goalSectionV2(multiSnapshot({ goal: { kind: "distance" } }), TODAY)).toContain("Versuch insgesamt etwa");
    expect(goalSectionV2(multiSnapshot(), TODAY)).toContain("- Zielart: Wettkampf.");
  });
});
