import fc from "fast-check";
import { daysBetween, macroWeekStarts } from "../../../src/plan/calendar";
import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { fixedSport, isFitnessGoal, scheduleDay, trainingDaysPerWeek, weeklyMinutes } from "../../../src/plan/multi/schedule";
import { dayLimits, goalDayOf, MULTI_RULES, phaseOf, RANK, sportLimits, taperFactors, taperWeeks, testBlackoutReason, weeksToGoal } from "../../../src/plan/multi/limits";
import { macroSportLimits, sanitizeMacroV2 } from "../../../src/plan/multi/macroSanity";
import { floorAmount, plannedSports, stateOf } from "../../../src/plan/multi/sports";
import { entryTest, fitsToday, lastConfirmedTest, stepsTotals } from "../../../src/plan/multi/tests";
import { sanitizeWeekV2, weekLimitsV2 } from "../../../src/plan/multi/weekSanity";
import { addDays, windowDates } from "../../../src/plan/calendar";
import { SPORTS } from "../../../src/sports/registry";
import { planningContext } from "../../../src/plan/multi/sports";
import { dayPlanArb, macroPlanArb, recentArb, snapshotArb, testSettingsArb, weekPlanArb } from "./arbitraries";
import { TODAY } from "./fixtures";

/**
 * Property-Tests der Sicherheitsschicht v2: Fuer beliebige gueltige Snapshots und beliebige (auch unsinnige) Plaene von
 * Claude haelt der gepruefte Plan jede Regel ein. Die Regeln stehen hier unabhaengig vom Code noch einmal.
 */
// PROPERTY_RUNS=5000 npx jest test/plan/multi/properties.test.ts fuer einen gruendlicheren Lauf.
const RUNS = { numRuns: Number(process.env.PROPERTY_RUNS ?? 300) };
const MAX_ZONE = { rest: 1, easy: 2, moderate: 3, hard: 5 } as const;
const MAX_EFFORT = { rest: 2, easy: 4, moderate: 6, hard: 10 } as const;
const EPS = 1e-6;

const sport = (id: string) => {
  const found = SPORTS.get(id);
  if (found === undefined) throw new Error(`Sportart ${id} fehlt`);
  return found;
};

