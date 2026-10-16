import { LANGUAGES } from "../../../src/plan/language";
import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { MacroContextV2, sanitizeMacroV2 } from "../../../src/plan/multi/macroSanity";
import { CATALOGS, SafetyCatalog, say, sportText } from "../../../src/plan/multi/texts";
import { sanitizeWeekV2, WeekContextV2 } from "../../../src/plan/multi/weekSanity";
import { macroWeekStarts } from "../../../src/plan/calendar";
import { DayWeather } from "../../../src/plan/weather";
import { dayPlan, macroPlan, multiSnapshot, RUNNER, session, swimStep, TODAY, weekDates, weekPlan, weekSession } from "./fixtures";

const swimSession = (meters: number[]) => session("swim", { steps: meters.map((m) => swimStep(m)) });

type Sentence = { [K in keyof SafetyCatalog]: SafetyCatalog[K] extends (...args: never[]) => string ? K : never }[keyof SafetyCatalog];

/** Beispielwerte fuer jeden Satz: Fehlt ein neuer Satz hier, meldet TypeScript das. */
const SAMPLES: { [K in Sentence]: Parameters<SafetyCatalog[K]> } = {
  day: ["2026-10-06"],
  date: ["2026-10-06"],
  week: ["2026-10-05"],
  list: [["A", "B"], "or"],
  onDay: ["Tag", "Text"],
  safetyNote: [["a", "b", "c"], 2],
  macroNote: [3],
  restToday: ["Grund"],
  restNothingFits: [],
  missingDays: [2, "Tage"],
  noTimeRest: [],
  calendarNoTimeRest: [],
  scheduleRest: [],
  scheduleOnly: ["Sport"],
  sessionsCut: [2],
  sessionsCutToday: [2],
  unplannedSessions: ["Sport"],
  dayCapped: [120, 90, true],
  oneHardPerDay: [],
  oneHardToday: [],
  weeklyCut: ["Sport", "200 min", "150 min"],
  restDaySet: ["Grund"],
  totalCut: [600, 480],
  dropped: ["Sport", "Grund"],
  lowered: ["Sport", "easy", "Grund"],
  cut: ["Sport", "60 min", "45 min", "Grund"],
  brickSeparate: ["Sport", ""],
  outdoor: ["Sport", ""],
  indoorForWeather: ["Wetter", "Sport", "Ort"],
  indoorForWeatherToday: ["Wetter", "Sport", "Ort"],
  pool: ["Sport", true],
  poolForWeather: ["Wetter", "Sport"],
  poolForWeatherToday: ["Wetter", "Sport"],
  openWaterForRace: ["Sport"],
  noStrengthBeforeGoal: [7],
  noStrength: ["Grund"],
  noStrengthBeforeHard: [],
  extraMaxPerWeek: ["Kraft", 2],
  extraNoTime: ["Kraft"],
  easyAfterPause: ["Sport"],
  raised: ["Sport", "15 min", "20 min"],
  belowMinimum: ["Sport", "20 min"],
  noTest: ["Sport", "Grund"],
  noTestToday: ["Sport", "Grund"],
  hardLowered: ["Grund"],
  testMoved: ["Sport", "Tag", "Grund"],
  forcedRest: ["Grund"],
  forcedRestToday: ["Grund"],
  moreCorrections: [3],
  maxSessionsPerWeek: [3],
  maxTrainingDays: [5],
  minOneRestDay: [],
  notTwoDaysInRow: [],
  maxHardDays: [2],
  rollingWindow: ["150 min", "120 min"],
  sessionCap: [],
  todayCap: [],
  easyShare: [80],
  testsOff: [],
  oneTestPerDay: [],
  oneTestPerSport: [],
  doesNotFit: [],
  reentry: [],
  extrasNotPlanned: ["Kraft"],
  equipmentRemoved: ["Flossen"],
  targetsAdjusted: [],
  stepsCut: ["Sport", 12],
  noSteps: ["Sport"],
  intensityLowered: ["Sport", "hard", "easy", "Grund"],
  tooLittleLeft: [],
  amountCutToday: ["Sport", "60 min", "45 min", "45 min"],
  deloadSet: [3],
  capped: ["Sport", "200 min", "150 min", "Grund"],
  firstWeekCap: [],
  deloadWeek: [],
  growth: [10],
  returnGrowth: [20],
  taper: [],
  goalWeek: [],
  taperSessions: ["Sport", 3, 2],
  missingWeeks: [2],
  unplannedSports: ["Sport"],
  moreVolumeCorrections: [3],
  overreaching: [],
  recoveryPoor: [],
  recoveryModerate: [],
  hardRecently: [],
  hardDaysRecently: [2],
  fixedSportToday: ["Sport"],
  painPause: ["Grund", "08.10."],
  weekExhausted: [],
  tooLittleSafe: [],
  pain: [2, "Knie", "Sport", "04.10."],
  testBlackout: [14],
  thunderstorm: [],
  storm: [70],
  heavyRain: [15],
  ice: [],
  tooColdForOpenWater: [14],
  noTestForSport: [],
  noMaxEffort: ["Test", "Grund"],
  atMost: ["moderate"],
  longestTooShort: ["Test", 20],
  testOverAmount: ["Test", "2000 m", "1500 m"],
  testOverMinutes: ["Test", 50, 40],
  raceMissing: ["Sport"],
  raceImplausible: ["Sport", 30, 45],
  raceForeign: ["Sport"],
  racePacing: [],
  raceNoFuel: ["Sport"],
  raceFuel: [90, 800, 1000]
};

