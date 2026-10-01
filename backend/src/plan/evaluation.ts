import { assessGoal } from "./goal";
import { TrainingPlan } from "./plan";
import { Snapshot } from "./snapshot";
import { WeekPlan } from "./week";

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
export function checkWeekPlanAgainstGoal(snapshot: Snapshot, week: WeekPlan): EvalCheck[] {
  const a = assessGoal(snapshot);
  const checks = shared(snapshot, week.rationale);
  const total = week.days.reduce((sum, day) => sum + day.target_distance_meters, 0);
  const hard = week.days.filter((day) => day.intensity === "hard").length;

  if (a.phase === "past" || a.phase === "peak_week") {
    checks.push({
      name: a.phase === "past" ? "Erhaltend statt hart (Zieltag vorbei)" : "Keine harte Einheit in der Zielwoche",
      ok: hard === 0,
      detail: `${hard} harte Einheit(en)`
    });
  }
  if ((a.phase === "taper" || a.phase === "peak_week") && snapshot.volume.average_weekly_meters > 0) {
    checks.push({
      name: "Umfang sinkt beim Zuspitzen",
      ok: total <= snapshot.volume.average_weekly_meters,
      detail: `${total} m geplant, Wochenschnitt ${snapshot.volume.average_weekly_meters} m`
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

/** Eine Zeile je Pruefung fuer den Bericht. */
export function formatChecks(checks: EvalCheck[]): string {
  if (checks.length === 0) return "Keine automatischen Prüfungen für dieses Szenario.";
  return checks.map((check) => `- [${check.ok ? "x" : " "}] ${check.name}: ${check.detail}`).join("\n");
}