describe("Tagesplan v2: Invarianten", () => {
  it("haelt fuer jeden Snapshot und jeden Plan alle Regeln ein", () => {
    fc.assert(
      fc.property(snapshotArb, dayPlanArb, recentArb(TODAY), testSettingsArb, fc.option(fc.subarray(["pull_buoy", "fins"]), { nil: undefined }), (snapshot, raw, recent, settings, equipment) => {
        const options = { date: TODAY, recent, testSettings: settings, equipment };
        const result = sanitizeDayV2(raw, snapshot, options);
        if (raw.rationale.trim() === "") expect(result.blocked).not.toBeNull();
        if (result.blocked !== null) return;
        const today = dayLimits(snapshot, TODAY, recent);
        const sessions = result.plan.sessions;

        expect(sessions.length).toBeLessThanOrEqual(MULTI_RULES.maxSessionsPerDay);
        expect(sessions.filter((session) => session.intensity === "hard").length).toBeLessThanOrEqual(1);
        expect(sessions.filter((session) => session.test !== null).length).toBeLessThanOrEqual(1);
        if (today.restReason !== null) expect(sessions).toEqual([]);
        expect(result.plan.rationale.length).toBeLessThanOrEqual(MULTI_RULES.maxRationaleLength);

        let minutes = 0;
        for (const session of sessions) {
          const definition = sport(session.sport);
          const limits = today.sports.get(session.sport);
          expect(limits).toBeDefined();
          if (limits === undefined) return;
          expect(limits.blockedReason).toBeNull();
          const speed = sportLimits(snapshot, definition).speed;
          const totals = stepsTotals(definition, session.steps, speed);
          minutes += totals.minutes;
          expect(totals.amount).toBeLessThanOrEqual(limits.maxAmount + EPS);
          expect(session.steps.length).toBeLessThanOrEqual(MULTI_RULES.maxStepsPerSession);

          if (session.test !== null) {
            const test = definition.performanceTests.find((entry) => entry.id === session.test?.id);
            expect(test).toBeDefined();
            expect(session.session_type).toBe("test");
            expect(today.testBlockedReason).toBeNull();
            expect(settings?.offer).not.toBe(false);
            expect(session.steps).toEqual(definition.planning.testSessions[test?.id ?? ""]);
            if (test?.maximalEffort) {
              expect(session.intensity).toBe("hard");
              expect(RANK[limits.maxIntensity]).toBe(RANK.hard);
              expect(stateOf(snapshot, session.sport).longest_session_minutes).toBeGreaterThanOrEqual(test.durationMinutes);
            }
            continue;
          }
          expect(session.session_type).not.toBe("test");
          expect(RANK[session.intensity]).toBeLessThanOrEqual(RANK[limits.maxIntensity]);
          expect(session.intensity).not.toBe("rest");

          const planning = definition.planning;
          const context = planningContext(snapshot, definition);
          for (const step of session.steps) {
            expect(planning.stepMeasures).toContain(step.measure);
            expect(step.repetitions).toBeGreaterThanOrEqual(1);
            expect(step.repetitions).toBeLessThanOrEqual(MULTI_RULES.maxRepetitions);
            expect(step.rest_seconds).toBeGreaterThanOrEqual(0);
            expect(step.rest_seconds).toBeLessThanOrEqual(MULTI_RULES.maxRestSeconds);
            if (step.measure === "distance") {
              expect(step.duration_seconds).toBeNull();
              expect((step.distance_meters ?? 0) % planning.distanceStepMeters).toBe(0);
              expect(step.distance_meters).toBeGreaterThanOrEqual(planning.minStepMeters);
              expect(step.distance_meters).toBeLessThanOrEqual(planning.maxStepMeters);
            } else {
              expect(step.distance_meters).toBeNull();
              expect((step.duration_seconds ?? 0) % 5).toBe(0);
              expect(step.duration_seconds).toBeGreaterThanOrEqual(planning.minStepSeconds);
              expect(step.duration_seconds).toBeLessThanOrEqual(planning.maxStepSeconds);
            }
            for (const item of step.equipment) {
              expect(Object.keys(planning.equipment)).toContain(item);
              if (equipment !== undefined) expect(equipment).toContain(item);
            }
            expect(step.cue.length).toBeLessThanOrEqual(MULTI_RULES.maxCueLength);
            expect(step.target_type === null).toBe(step.target_value === null);
            if (step.target_type !== null && step.target_value !== null) {
              expect(definition.targets).toContain(step.target_type);
              const range = planning.targetRange(step.target_type, context);
              expect(range).not.toBeNull();
              expect(step.target_value).toBeGreaterThanOrEqual(range?.min ?? Infinity);
              expect(step.target_value).toBeLessThanOrEqual(range?.max ?? -Infinity);
              if (step.target_type === "heart_rate_zone") expect(step.target_value).toBeLessThanOrEqual(Math.max(MAX_ZONE[session.intensity], range?.min ?? 1));
              if (step.target_type === "perceived_effort") expect(step.target_value).toBeLessThanOrEqual(Math.max(MAX_EFFORT[session.intensity], range?.min ?? 1));
            }
          }
        }
        expect(minutes).toBeLessThanOrEqual(today.maxMinutes + EPS);
      }),
      RUNS
    );
  });
});