const SENTENCES = Object.keys(SAMPLES) as Sentence[];
const write = (language: (typeof LANGUAGES)[number], key: Sentence) => (CATALOGS[language][key] as (...args: unknown[]) => string)(...SAMPLES[key]);

describe("Texte der Sicherheitsschicht", () => {
  it.each(LANGUAGES)("hat in %s jeden Satz ohne Luecken", (language) => {
    for (const key of SENTENCES) {
      const text = write(language, key);
      expect(text.trim()).not.toBe("");
      expect(text).not.toMatch(/undefined|NaN|\[object|\$\{/);
    }
  });

  it.each(LANGUAGES.filter((language) => language !== "de"))("uebersetzt in %s jeden Satz mit eigenem Text", (language) => {
    const german = SENTENCES.filter((key) => !["date", "onDay", "list"].includes(key) && write(language, key) === write("de", key));
    expect(german).toEqual([]);
  });

  it.each(LANGUAGES)("kennt in %s dieselben Woerter wie auf Deutsch", (language) => {
    for (const words of ["sports", "extras", "equipment", "venues", "tests", "intensities", "painAreas"] as const) {
      expect(Object.keys(CATALOGS[language][words]).sort()).toEqual(Object.keys(CATALOGS.de[words]).sort());
    }
  });

  it("schreibt eingesetzte Texte in derselben Sprache", () => {
    const note = say("dropped", sportText("run"), say("maxSessionsPerWeek", 3));
    expect(note.in("de")).toBe("Laufen gestrichen (höchstens 3 Einheiten pro Woche)");
    expect(note.in("en")).toBe("Running removed (at most 3 sessions per week)");
    expect(note.in("fr")).toBe("séance de course à pied retirée (3 séances par semaine maximum)");
    expect(String(note)).toBe(note.in("de"));
  });
});

const BIKER = { sessions_last_seven_days: 3, sessions_last_four_weeks: 12, minutes_last_seven_days: 180, average_weekly_minutes: 200, meters_last_seven_days: 60_000, average_weekly_meters: 70_000, longest_session_meters: 40_000, longest_session_minutes: 90, days_since_last_session: 1 };
const athlete = () => multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: RUNNER, bike: BIKER, swim: { meters_last_seven_days: 1000 } } });
const weekContext = (patch: Partial<WeekContextV2> = {}): WeekContextV2 => ({ today: TODAY, dates: weekDates(), unavailable: [], recent: [], ...patch });
const storm = (date: string): DayWeather => ({ date, temp_max_c: 20, temp_min_c: 10, precipitation_mm: 0, precipitation_probability: 0, wind_max_kmh: 10, weather_code: 95 });

