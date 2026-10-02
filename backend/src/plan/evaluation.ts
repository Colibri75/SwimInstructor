import { assessGoal } from "./goal";
import { MacroWeek } from "./macro";
import { TrainingPlan } from "./plan";
import { Snapshot } from "./snapshot";
import { WeekPlan } from "./week";
import { WeekLimits } from "./weekSanity";

/**
 * Automatische Pruefungen fuer die manuelle Bewertung (npm run eval:scenarios): Haelt ein Plan das
 * Gesamtziel des Athleten ein? Das sind Heuristiken. Sie ersetzen nicht das Urteil, ob ein Plan
 * sinnvoll ist, sondern zeigen schnell, wo man hinschauen sollte. Die harten Grenzen (Umfang,
 * Intensitaet, Ruhetage) prueft die Sicherheitsschicht, nicht dieser Code.
 */
export interface EvalCheck {
  name: string;
  ok: boolean;
  detail: string;
}

const GOAL_WORDS = /ziel/i;
const HONEST_WORDS = /nicht (ganz |sicher |mehr )?(erreich|schaff)|unrealistisch|knapp|zu kurz|reicht (die|nicht)|schwierig|ehrlich/i;
const NEW_GOAL_WORDS = /neue[sn]? ziel/i;
/** Ein Wochenplan ohne Warnhinweis liegt mindestens so hoch (Anteil der Wochengrenze). */
const MIN_SHARE_OF_WEEK_LIMIT = 0.5;

/** Der ganze Text, mit dem der Plan seine Entscheidung begruendet. */
function reasoning(rationale: string, notes: string[] = []): string {
  return [rationale, ...notes].join(" ");
}

function shared(snapshot: Snapshot, text: string): EvalCheck[] {
  const a = assessGoal(snapshot);
  const checks: EvalCheck[] = [
    {
      name: "Begründung nennt das Ziel",
      ok: GOAL_WORDS.test(text),
      detail: GOAL_WORDS.test(text) ? "ja" : 'kein Wort "Ziel" in Begründung und Hinweisen'
    }
  ];
  if (a.phase !== "past" && !a.distanceReachableSafely) {
    const honest = HONEST_WORDS.test(text);
    checks.push({
      name: "Sagt ehrlich, dass das Ziel nicht sicher erreichbar ist",
      ok: honest,
      detail: honest ? "ja" : `Aufbau braucht rund ${a.weeksNeededForDistance} Wochen, es bleiben ${a.weeksLeft}; die Begründung sagt dazu nichts`
    });
  }
  if (a.phase === "past") {
    const hint = NEW_GOAL_WORDS.test(text);
    checks.push({
      name: "Weist auf ein neues Ziel hin (Zieltag vorbei)",
      ok: hint,
      detail: hint ? "ja" : "kein Hinweis auf ein neues Ziel"
    });
  }
  return checks;
}

/** Tagesplan gegen das Gesamtziel. */
export function checkDayPlanAgainstGoal(snapshot: Snapshot, plan: TrainingPlan): EvalCheck[] {
  const a = assessGoal(snapshot);
  const checks = shared(snapshot, reasoning(plan.rationale, plan.coach_notes));

  if (a.phase === "past" || a.phase === "peak_week") {
    checks.push({
      name: a.phase === "past" ? "Erhaltend statt hart (Zieltag vorbei)" : "Keine harte Einheit in der Zielwoche",
      ok: plan.intensity !== "hard",
      detail: `Intensität ${plan.intensity}`
    });
  }
  if ((a.phase === "taper" || a.phase === "peak_week") && snapshot.volume.average_weekly_meters > 0) {
    // Ein Tag soll beim Zuspitzen nicht mehr als ein Wochenschnitt-Drittel ausmachen.
    const limit = snapshot.volume.average_weekly_meters / 3;
    checks.push({
      name: "Kurze Einheit beim Zuspitzen",
      ok: plan.total_distance_meters <= limit,
      detail: `${plan.total_distance_meters} m, Orientierung höchstens ${Math.round(limit)} m (ein Drittel des Wochenschnitts)`
    });
  }
  if ((a.phase === "specific" || a.phase === "taper") && plan.intensity !== "easy" && plan.intensity !== "rest") {
    const goalPace = snapshot.goal.target_pace_seconds_per_hundred_meters;
    const near = plan.sets.some((s) => s.target_pace_seconds_per_hundred_meters !== null && s.target_pace_seconds_per_hundred_meters <= goalPace * 1.15);
    checks.push({
      name: "Zielpace-nahe Abschnitte in der zielspezifischen Phase",
      ok: near,
      detail: near ? "ja" : `kein Abschnitt mit Pace bis ${Math.round(goalPace * 1.15)} s/100 m`
    });
  }
  return checks;
}

