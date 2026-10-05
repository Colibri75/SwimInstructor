import fc from "fast-check";
import { INTENSITIES, SESSION_TYPES } from "../../../src/plan/vocabulary";
import { DaySessionRaw, MultiDayPlanRaw, MacroWeeksRaw, MultiWeekPlanRaw, RecentTraining, StepRaw, TestSettings } from "../../../src/plan/multi/schemas";
import { SnapshotSchema, SnapshotV2, SportState } from "../../../src/plan/snapshot";
import { SPORTS } from "../../../src/sports/registry";
import { STEP_TARGETS } from "../../../src/sports/vocabulary";
import { addDays } from "../../../src/plan/calendar";
import { contractSnapshot, emptyState, TODAY } from "./fixtures";

/**
 * Zufaellige, gueltige Snapshots v2 und beliebige (auch unsinnige) Plaene von Claude fuer die Property-Tests der
 * Sicherheitsschicht. Die Snapshots gehen durch das Schema, damit nur Zustaende entstehen, die die App senden kann.
 */
const SPORT_IDS = SPORTS.ids;

/** Typisches Tempo je Sportart fuer die Verlaufswerte (m/s), damit Meter und Minuten zusammenpassen. */
function speedOf(sport: string): number {
  return SPORTS.get(sport)?.planning.typicalSpeedMetersPerSecond ?? 1;
}

const RACE_RANGE: Record<string, [number, number]> = {};
for (const sport of SPORTS.sports) {
  const meters = sport.planning.limitUnit === "meters";
  // Schwimmen 400 m bis 4 km, Rad 10 bis 180 km, Laufen 3 bis 42 km: aus dem typischen Tempo, 10 min bis 6 h.
  RACE_RANGE[sport.id] = meters ? [400, 4000] : [Math.round(sport.planning.typicalSpeedMetersPerSecond * 600), Math.round(sport.planning.typicalSpeedMetersPerSecond * 6 * 3600)];
}

const stateArb = (sport: string): fc.Arbitrary<SportState> =>
  fc.oneof(
    { weight: 1, arbitrary: fc.constant(emptyState(sport)) },
    {
      weight: 4,
      arbitrary: fc
        .record({
          sessionsWeek: fc.integer({ min: 0, max: 7 }),
          sessionsMonth: fc.integer({ min: 0, max: 24 }),
          weekMinutes: fc.integer({ min: 0, max: 900 }),
          averageMinutes: fc.integer({ min: 0, max: 900 }),
          longestMinutes: fc.integer({ min: 0, max: 300 }),
          speedFactor: fc.double({ min: 0.6, max: 1.4, noNaN: true }),
          days: fc.option(fc.integer({ min: 0, max: 60 }), { nil: undefined })
        })
        .map(({ sessionsWeek, sessionsMonth, weekMinutes, averageMinutes, longestMinutes, speedFactor, days }): SportState => {
          const speed = speedOf(sport) * speedFactor;
          return {
            sport,
            sessions_last_seven_days: sessionsWeek,
            sessions_last_four_weeks: Math.max(sessionsMonth, sessionsWeek),
            minutes_last_seven_days: weekMinutes,
            average_weekly_minutes: averageMinutes,
            meters_last_seven_days: Math.round(weekMinutes * 60 * speed),
            average_weekly_meters: Math.round(averageMinutes * 60 * speed),
            longest_session_meters: Math.round(longestMinutes * 60 * speed),
            longest_session_minutes: longestMinutes,
            load_last_seven_days: weekMinutes,
            average_weekly_load: averageMinutes,
            ...(days !== undefined ? { days_since_last_session: days } : {})
          };
        })
    }
  );

/** Schwerpunkte: jede Sportart 0 bis 5 Anteile, mindestens eine, auf 100 % verteilt. */
const emphasisArb = fc
  .array(fc.integer({ min: 0, max: 5 }), { minLength: SPORT_IDS.length, maxLength: SPORT_IDS.length })
  .filter((weights) => weights.some((weight) => weight > 0))
  .map((weights) => {
    const total = weights.reduce((sum, weight) => sum + weight, 0);
    const percents = weights.map((weight) => Math.floor((weight * 100) / total));
    const last = percents.reduce((best, percent, index) => (percent > percents[best] ? index : best), 0);
    percents[last] += 100 - percents.reduce((sum, percent) => sum + percent, 0);
    return SPORT_IDS.map((sport, index) => ({ sport, percent: percents[index] }));
  });

/** Leistungswerte: wie im Vertrag, ohne Profil, oder alle Werte nur geschaetzt (dann fehlen bestaetigte Tests). */
const performanceArb = fc.constantFrom("contract", "none", "estimated");

