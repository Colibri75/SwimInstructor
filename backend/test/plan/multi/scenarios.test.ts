import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { GeneratedPlan, StructuredGenerator } from "../../../src/plan/generator";
import { checkDayPlanV2, checkMacroPlanV2, checkRevisionV2, checkWeekPlanV2 } from "../../../src/plan/multi/evaluation";
import { sanitizeDayV2 } from "../../../src/plan/multi/daySanity";
import { MULTI_DAY_SYSTEM_PROMPT, MULTI_MACRO_SYSTEM_PROMPT } from "../../../src/plan/multi/prompts";
import {
  coveringWeeks,
  dayTargetFrom,
  formatScenarioReport,
  formatSummary,
  kindOf,
  macroTargets,
  MultiScenario,
  parseScenario,
  Recording,
  RecordingGenerator,
  recentFromSnapshot,
  ReplayGenerator,
  runScenario,
  stepSummary,
  ScenarioReport
} from "../../../src/plan/multi/scenarios";
import { MultiMacroPlanSchema } from "../../../src/plan/multi/schemas";
import { dayPlan, multiSnapshot, session, TODAY } from "./fixtures";

/**
 * Die Szenarien aus backend/scenarios/multisport/ laufen mit ihren Aufzeichnungen durch den echten MultiPlanService,
 * wie `EVAL_REPLAY=1 npm run eval:multisport`: ohne Netz, ohne Kosten.
 */
const DIR = path.join(__dirname, "..", "..", "..", "scenarios", "multisport");
const NAMES = readdirSync(DIR)
  .filter((file) => file.endsWith(".json"))
  .map((file) => file.replace(/\.json$/, ""))
  .sort();

function load(name: string): { scenario: MultiScenario; recording: Recording } {
  return {
    scenario: parseScenario(JSON.parse(readFileSync(path.join(DIR, `${name}.json`), "utf8"))),
    recording: JSON.parse(readFileSync(path.join(DIR, "recorded", `${name}.json`), "utf8")) as Recording
  };
}

const reports = new Map<string, ScenarioReport>();

beforeAll(async () => {
  for (const name of NAMES) {
    const { scenario, recording } = load(name);
    reports.set(name, await runScenario(name, scenario, new ReplayGenerator(recording)));
  }
});

function report(name: string): ScenarioReport {
  const found = [...reports.entries()].find(([key]) => key.startsWith(name));
  if (found === undefined) throw new Error(`kein Szenario ${name}`);
  return found[1];
}

const sportsOfWeek = (item: ScenarioReport) => new Set(item.week.result?.plan.days.flatMap((day) => day.sessions.map((entry) => entry.sport)));