describe("Tagesplan v2 mit Leistungstest", () => {
  // Erholt, kein harter Tag zuletzt, Laufen mit Verlauf: hier kommen Tests oft durch.
  const freshArb = snapshotArb.map((snapshot) => ({
    ...snapshot,
    recovery: { ...snapshot.recovery, status: "good" as const },
    flags: [],
    load: { ...snapshot.load, days_since_last_hard_session: 5 },
    sports: snapshot.sports.map((state) => ({ ...state, days_since_last_session: 2 }))
  }));
  const testPlanArb = fc.tuple(fc.constantFrom(...SPORTS.sports), dayPlanArb).map(([definition, raw]) => ({
    ...raw,
    sessions: [{ sport: definition.id, session_type: "test" as const, intensity: "hard" as const, focus: "Test", test_id: definition.performanceTests[0]?.id ?? null, steps: [] }, ...raw.sessions]
  }));

  it("setzt einen Test nur, wenn er passt, mit den Schritten des Moduls", () => {
    fc.assert(
      fc.property(freshArb, testPlanArb, testSettingsArb, (snapshot, raw, settings) => {
        const result = sanitizeDayV2(raw, snapshot, { date: TODAY, testSettings: settings });
        const today = dayLimits(snapshot, TODAY);
        const tests = result.plan.sessions.filter((session) => session.test !== null);
        expect(tests.length).toBeLessThanOrEqual(1);
        expect(result.plan.sessions.filter((session) => session.intensity === "hard").length).toBeLessThanOrEqual(1);
        for (const session of tests) {
          const definition = sport(session.sport);
          const test = definition.performanceTests.find((entry) => entry.id === session.test?.id);
          const limits = today.sports.get(session.sport);
          expect(settings?.offer).not.toBe(false);
          expect(today.testBlockedReason).toBeNull();
          expect(session.steps).toEqual(definition.planning.testSessions[test?.id ?? ""]);
          const totals = stepsTotals(definition, session.steps, sportLimits(snapshot, definition).speed);
          expect(totals.amount).toBeLessThanOrEqual((limits?.maxAmount ?? 0) + EPS);
          expect(totals.minutes).toBeLessThanOrEqual(today.maxMinutes + EPS);
          if (test?.maximalEffort) expect(stateOf(snapshot, session.sport).longest_session_minutes).toBeGreaterThanOrEqual(test.durationMinutes);
        }
      }),
      RUNS
    );
  });
});