describe("Liste \"Zur Sicherheit angepasst\" in der Sprache der App", () => {
  const raw = weekPlan([[weekSession("bike", 60), weekSession("run", 20, { brick: true, indoor: true })]]);

  it("schreibt den Wochenplan auf Deutsch wie bisher", () => {
    const result = sanitizeWeekV2(raw, athlete(), weekContext({ weather: [storm(TODAY)], equipment: ["indoor_trainer"] }));
    expect(result.adjustments).toEqual(["Mittwoch, 30.09.: Gewitter angesagt, Radfahren drinnen (Rolle)", "Mittwoch, 30.09.: Laufen draußen (kein Laufband angegeben)"]);
    expect(result.plan.rationale).toContain("Hinweis: Zur Sicherheit angepasst (Mittwoch, 30.09.: Gewitter angesagt");
  });

  it("schreibt den Wochenplan auf Englisch und Japanisch", () => {
    const english = sanitizeWeekV2(raw, athlete(), weekContext({ weather: [storm(TODAY)], equipment: ["indoor_trainer"], language: "en" }));
    expect(english.adjustments).toEqual(["Wed, 9/30: thunderstorms forecast, Cycling indoors (Bike trainer)", "Wed, 9/30: Running outdoors (no treadmill listed)"]);
    expect(english.plan.rationale).toContain("Note: adjusted for safety (Wed, 9/30: thunderstorms forecast");

    const japanese = sanitizeWeekV2(raw, athlete(), weekContext({ weather: [storm(TODAY)], equipment: ["indoor_trainer"], language: "ja" }));
    expect(japanese.adjustments).toEqual(["9/30(水)：雷雨の予報のためバイクは屋内で（ローラー台）", "9/30(水)：ランは屋外で（トレッドミルの登録なし）"]);

    const korean = sanitizeWeekV2(raw, athlete(), weekContext({ weather: [storm(TODAY)], equipment: ["indoor_trainer"], language: "ko" }));
    expect(korean.adjustments).toEqual(["9. 30. (수): 뇌우 예보, 사이클은 실내에서(실내 자전거)", "9. 30. (수): 달리기는 실외에서(트레드밀 등록 안 됨)"]);
  });

  it("schreibt Gruende aus den Grenzen fuer heute in der Sprache der App", () => {
    const result = sanitizeDayV2(dayPlan([swimSession([400])]), multiSnapshot({ flags: ["overreaching_risk"] }), { date: TODAY, language: "en" });
    expect(result.adjustments).toEqual(["Rest day required: poor recovery values under high load (risk of overtraining)"]);
    expect(result.plan.rationale).toBe("Today is a rest day: poor recovery values under high load (risk of overtraining).");
  });

  it.each(LANGUAGES.filter((language) => language !== "de"))("enthaelt in %s keine deutschen Saetze", (language) => {
    const week = sanitizeWeekV2(
      weekPlan([[weekSession("bike", 60), weekSession("run", 20, { brick: true, indoor: true })], [weekSession("swim", 1000, { open_water: true })], [weekSession("run", 400)]]),
      athlete(),
      weekContext({ weather: [storm(TODAY)], equipment: ["indoor_trainer"], language })
    );
    const day = sanitizeDayV2(dayPlan([swimSession([400])]), multiSnapshot({ flags: ["overreaching_risk"] }), { date: TODAY, language });
    const lines = [...week.adjustments, ...day.adjustments, week.plan.rationale, day.plan.rationale];
    expect(week.adjustments.length).toBeGreaterThan(2);
    for (const line of lines) expect(line).not.toMatch(/gestrichen|gekürzt|Einheit|Ruhetag|angesagt|Laufen|Radfahren|Schwimmen|Hinweis|Mittwoch/);
  });

  it("schreibt den Hinweis im Gesamtplan in der Sprache der App", () => {
    const weeks = macroWeekStarts(TODAY, "2027-07-04").slice(0, 3);
    const context = (language?: MacroContextV2["language"]): MacroContextV2 => ({ today: TODAY, goalDay: "2027-07-04", weeks, ...(language !== undefined ? { language } : {}) });
    const raw = macroPlan(weeks, () => ({ swim: 3500, bike: 100, run: 400 }));

    const german = sanitizeMacroV2(raw, multiSnapshot(), context());
    const english = sanitizeMacroV2(raw, multiSnapshot(), context("en"));
    expect(german.adjustments[0]).toMatch(/^Woche ab 28\.09\.: Laufen von 400 min auf \d+ min begrenzt \(Grenze für die erste Woche\)$/);
    expect(english.adjustments[0]).toMatch(/^Week of 9\/28: Running limited from 400 min to \d+ min \(limit for the first week\)$/);
    expect(english.plan.rationale).toMatch(/Note: adjusted for safety in \d+ places?; the weeks show the checked volumes\.$/);
  });
});