describe("Szenarien fuer mehrere Sportarten", () => {
  it("hat die neun Szenarien, jedes mit Aufzeichnung fuer jede Stufe", () => {
    expect(NAMES).toEqual([
      "01-sprint-einsteiger",
      "02-olympisch-schwimmen",
      "03-mitteldistanz",
      "04-nur-laufen",
      "05-nur-schwimmen",
      "06-laufen-nach-verletzung",
      "07-einsteiger-ohne-profil",
      "08-schwimmen-startniveau",
      "09-fitness-wochenraster"
    ]);
    for (const name of NAMES) {
      const { scenario, recording } = load(name);
      const kinds = Object.keys(recording).sort();
      expect(kinds).toEqual(scenario.feedback !== undefined ? ["day", "macro", "revise", "week"] : ["day", "macro", "week"]);
    }
  });

  it.each(NAMES)("%s laeuft ohne Fehler durch alle Stufen", (name) => {
    const item = report(name);

    expect([item.macro.error, item.week.error, item.day.error, item.revise?.error]).toEqual([undefined, undefined, undefined, undefined]);
    expect(item.calls.map((call) => call.kind)).toEqual(item.revise !== undefined ? ["macro", "week", "day", "revise"] : ["macro", "week", "day"]);
    expect(item.macro.checks.length).toBeGreaterThan(0);
    expect(item.week.result?.plan.days).toHaveLength(7);
  });

  it("setzt beim Einsteiger ohne Profil die Einstiegstests in die ersten zwei Wochen", () => {
    const weeks = report("07").macro.result!.plan.weeks;

    expect(new Set(weeks.slice(0, 2).flatMap((week) => week.tests.map((test) => test.sport)))).toEqual(new Set(["swim", "bike", "run"]));
    expect(report("07").macro.checks.find((check) => check.name === "Einstiegstests in den ersten zwei Wochen")?.ok).toBe(true);
  });

  it("plant nur die Sportarten des Ziels", () => {
    expect(report("04").macro.result!.plan.weeks.every((week) => week.sports.map((entry) => entry.sport).join() === "run")).toBe(true);
    expect(sportsOfWeek(report("04"))).toEqual(new Set(["run"]));
    expect(report("05").macro.result!.plan.weeks.every((week) => week.sports.map((entry) => entry.sport).join() === "swim")).toBe(true);
    expect(sportsOfWeek(report("05"))).toEqual(new Set(["swim"]));
  });

  it("spitzt vor der Mitteldistanz zwei Wochen zu und testet alle 8 Wochen, beim Schwimmen 1000 m", () => {
    const weeks = report("03").macro.result!.plan.weeks;
    const swimTests = weeks.filter((week) => week.tests.some((test) => test.sport === "swim"));

    expect(weeks.filter((week) => week.phase === "taper")).toHaveLength(2);
    expect(weeks.at(-1)?.phase).toBe("goal_week");
    expect(swimTests.every((week) => week.tests.find((test) => test.sport === "swim")?.test_id === "time_trial_1000m")).toBe(true);
    // CSS getestet am 01.08.: faellig 8 Wochen spaeter (26.09.), also in der ersten Woche.
    expect(swimTests[0].week_start).toBe("2026-09-28");
  });

  it("startet nach einer angegebenen Pause mit dem Startniveau statt mit dem Wiedereinstieg aus Health", () => {
    const item = report("08");
    const weeks = item.macro.result!.plan.weeks.map((week) => week.sports[0].amount);
    const swims = item.week.result!.plan.days.flatMap((day) => day.sessions.map((entry) => entry.amount));

    // 70 % von 6000 m; ohne Angabe waeren es hoechstens 2400 m (Wiedereinstieg, 800 m je Einheit).
    expect(weeks.slice(0, 3)).toEqual([4200, 5000, 5800]);
    expect(Math.max(...swims)).toBe(2000);
    expect(item.week.result!.adjustments).toEqual([]);
  });

  it("plant ein Fitnessziel ohne Zuspitzen und haelt die Woche im Wochenraster", () => {
    const item = report("09");
    const weeks = item.macro.result!.plan.weeks;
    const days = item.week.result!.plan.days;

    expect(new Set(weeks.map((week) => week.phase))).toEqual(new Set(["base"]));
    expect(Math.max(...weeks.map((week) => week.total_minutes))).toBeLessThanOrEqual(285);
    expect(days.filter((day) => day.sessions.length > 0).map((day) => day.date)).toEqual(["2026-09-30", "2026-10-01", "2026-10-03", "2026-10-04"]);
    expect(days[1].sessions.map((entry) => entry.sport)).toEqual(["bike"]);
    expect(days[4].sessions.map((entry) => entry.sport)).toEqual(["run"]);
    expect(days.map((day) => day.sessions.reduce((sum, entry) => sum + entry.minutes, 0))).toEqual([40, 58, 0, 75, 47, 0, 0]);
  });

  it("haelt das Laufen nach der Verletzungspause kurz und locker", () => {
    const item = report("06");
    const runs = item.week.result!.plan.days.flatMap((day) => day.sessions.filter((entry) => entry.sport === "run"));

    expect(runs.length).toBeGreaterThan(0);
    expect(runs.every((entry) => entry.amount <= 20 && entry.intensity === "easy" && entry.test === null)).toBe(true);
    // Der Test ohne Vollbelastung kommt erst nach der ersten Woche Wiedereinstieg.
    const runTests = item.macro.result!.plan.weeks.flatMap((week) => week.tests.filter((test) => test.sport === "run").map((test) => `${week.week_start} ${test.test_id}`));
    expect(runTests[0]).toMatch(/^2026-10-(05|12|19) entry_easy_25min$/);
  });

  it("aendert den Gesamtplan nach dem Feedback", () => {
    for (const name of ["02", "06"]) {
      const revise = report(name).revise!;
      expect(revise.checks.every((check) => check.ok)).toBe(true);
      expect(revise.result!.changes.length).toBeGreaterThan(0);
    }
  });

  it("schreibt einen Bericht je Szenario und eine Uebersicht mit Kosten", () => {
    const all = NAMES.map(report);
    const text = formatScenarioReport(report("02"));
    const summary = formatSummary(all);

    expect(text).toMatch(/^## 02-olympisch-schwimmen\n/);
    for (const heading of ["### Gesamtplan", "### Die nächsten sieben Tage", "### Heute", "### Feedback zum Gesamtplan", "Prüfungen:", "Modell `"]) expect(text).toContain(heading);
    expect(formatScenarioReport(report("01"))).toContain('Wunsch für die Woche: "Unter der Woche');
    expect(formatScenarioReport(report("05"))).toContain('Wunsch für heute: "Heute gern etwas mit Technik."');
    expect(summary.split("\n").filter((line) => line.startsWith("| 0"))).toHaveLength(NAMES.length * 3 + 2);
    // Synthetische Aufzeichnungen kosten nichts, echte schon: Der Betrag haengt davon ab, welche schon aufgezeichnet sind.
    expect(summary).toMatch(/Geschätzte Kosten: \$\d+\.\d{2} \(29 Aufrufe\)\.$/);
  });
});

describe("Durchlauf und Generatoren", () => {
  it("meldet eine fehlende Aufzeichnung wie einen Fehler von Claude und bricht nicht ab", async () => {
    const { scenario, recording } = load("04-nur-laufen");
    const item = await runScenario("04", scenario, new ReplayGenerator({ macro: recording.macro }));

    expect(item.macro.error).toBeUndefined();
    expect(item.week.error).toBe("unknown");
    expect(item.day.error).toBe("unknown");
    expect(item.day.target).toBeUndefined();
    const text = formatScenarioReport(item);
    expect(text).toContain("**Kein Wochenplan:** unknown");
    expect(text).toContain("**Kein Tagesplan:** unknown");
  });

  it("zeigt ohne Gesamtplan und ohne Ueberarbeitung den Grund", async () => {
    const { scenario } = load("02-olympisch-schwimmen");
    const item = await runScenario("02", scenario, new ReplayGenerator({}));

    expect(item.macro.error).toBe("unknown");
    expect(item.revise).toBeUndefined();
    expect(formatScenarioReport(item)).toContain("**Kein Gesamtplan:** unknown");
    expect(formatSummary([item])).toContain("| 02 | Gesamt | unknown | 0 | 0/0 |");

    const failing: StructuredGenerator = {
      complete: async (system) => {
        if (kindOf(system) === "revise") throw new Error("kaputt");
        return { raw: load("02-olympisch-schwimmen").recording[kindOf(system)]!.raw, model: "m", usage: { inputTokens: 1, outputTokens: 1 } };
      }
    };
    const revised = await runScenario("02", scenario, failing);
    expect(revised.revise?.error).toBe("unknown");
    expect(formatScenarioReport(revised)).toContain("**Keine Überarbeitung:** unknown");
    expect(formatScenarioReport(revised)).toMatch(/Aufruf fehlgeschlagen nach \d+\.\d s: kaputt/);
    expect(stepSummary(revised)).toMatch(/^ok, ok, ok, unknown \(kaputt, nach \d+ s\)$/);
    expect(stepSummary(item)).toBe("unknown (keine Aufzeichnung für macro, nach 0 s), unknown (keine Aufzeichnung für week, nach 0 s), unknown (keine Aufzeichnung für day, nach 0 s)");
  });

  it("zeigt bei einem blockierten Gesamtplan, warum die Sicherheitsschicht blockierte", async () => {
    const { scenario, recording } = load("02-olympisch-schwimmen");
    const blocking: StructuredGenerator = {
      complete: async (system) => {
        const raw = recording[kindOf(system)]!.raw;
        return { raw: kindOf(system) === "macro" ? { ...(raw as object), blocks: [] } : raw, model: "m", usage: { inputTokens: 1, outputTokens: 1 } };
      }
    };
    const item = await runScenario("02", scenario, blocking);

    expect(item.macro).toMatchObject({ error: "sanity_blocked", detail: "Gesamtplan ohne Wochen" });
    expect(formatScenarioReport(item)).toContain("**Kein Gesamtplan:** sanity_blocked (Gesamtplan ohne Wochen)");
    expect(formatSummary([item])).toContain("| 02 | Gesamt | sanity_blocked | 0 | 0/0 |");
    expect(stepSummary(item)).toBe("sanity_blocked (Gesamtplan ohne Wochen), ok, ok");
  });

  it("haelt beim Aufzeichnen jede Antwort mit Quelle, Modell und Zeit fest", async () => {
    const inner: StructuredGenerator = { complete: async (): Promise<GeneratedPlan> => ({ raw: { a: 1 }, model: "claude-test", usage: { inputTokens: 10, outputTokens: 5 } }) };
    const recorder = new RecordingGenerator(inner, () => new Date("2026-10-03T12:00:00Z"));

    await recorder.complete(MULTI_MACRO_SYSTEM_PROMPT, "x", MultiMacroPlanSchema);

    expect(recorder.recording).toEqual({ macro: { source: "claude", model: "claude-test", recorded_at: "2026-10-03T12:00:00.000Z", usage: { inputTokens: 10, outputTokens: 5 }, raw: { a: 1 } } });
    expect(() => kindOf("anderer Prompt")).toThrow("unbekannter System-Prompt");
    expect(kindOf(MULTI_DAY_SYSTEM_PROMPT)).toBe("day");
  });

  it("lehnt Szenarien mit Snapshot v1 ab", () => {
    const first = readdirSync(DIR).filter((file) => file.endsWith(".json")).sort()[0];
    const v1 = { ...JSON.parse(readFileSync(path.join(DIR, first), "utf8")).snapshot, schema_version: 1 };
    expect(() => parseScenario({ description: "alt", today: TODAY, snapshot: v1 })).toThrow("Plan v2 braucht Snapshot v2");
  });

  it("baut das Training der letzten Tage aus dem Snapshot nach, mit der harten Einheit am richtigen Tag", () => {
    const snapshot = multiSnapshot({
      load: { days_since_last_hard_session: 3 },
      sports: { run: { sessions_last_seven_days: 2, minutes_last_seven_days: 60, meters_last_seven_days: 10_000, days_since_last_session: 1 } }
    });

    // Schwimmen 1 und 3 Tage her (2 Einheiten), Rad 3 Tage her, Laufen 1 und 3 Tage her; harte Einheit vor 3 Tagen:
    // die erste Sportart des Verzeichnisses an diesem Tag.
    expect(recentFromSnapshot(snapshot, TODAY)).toEqual([
      { date: "2026-09-27", sport: "bike", minutes: 90, meters: 42_000 },
      { date: "2026-09-27", sport: "run", minutes: 30, meters: 5000 },
      { date: "2026-09-27", sport: "swim", minutes: 35, meters: 1750, hard: true },
      { date: "2026-09-29", sport: "run", minutes: 30, meters: 5000 },
      { date: "2026-09-29", sport: "swim", minutes: 35, meters: 1750 }
    ]);
  });

  it("nimmt aus Gesamt- und Wochenplan genau die Vorgaben, die die App schicken wuerde", () => {
    const item = report("03");
    const targets = macroTargets(item.macro.result!.plan);

    expect(coveringWeeks(targets, TODAY).map((week) => week.week_start)).toEqual(["2026-09-28", "2026-10-05"]);
    expect(coveringWeeks(targets, "2026-10-05").map((week) => week.week_start)).toEqual(["2026-10-05"]);
    expect(dayTargetFrom(item.week.result!.plan, "2026-12-24")).toBeUndefined();
    expect(dayTargetFrom(item.week.result!.plan, TODAY)?.sessions.map((entry) => entry.sport)).toEqual(item.day.result!.plan.sessions.map((entry) => entry.sport));
  });
});

describe("Pruefungen der Bewertung", () => {
  const snapshot = multiSnapshot();

  it("meldet einen Plan ohne Training, eine fehlende Ehrlichkeit und einen unveraenderten Plan", () => {
    const empty = { rationale: "Plan.", total_minutes: 0, days: [] };
    expect(checkWeekPlanV2(snapshot, empty)).toEqual([
      { name: "Schwerpunkte verteilt", ok: false, detail: "kein Training geplant" },
      { name: "Begründung nennt das Ziel", ok: false, detail: 'kein Wort wie "Ziel" oder "Wettkampf" in der Begründung' }
    ]);

    // Halbmarathon in drei Wochen ohne Lauftraining: nicht sicher erreichbar.
    const tight = multiSnapshot({ daysUntilGoal: 21, goal: { disciplines: [{ sport: "run", distance_meters: 21_097 }], emphasis: [{ sport: "run", percent: 100 }] } });
    const plan = { rationale: "Aufbau zum Ziel.", weeks: [] };
    expect(checkMacroPlanV2(tight, plan, TODAY).find((check) => check.name === "Ehrlich bei knapper Zeit")).toEqual({
      name: "Ehrlich bei knapper Zeit",
      ok: false,
      detail: "Laufen lässt sich nicht sicher aufbauen, die Begründung sagt das nicht"
    });
    expect(checkMacroPlanV2(tight, { ...plan, rationale: "Ehrlich: das Ziel ist knapp." }, TODAY).find((check) => check.name === "Ehrlich bei knapper Zeit")?.ok).toBe(true);

    const weeks = macroTargets(report("05").macro.result!.plan);
    expect(checkRevisionV2(weeks, report("05").macro.result!.plan, [])).toEqual([
      { name: "Änderungen genannt", ok: false, detail: "keine" },
      { name: "Plan geändert", ok: false, detail: "alle Umfänge gleich" }
    ]);
  });

  it("vergleicht den Tagesplan mit der Vorgabe der Woche und dem vorgesehenen Test", () => {
    const plan = sanitizeDayV2(dayPlan([session("run")]), multiSnapshot({ load: { days_since_last_hard_session: 5 }, sports: { run: { days_since_last_session: 2, longest_session_minutes: 40 } } }), { date: TODAY }).plan;
    const target = { sessions: [{ sport: "bike", session_type: "test" as const, intensity: "hard" as const, amount: 58, focus: "Test", test_id: "threshold_30min" }] };

    expect(checkDayPlanV2(plan, target)).toEqual([
      { name: "Vorgabe des Wochenplans", ok: false, detail: "geplant Laufen, Vorgabe Radfahren" },
      { name: "Leistungstest der Vorgabe", ok: false, detail: "kein Test im Tagesplan" },
      { name: "Begründung nennt das Ziel", ok: true, detail: "ja" }
    ]);
    expect(checkDayPlanV2({ ...plan, sessions: [] }, { sessions: [] })).toEqual([{ name: "Vorgabe des Wochenplans", ok: true, detail: "geplant Ruhetag, Vorgabe Ruhetag" }]);
  });
});