export const snapshotArb: fc.Arbitrary<SnapshotV2> = fc
  .record({
    emphasis: emphasisArb,
    states: fc.tuple(...SPORT_IDS.map(stateArb)),
    raceFactors: fc.array(fc.double({ min: 0, max: 1, noNaN: true }), { minLength: SPORT_IDS.length, maxLength: SPORT_IDS.length }),
    daysUntilGoal: fc.integer({ min: -30, max: 400 }),
    trainingDays: fc.integer({ min: 1, max: 7 }),
    weeklyHours: fc.constantFrom(0.5, 1, 2, 3.5, 5, 7.5, 10, 15, 25),
    recovery: fc.constantFrom("good", "moderate", "poor", "unknown"),
    flags: fc.subarray(["recovery_poor", "overreaching_risk", "volume_spike"] as const),
    hardDaysAgo: fc.option(fc.integer({ min: 0, max: 10 }), { nil: undefined }),
    performance: performanceArb,
    kind: fc.constantFrom(undefined, "race" as const, "time" as const, "distance" as const, "fitness" as const),
    // Wochenraster (oder keiner): je Tag Training ja/nein, Minuten, Tageszeit und feste Sportart.
    schedule: fc.option(
      fc
        .array(
          fc.record({
            trains: fc.boolean(),
            minutes: fc.constantFrom(15, 30, 45, 60, 90, 180, 300),
            time: fc.constantFrom(undefined, "morning" as const, "midday" as const, "evening" as const),
            sport: fc.option(fc.constantFrom(...SPORT_IDS), { nil: undefined })
          }),
          { minLength: 7, maxLength: 7 }
        )
        .filter((days) => days.some((day) => day.trains))
        .map((days) =>
          days.map((day, index) => ({
            weekday: index + 1,
            trains: day.trains,
            max_minutes: day.trains ? day.minutes : 0,
            ...(day.time !== undefined ? { time_of_day: day.time } : {}),
            ...(day.sport !== undefined ? { sport: day.sport } : {})
          }))
        ),
      { nil: undefined }
    ),
    // Selbst angegebenes Startniveau je Sportart (oder keins), auch unsinnig hoch und abgelaufen.
    startingLevels: fc.tuple(
      ...SPORT_IDS.map((sport) =>
        fc.option(
          fc.record({
            sport: fc.constant(sport),
            weekly_amount: fc.constantFrom(0, 30, 300, 6000, 50_000),
            longest_session: fc.constantFrom(0, 20, 90, 2500, 20_000),
            status: fc.constantFrom("regular" as const, "short_break" as const, "long_break" as const, "beginner" as const),
            reported_at: fc.constantFrom("2026-09-29T19:00:00Z", "2026-08-01T19:00:00Z")
          }),
          { nil: undefined }
        )
      )
    )
  })
  .map((input) => {
    const base = contractSnapshot();
    const goalDay = addDays(TODAY, input.daysUntilGoal);
    const disciplines = input.kind === "fitness" ? [] : input.emphasis
      .filter((entry) => entry.percent > 0)
      .map((entry) => {
        const [min, max] = RACE_RANGE[entry.sport];
        const factor = input.raceFactors[SPORT_IDS.indexOf(entry.sport)];
        return { sport: entry.sport, distance_meters: Math.round(min + (max - min) * factor) };
      });
    let performance = base.performance;
    if (input.performance === "none") performance = undefined;
    if (input.performance === "estimated" && performance !== undefined) {
      performance = {
        athlete: performance.athlete,
        sports: performance.sports.map((entry) => ({ ...entry, values: entry.values.map((value) => ({ ...value, source: "estimated" as const })) }))
      };
    }
    const snapshot = {
      ...base,
      recovery: { ...base.recovery, status: input.recovery },
      flags: [...input.flags],
      load: { ...base.load, days_since_last_hard_session: input.hardDaysAgo },
      training_goal: {
        target_date: `${goalDay}T10:00:00Z`,
        days_until_goal: Math.max(input.daysUntilGoal, 0),
        training_days_per_week: input.trainingDays,
        weekly_hours: input.weeklyHours,
        disciplines,
        emphasis: input.emphasis,
        ...(input.kind !== undefined ? { kind: input.kind } : {}),
        ...(input.schedule !== undefined ? { weekly_schedule: input.schedule } : {})
      },
      sports: [...input.states],
      ...(performance !== undefined ? { performance } : { performance: undefined })
    };
    const levels = input.startingLevels.filter((level) => level !== undefined);
    if (levels.length > 0) (snapshot as { starting_levels?: unknown }).starting_levels = levels;
    if (snapshot.load.days_since_last_hard_session === undefined) delete (snapshot.load as { days_since_last_hard_session?: number }).days_since_last_hard_session;
    if (snapshot.performance === undefined) delete (snapshot as { performance?: unknown }).performance;
    return SnapshotSchema.parse(snapshot) as SnapshotV2;
  });

const textArb = fc.constantFrom("", "  ", "Grundlage", "Locker rollen", "x".repeat(200));