describe("Wochenplan v2: Invarianten", () => {
  const fromArb = fc.integer({ min: 0, max: 2 }).map((offset) => addDays(TODAY, offset));

  it("haelt fuer jeden Snapshot und jeden Plan alle Regeln ein", () => {
    fc.assert(
      fc.property(
        snapshotArb,
        fromArb.chain((from) => fc.tuple(fc.constant(from), weekPlanArb(windowDates(from, 7)), recentArb(from), fc.subarray(windowDates(from, 7), { maxLength: 3 }))),
        testSettingsArb,
        (snapshot, [from, raw, recent, unavailable], settings) => {
          const dates = windowDates(from, 7);
          const context = { today: TODAY, dates, unavailable, recent, ...(settings !== undefined ? { testSettings: settings } : {}) };
          const result = sanitizeWeekV2(raw, snapshot, context);
          expect(result.blocked).toBeNull();
          const week = weekLimitsV2(snapshot, context);
          const days = result.plan.days;

          expect(days.map((day) => day.date)).toEqual(dates);
          expect(result.adjustments.length).toBeLessThanOrEqual(MULTI_RULES.maxAdjustmentLines + 1);

          // Ueber alle Sportarten.
          const hardIndexes = days.flatMap((day, index) => (day.sessions.some((session) => session.intensity === "hard") ? [index] : []));
          expect(hardIndexes.length).toBeLessThanOrEqual(MULTI_RULES.maxHardDaysPerWeek);
          hardIndexes.forEach((index, position) => {
            if (position > 0) expect(index - hardIndexes[position - 1]).toBeGreaterThan(1);
          });
          if (week.hardBefore) expect(hardIndexes).not.toContain(0);
          const trainingDays = days.filter((day) => day.sessions.length > 0).length;
          expect(trainingDays).toBeLessThanOrEqual(Math.min(trainingDaysPerWeek(snapshot), 6));
          expect(result.plan.total_minutes).toBeLessThanOrEqual(week.maxMinutes + days.length);

          // Leistungstests.
          const testDays: number[] = [];
          const testedSports = new Set<string>();
          days.forEach((day, index) => {
            expect(day.sessions.length).toBeLessThanOrEqual(MULTI_RULES.maxSessionsPerDay);
            expect(day.sessions.filter((session) => session.intensity === "hard").length).toBeLessThanOrEqual(1);
            if (unavailable.includes(day.date) || scheduleDay(snapshot, day.date)?.trains === false) expect(day.sessions).toEqual([]);
            const fixed = fixedSport(snapshot, day.date);
            if (fixed !== undefined) for (const session of day.sessions) expect(session.sport).toBe(fixed);
            const tests = day.sessions.filter((session) => session.test !== null);
            expect(tests.length).toBeLessThanOrEqual(1);
            if (tests.length > 0) testDays.push(index);
            const cap = day.date === TODAY && week.today !== null ? week.today.maxMinutes : (week.dayMinutes.get(day.date) ?? week.maxDayMinutes);
            const dayMinutes = day.sessions.reduce((sum, session) => sum + session.minutes, 0);
            expect(dayMinutes).toBeLessThanOrEqual(cap + day.sessions.length);
            for (const session of tests) {
              const definition = sport(session.sport);
              const test = definition.performanceTests.find((entry) => entry.id === session.test?.id);
              const limits = week.sports.get(session.sport);
              expect(test).toBeDefined();
              expect(limits).toBeDefined();
              expect(settings?.offer).not.toBe(false);
              expect(testBlackoutReason(snapshot, day.date)).toBeNull();
              expect(testedSports.has(session.sport)).toBe(false);
              testedSports.add(session.sport);
              expect(session.amount).toBeLessThanOrEqual(Math.min(limits?.sessionCap ?? 0, limits?.weeklyCap ?? 0) + 1);
              if (test?.maximalEffort) {
                expect(session.intensity).toBe("hard");
                expect(limits?.pause).toBe(false);
                expect(stateOf(snapshot, session.sport).longest_session_minutes).toBeGreaterThanOrEqual(test.durationMinutes);
              }
            }
          });
          testDays.forEach((index, position) => {
            if (position > 0) expect(index - testDays[position - 1]).toBeGreaterThan(1);
          });

          // Heute.
          if (week.today !== null) {
            const today = days.find((day) => day.date === TODAY);
            if (week.today.restReason !== null) expect(today?.sessions).toEqual([]);
            for (const session of today?.sessions ?? []) {
              const limits = week.today.sports.get(session.sport);
              expect(limits?.blockedReason).toBeNull();
              expect(RANK[session.intensity]).toBeLessThanOrEqual(RANK[limits?.maxIntensity ?? "rest"]);
              if (session.test === null) expect(session.amount).toBeLessThanOrEqual(limits?.maxAmount ?? 0);
            }
          }

          // Je Sportart.
          for (const [sportId, limits] of week.sports) {
            const own = days.flatMap((day) => day.sessions.filter((session) => session.sport === sportId));
            expect(own.length).toBeLessThanOrEqual(limits.sport.planning.limits.maxSessionsPerWeek);
            expect(own.reduce((sum, session) => sum + session.amount, 0)).toBeLessThanOrEqual(limits.weeklyCap + 1);
            for (const session of own) {
              if (session.test !== null) continue;
              expect(session.session_type).not.toBe("test");
              expect(session.amount).toBeLessThanOrEqual(limits.sessionCap);
              expect(session.amount).toBeGreaterThanOrEqual(limits.sport.planning.limits.minSession);
              if (limits.pause) expect(session.intensity).toBe("easy");
            }
          }
          for (const day of days) for (const session of day.sessions) expect(week.sports.has(session.sport)).toBe(true);
        }
      ),
      RUNS
    );
  });
});

