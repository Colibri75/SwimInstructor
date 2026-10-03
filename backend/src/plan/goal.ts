import { multiSportSection } from "./multiSport";
import { Snapshot } from "./snapshot";

/**
 * Das Gesamtziel des Athleten (Distanz, Zielzeit, Zieltag; in der App einstellbar) als feste Fakten fuer
 * den Prompt. Alles ist aus den Zahlen des Snapshots berechnet, nie Freitext vom Client: So haengt es
 * nicht von Claudes Rechenkuensten ab, ob "noch 9 Wochen" oder "in zwei Wochen Zuspitzen" richtig
 * eingeordnet wird.
 */
export type GoalPhase = "past" | "peak_week" | "taper" | "specific" | "base";

export interface GoalAssessment {
  phase: GoalPhase;
  /** Volle und angebrochene Wochen bis zum Zieltag. */
  weeksLeft: number;
  /** Laengste Einheit der letzten 4 Wochen in Prozent der Zieldistanz. */
  longestPercent: number;
  /** Wochen, die ein sicherer Aufbau (etwa 10 % mehr je Woche) bis zur Zieldistanz braucht; 0, wenn sie schon geschwommen wird. */
  weeksNeededForDistance: number;
  /** Reicht die Restzeit fuer einen sicheren Aufbau bis zur Zieldistanz? */
  distanceReachableSafely: boolean;
}

/** Wochenzuwachs, den die Leitplanken erlauben (etwa 10 Prozent). */
const SAFE_WEEKLY_GROWTH = 1.1;
/** Ab so vielen Tagen vor dem Ziel gilt eine Phase. */
const PEAK_WEEK_DAYS = 7;
const TAPER_DAYS = 14;
const SPECIFIC_DAYS = 84;

export function assessGoal(snapshot: Snapshot): GoalAssessment {
  const { goal, volume } = snapshot;
  const days = goal.days_until_goal;
  const phase: GoalPhase =
    days <= 0 ? "past" : days <= PEAK_WEEK_DAYS ? "peak_week" : days <= TAPER_DAYS ? "taper" : days <= SPECIFIC_DAYS ? "specific" : "base";

  const weeksLeft = Math.ceil(days / 7);
  const longestPercent = Math.round((volume.longest_session_meters / goal.distance_meters) * 100);
  // Ausgangspunkt mindestens 100 m, damit "noch nie geschwommen" nicht unendlich lange dauert.
  const start = Math.max(volume.longest_session_meters, 100);
  const weeksNeededForDistance = start >= goal.distance_meters ? 0 : Math.ceil(Math.log(goal.distance_meters / start) / Math.log(SAFE_WEEKLY_GROWTH));
  return {
    phase,
    weeksLeft,
    longestPercent,
    weeksNeededForDistance,
    distanceReachableSafely: weeksNeededForDistance <= weeksLeft
  };
}

function formatPace(seconds: number): string {
  const total = Math.round(seconds);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

function formatDuration(seconds: number): string {
  const minutes = Math.round(seconds / 60);
  return minutes >= 120 ? `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, "0")} min` : `${minutes} min`;
}

const PHASE_TEXT: Record<GoalPhase, string> = {
  past: "Das Zieldatum ist erreicht oder vorbei. Plane erhaltend und locker, und sage in der Begründung in einem Satz, dass der Athlet in den Einstellungen ein neues Ziel setzen kann.",
  peak_week: "Zielwoche. Kurze, lockere Einheiten mit wenigen kurzen Zielpace-Abschnitten, damit der Athlet frisch am Zieltag ankommt. Kein Umfang mehr aufbauen.",
  taper: "Zuspitzen (letzte ein bis zwei Wochen). Der Umfang sinkt, die Qualität bleibt: zielpace-nah, aber kürzer als zuvor.",
  specific: "Zielspezifische Phase. Die Einheiten arbeiten erkennbar auf Zieldistanz und Zielpace hin: Schwelle, lange Ausdauer, Abschnitte in Zielpace.",
  base: "Aufbauphase. Umfang und Ausdauer stehen im Vordergrund, dazu Technik; Zielpace nur sparsam und in kurzen Stücken."
};

/** Der Abschnitt "Gesamtziel" der Nutzernachricht (Tages- und Wochenplan). */
export function goalSection(snapshot: Snapshot): string {
  const { goal } = snapshot;
  const a = assessGoal(snapshot);
  const lines = [
    "Gesamtziel des Athleten (in der App eingestellt, aus dem Snapshot berechnet, verbindlicher Maßstab nach der Sicherheit):",
    `- ${goal.distance_meters} m in ${formatDuration(goal.target_duration_seconds)} (Zielpace ${formatPace(goal.target_pace_seconds_per_hundred_meters)} pro 100 m), am ${goal.target_date.slice(0, 10)}.`,
    a.phase === "past" ? "- Der Zieltag ist heute oder schon vorbei." : `- Noch ${goal.days_until_goal} Tage (${a.weeksLeft} Wochen).`,
    `- Längste Einheit der letzten 4 Wochen: ${snapshot.volume.longest_session_meters} m (${a.longestPercent} % der Zieldistanz).`
  ];
  const gap = snapshot.pace.gap_to_target_seconds_per_hundred_meters;
  if (gap !== undefined) {
    lines.push(gap > 0 ? `- Aktuelle Pace: ${Math.round(gap)} s pro 100 m langsamer als die Zielpace.` : "- Aktuelle Pace: schon auf Zielpace oder schneller.");
  }
  lines.push(`- Phase: ${PHASE_TEXT[a.phase]}`);
  if (a.phase !== "past" && !a.distanceReachableSafely) {
    lines.push(
      `- Realismus: Mit etwa 10 % Steigerung pro Woche braucht der Aufbau bis zur Zieldistanz rund ${a.weeksNeededForDistance} Wochen, es bleiben ${a.weeksLeft}. Baue so zielgerichtet auf, wie die Grenzen erlauben, und sage ehrlich in einem Satz der Begründung, dass das Ziel zum Zieltag so wohl nicht ganz erreichbar ist. Die Grenzen hebst du dafür nie auf.`
    );
  }
  // Snapshot v2: Gesamtziel und andere Sportarten. Ein v1-Snapshot ergibt genau den Abschnitt wie vor v2.
  if (snapshot.schema_version === 2) lines.push("", multiSportSection(snapshot));
  return lines.join("\n");
}