export const stepArb: fc.Arbitrary<StepRaw> = fc.record({
  name: textArb,
  repetitions: fc.integer({ min: 1, max: 40 }),
  measure: fc.constantFrom("distance", "duration"),
  distance_meters: fc.option(fc.integer({ min: 0, max: 20_000 }), { nil: null }),
  duration_seconds: fc.option(fc.integer({ min: 0, max: 4 * 3600 }), { nil: null }),
  target_type: fc.option(fc.constantFrom(...STEP_TARGETS), { nil: null }),
  target_value: fc.option(fc.integer({ min: -10, max: 1000 }), { nil: null }),
  rest_seconds: fc.integer({ min: 0, max: 3000 }),
  instructions: textArb,
  cue: textArb,
  equipment: fc.subarray(["pull_buoy", "paddles", "fins", "snorkel", "kickboard", "ankle_band", "laser_sword"])
});

const sportArb = fc.constantFrom(...SPORT_IDS, "kayak");

const testIdArb = (sport: string) =>
  fc.option(fc.constantFrom(...(SPORTS.get(sport)?.performanceTests.map((test) => test.id) ?? []), "unknown_test"), { nil: null });

export const daySessionArb: fc.Arbitrary<DaySessionRaw> = sportArb.chain((sport) =>
  fc.record({
    sport: fc.constant(sport),
    session_type: fc.constantFrom(...SESSION_TYPES),
    intensity: fc.constantFrom(...INTENSITIES),
    focus: textArb,
    test_id: testIdArb(sport),
    steps: fc.array(stepArb, { maxLength: 8 })
  })
);

export const dayPlanArb: fc.Arbitrary<MultiDayPlanRaw> = fc.record({
  rationale: fc.constantFrom("Plan mit Bezug zum Ziel.", "x".repeat(1500)),
  sessions: fc.array(daySessionArb, { maxLength: 4 }),
  coach_notes: fc.array(textArb, { maxLength: 7 })
});

const weekSessionArb = sportArb.chain((sport) =>
  fc.record({
    sport: fc.constant(sport),
    session_type: fc.constantFrom(...SESSION_TYPES),
    intensity: fc.constantFrom(...INTENSITIES),
    amount: fc.oneof(fc.integer({ min: 0, max: 300 }), fc.integer({ min: 0, max: 8000 })),
    focus: textArb,
    test_id: testIdArb(sport)
  })
);

export function weekPlanArb(dates: string[]): fc.Arbitrary<MultiWeekPlanRaw> {
  const dateArb = fc.oneof({ weight: 6, arbitrary: fc.constantFrom(...dates) }, { weight: 1, arbitrary: fc.constant(addDays(dates[0], -3)) });
  return fc.record({
    rationale: fc.constant("Woche mit Bezug zum Ziel."),
    days: fc.array(fc.record({ date: dateArb, focus: textArb, sessions: fc.array(weekSessionArb, { maxLength: 3 }) }), { minLength: 1, maxLength: 9 })
  });
}

export function macroPlanArb(weeks: string[]): fc.Arbitrary<MacroWeeksRaw> {
  const weekArb = (week_start: string) =>
    fc.record({
      week_start: fc.constant(week_start),
      deload: fc.boolean(),
      focus: textArb,
      sports: fc.array(fc.record({ sport: sportArb, amount: fc.integer({ min: -100, max: 20_000 }), sessions: fc.integer({ min: 0, max: 12 }) }), { maxLength: 5 })
    });
  return fc
    .tuple(...weeks.map(weekArb), fc.array(fc.boolean(), { minLength: weeks.length, maxLength: weeks.length }))
    .map((items) => {
      const keep = items[items.length - 1] as boolean[];
      const all = items.slice(0, -1) as MacroWeeksRaw["weeks"];
      // Meist alle Wochen, manchmal fehlen einzelne.
      const chosen = all.filter((_, index) => keep[index] || index % 3 !== 0);
      return { rationale: "Aufbau bis zum Ziel.", weeks: chosen.length > 0 ? chosen : all.slice(0, 1) };
    });
}

/** Verlauf der Tage vor `from`: harte und lockere Einheiten. */
export function recentArb(from: string): fc.Arbitrary<RecentTraining[]> {
  return fc.array(
    fc.record({
      date: fc.integer({ min: 1, max: 10 }).map((days) => addDays(from, -days)),
      sport: fc.constantFrom(...SPORT_IDS),
      minutes: fc.integer({ min: 10, max: 240 }),
      meters: fc.integer({ min: 0, max: 50_000 }),
      hard: fc.option(fc.boolean(), { nil: undefined })
    }),
    { maxLength: 8 }
  );
}

export const testSettingsArb: fc.Arbitrary<TestSettings | undefined> = fc.option(
  fc.record(
    {
      offer: fc.boolean(),
      interval_weeks: fc.integer({ min: 4, max: 12 }),
      preferred: fc.subarray(SPORTS.sports.flatMap((sport) => sport.performanceTests.map((test) => ({ sport: sport.id, test_id: test.id }))), { maxLength: 2 })
    },
    { requiredKeys: [] }
  ),
  { nil: undefined }
);