/** Wochenplan gegen das Gesamtziel. */
export function checkWeekPlanAgainstGoal(snapshot: Snapshot, week: WeekPlan, limits?: WeekLimits): EvalCheck[] {
  const a = assessGoal(snapshot);
  const checks = shared(snapshot, week.rationale);
  const total = week.days.reduce((sum, day) => sum + day.target_distance_meters, 0);
  // Der Versuch am Zieltag (Typ test, hart) gehoert zur Zielwoche und zaehlt nicht als harte Einheit davor.
  const goalDay = snapshot.goal.target_date.slice(0, 10);
  const hard = week.days.filter((day) => day.intensity === "hard" && day.date !== goalDay).length;

  if (a.phase === "past" || a.phase === "peak_week") {
    checks.push({
      name: a.phase === "past" ? "Erhaltend statt hart (Zieltag vorbei)" : "Keine harte Einheit in der Zielwoche",
      ok: hard === 0,
      detail: `${hard} harte Einheit(en)${a.phase === "peak_week" ? " außer dem Versuch am Zieltag" : ""}`
    });
  }
  if ((a.phase === "taper" || a.phase === "peak_week") && snapshot.volume.average_weekly_meters > 0) {
    // In der Zielwoche kommt der Versuch auf die Zieldistanz (mit Einschwimmen) dazu.
    const allowed = a.phase === "peak_week" ? Math.max(snapshot.volume.average_weekly_meters, Math.round(snapshot.goal.distance_meters * 1.2)) : snapshot.volume.average_weekly_meters;
    checks.push({
      name: "Umfang sinkt beim Zuspitzen",
      ok: total <= allowed,
      detail: `${total} m geplant, Wochenschnitt ${snapshot.volume.average_weekly_meters} m${allowed > snapshot.volume.average_weekly_meters ? `, mit dem Versuch am Zieltag bis ${allowed} m` : ""}`
    });
  }
  // Ohne Warnhinweis soll der Plan die Wochengrenze nicht nur zu einem Bruchteil nutzen (zu kleine Woche).
  const warning = snapshot.flags.some((flag) => ["recovery_poor", "overreaching_risk", "volume_spike"].includes(flag));
  if (limits !== undefined && !warning && (a.phase === "base" || a.phase === "specific") && limits.weeklyRemainingMeters > 0) {
    const needed = Math.round(limits.weeklyRemainingMeters * MIN_SHARE_OF_WEEK_LIMIT);
    checks.push({
      name: "Wochenumfang nutzt die Grenze sinnvoll",
      ok: total >= needed,
      detail: `${total} m geplant, Grenze ${limits.weeklyRemainingMeters} m, Orientierung mindestens ${needed} m (${Math.round(MIN_SHARE_OF_WEEK_LIMIT * 100)} % der Grenze)`
    });
  }
  if (a.phase === "specific" && week.days.some((day) => day.intensity !== "rest")) {
    const specific = week.days.some((day) => ["threshold", "intervals", "test"].includes(day.session_type) || /ziel|pace|tempo/i.test(day.focus));
    checks.push({
      name: "Mindestens ein zielspezifischer Tag in der zielspezifischen Phase",
      ok: specific,
      detail: specific ? "ja" : "weder Schwelle/Intervalle/Test noch ein Schwerpunkt mit Zielbezug"
    });
  }
  return checks;
}

/** Gesamtplan gegen das Gesamtziel. */
export function checkMacroPlanAgainstGoal(snapshot: Snapshot, macro: { rationale: string; weeks: MacroWeek[] }): EvalCheck[] {
  const a = assessGoal(snapshot);
  const checks = shared(snapshot, macro.rationale);
  const weeks = macro.weeks;
  if (weeks.length === 0) return [...checks, { name: "Gesamtplan hat Wochen", ok: false, detail: "keine Wochen" }];

  const goalWeek = weeks.find((week) => week.phase === "goal_week");
  const peak = Math.max(...weeks.filter((w) => w.phase === "base" || w.phase === "specific").map((w) => w.target_meters), 0);

  if (a.phase !== "past") {
    checks.push({
      name: "Reicht bis zur Zielwoche",
      ok: goalWeek !== undefined,
      detail: goalWeek ? `Zielwoche ab ${goalWeek.week_start}` : "keine Woche mit Phase goal_week"
    });
  }
  if (goalWeek !== undefined && peak > 0) {
    const taper = weeks.filter((w) => w.phase === "taper");
    checks.push({
      name: "Umfang sinkt beim Zuspitzen und in der Zielwoche",
      ok: goalWeek.target_meters <= peak && taper.every((w) => w.target_meters <= peak),
      detail: `Höhepunkt ${peak} m, Zuspitzen ${taper.map((w) => w.target_meters).join("/") || "–"} m, Zielwoche ${goalWeek.target_meters} m`
    });
  }
  const buildUp = weeks.filter((w) => w.phase === "base" || w.phase === "specific");
  if (buildUp.length >= 8) {
    const deloads = buildUp.filter((w) => w.deload).length;
    checks.push({
      name: "Entlastungswochen eingeplant",
      ok: deloads >= Math.floor(buildUp.length / 6),
      detail: `${deloads} Entlastungswochen in ${buildUp.length} Aufbau-Wochen`
    });
  }
  if (a.distanceReachableSafely && a.phase !== "past" && buildUp.length >= 4) {
    const needed = snapshot.goal.distance_meters * 2;
    checks.push({
      name: "Höhepunkt trägt die Zieldistanz mehrfach pro Woche",
      ok: peak >= needed,
      detail: `Höhepunkt ${peak} m pro Woche, Orientierung mindestens ${needed} m (zweimal die Zieldistanz)`
    });
  }
  return checks;
}

/** Eine Zeile je Pruefung fuer den Bericht. */
export function formatChecks(checks: EvalCheck[]): string {
  if (checks.length === 0) return "Keine automatischen Prüfungen für dieses Szenario.";
  return checks.map((check) => `- [${check.ok ? "x" : " "}] ${check.name}: ${check.detail}`).join("\n");
}