describe("Gesamtplan v2: Invarianten", () => {
  it("haelt fuer jeden Snapshot und jeden Plan alle Regeln ein", () => {
    fc.assert(
      fc.property(
        snapshotArb.chain((snapshot) => {
          const weeks = macroWeekStarts(TODAY, goalDayOf(snapshot));
          return fc.tuple(fc.constant(snapshot), fc.constant(weeks), macroPlanArb(weeks), testSettingsArb);
        }),
        ([snapshot, weeks, raw, settings]) => {
          const goalDay = goalDayOf(snapshot);
          const context = { today: TODAY, goalDay, weeks, ...(settings !== undefined ? { testSettings: settings } : {}) };
          const result = sanitizeMacroV2(raw, snapshot, context);
          expect(result.blocked).toBeNull();
          const plan = result.plan;
          const taper = taperWeeks(snapshot);
          const factors = taperFactors(snapshot);

          expect(plan.weeks.map((week) => week.week_start)).toEqual(weeks);
          let streak = 0;
          plan.weeks.forEach((week, index) => {
            expect(week.phase).toBe(phaseOf(snapshot, week.week_start, TODAY));
            if (isFitnessGoal(snapshot)) expect(["base", "maintain"]).toContain(week.phase);
            if (index === 0 || !(week.phase === "base" || week.phase === "specific")) expect(week.deload).toBe(false);
            if (week.phase === "base" || week.phase === "specific") {
              streak = week.deload ? 0 : streak + 1;
              expect(streak).toBeLessThanOrEqual(MULTI_RULES.maxLoadingWeeks);
            }
            expect(week.total_minutes).toBeLessThanOrEqual(weeklyMinutes(snapshot) + week.sports.length);
            const withTraining = week.sports.filter((entry) => entry.amount > 0).length;
            expect(week.sports.reduce((sum, entry) => sum + entry.sessions, 0)).toBeLessThanOrEqual(Math.max(trainingDaysPerWeek(snapshot) * 2, withTraining));
            expect(week.tests.length).toBeLessThanOrEqual(MULTI_RULES.maxTestsPerWeek);
            for (const test of week.tests) {
              expect(["base", "specific", "maintain"]).toContain(week.phase);
              expect(settings?.offer).not.toBe(false);
              if (week.phase !== "maintain" && !isFitnessGoal(snapshot)) expect(daysBetween(addDays(week.week_start, 6), goalDay)).toBeGreaterThan(MULTI_RULES.testBlackoutDays);
              expect(week.sports.find((entry) => entry.sport === test.sport)?.amount ?? 0).toBeGreaterThan(0);
            }
          });

          for (const entry of macroSportLimits(snapshot)) {
            const definition = entry.limits.sport;
            const limits = definition.planning.limits;
            let reference = entry.limits.average;
            let peak = 0;
            plan.weeks.forEach((week, index) => {
              const own = week.sports.find((item) => item.sport === definition.id);
              expect(own).toBeDefined();
              const amount = own?.amount ?? 0;
              expect(amount).toBeLessThanOrEqual(entry.absoluteWeekly);
              if (amount > 0) expect(amount).toBeGreaterThanOrEqual(limits.minSession);
              expect(own?.sessions ?? 0).toBeLessThanOrEqual(limits.maxSessionsPerWeek);
              if (amount > 0) expect((own?.sessions ?? 0) * limits.minSession).toBeLessThanOrEqual(Math.max(amount, limits.minSession));

              // Nach einer angegebenen Pause darf es bis zum Niveau davor schneller gehen, nie darueber hinaus.
              const base = Math.max(reference, entry.floor);
              const back = floorAmount(definition, Math.min(base * entry.returnGrowthFactor, entry.returnTarget));
              expect(entry.returnGrowthFactor).toBeLessThanOrEqual(1.5);
              const growth = index === 0 ? entry.firstWeekCap : Math.max(floorAmount(definition, base * entry.growthFactor), back);
              if (week.phase === "goal_week") {
                // Die Zielwoche enthaelt den Wettkampf selbst.
                const race = floorAmount(definition, entry.race * MULTI_RULES.goalWeekRaceFactor);
                expect(amount).toBeLessThanOrEqual(peak > 0 ? Math.max(floorAmount(definition, peak * MULTI_RULES.goalWeekFactor), race) : Math.max(growth, race));
              } else if (index === 0) {
                expect(amount).toBeLessThanOrEqual(entry.firstWeekCap);
              } else if (week.deload) {
                expect(amount).toBeLessThanOrEqual(floorAmount(definition, reference * MULTI_RULES.deloadFactor));
              } else {
                expect(amount).toBeLessThanOrEqual(growth);
              }
              if (week.phase === "taper" && peak > 0) {
                const factor = factors[Math.min(Math.max(taper - weeksToGoal(week.week_start, goalDay), 0), factors.length - 1)];
                expect(amount).toBeLessThanOrEqual(floorAmount(definition, peak * factor));
              }
              if (!week.deload) reference = index === 0 ? Math.max(amount, reference) : amount;
              if (!week.deload && (week.phase === "base" || week.phase === "specific")) peak = Math.max(peak, amount);
            });

            // Tests der Sportart: Abstand mindestens das Intervall (bis auf die Woche, in der der Termin faellig wird).
            const interval = (settings?.interval_weeks ?? MULTI_RULES.defaultTestIntervalWeeks) * 7;
            const testWeeks = plan.weeks.filter((week) => week.tests.some((test) => test.sport === definition.id)).map((week) => week.week_start);
            testWeeks.forEach((weekStart, position) => {
              if (position > 0) expect(daysBetween(testWeeks[position - 1], weekStart)).toBeGreaterThanOrEqual(interval - 6);
            });
            const last = lastConfirmedTest(snapshot, definition);
            if (last !== undefined && testWeeks.length > 0) expect(daysBetween(last, addDays(testWeeks[0], 6))).toBeGreaterThanOrEqual(interval);
          }
        }
      ),
      { numRuns: Math.ceil(RUNS.numRuns / 2) }
    );
  });

  it("setzt ohne bestaetigten Wert einen Einstiegstest in die ersten zwei Wochen, sonst in die drei Wochen ab der naechsten", () => {
    fc.assert(
      fc.property(
        snapshotArb.filter((snapshot) => daysBetween(TODAY, goalDayOf(snapshot)) > 60),
        (snapshot) => {
          const goalDay = goalDayOf(snapshot);
          const weeks = macroWeekStarts(TODAY, goalDay);
          // Jede Sportart in jeder Woche mit dem Mindestumfang: keine Woche faellt mangels Training aus.
          const raw = {
            rationale: "Aufbau.",
            weeks: weeks.map((week_start) => ({
              week_start,
              deload: false,
              focus: "Grundlage",
              sports: plannedSports(snapshot).map((definition) => ({ sport: definition.id, amount: definition.planning.limits.minSession, sessions: 1 }))
            }))
          };
          const plan = sanitizeMacroV2(raw, snapshot, { today: TODAY, goalDay, weeks }).plan;
          for (const definition of plannedSports(snapshot)) {
            if (definition.performanceTests.length === 0 || lastConfirmedTest(snapshot, definition) !== undefined) continue;
            // Passt der Einstiegstest heute nicht in die Grenze je Einheit, kommt er fruehestens eine Woche spaeter; dann
            // koennen sich bis zu drei verschobene Tests bei hoechstens zwei pro Woche in die dritte Woche schieben.
            const test = entryTest(definition, snapshot);
            const window = test !== undefined && fitsToday(snapshot, definition, test) ? plan.weeks.slice(0, 2) : plan.weeks.slice(1, 3);
            if (window.some((week) => (week.sports.find((entry) => entry.sport === definition.id)?.amount ?? 0) === 0)) continue;
            expect(window.flatMap((week) => week.tests.map((entry) => entry.sport))).toContain(definition.id);
          }
        }
      ),
      { numRuns: Math.ceil(RUNS.numRuns / 3) }
    );
  });
});
