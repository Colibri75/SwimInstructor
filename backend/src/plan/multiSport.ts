import { LEGACY_SPORT_ID, SPORTS } from "../sports/registry";
import { SnapshotV2 } from "./snapshot";

/**
 * Der Abschnitt fuer Snapshot v2: Gesamtziel ueber alle Sportarten, Schwerpunkte und was der Athlet in den
 * anderen Sportarten zuletzt trainiert hat. Alles aus Zahlen und Kennungen des Snapshots, Namen aus der
 * Registry, nie Freitext vom Client.
 *
 * Bis die Planung mehrere Sportarten kann (T3), plant der Server nur die Sportart von v1; die anderen gehen
 * als Belastung ein, die er beruecksichtigen soll.
 */
export function multiSportSection(snapshot: SnapshotV2): string {
  const goal = snapshot.training_goal;
  const name = (id: string) => SPORTS.get(id)?.displayName ?? id;
  const planned = name(LEGACY_SPORT_ID);
  const lines = ["Gesamtziel über alle Sportarten (in der App eingestellt):"];
  for (const discipline of goal.disciplines) {
    const time = discipline.target_duration_seconds !== undefined ? ` in ${formatDuration(discipline.target_duration_seconds)}` : "";
    lines.push(`- ${name(discipline.sport)}: ${formatDistance(discipline.distance_meters)}${time}.`);
  }
  lines.push(
    `- Am ${goal.target_date.slice(0, 10)}, noch ${goal.days_until_goal} Tage. ${goal.training_days_per_week} Trainingstage und etwa ${formatHours(goal.weekly_hours)} pro Woche.`,
    `- Schwerpunkte: ${goal.emphasis.map((entry) => `${name(entry.sport)} ${entry.percent} %`).join(", ")}.`
  );
  if (!goal.disciplines.some((discipline) => discipline.sport === LEGACY_SPORT_ID)) {
    lines.push(`- ${planned} ist keine Disziplin des Ziels: Plane ${planned} als Ausgleich und Grundlage, nicht auf das Ziel unter "goal" hin (das ist nur ein Platzhalter).`);
  }

  const others = snapshot.sports.filter((state) => state.sport !== LEGACY_SPORT_ID && (state.sessions_last_four_weeks > 0 || state.minutes_last_seven_days > 0));
  lines.push("", "Training in den anderen Sportarten:");
  if (others.length === 0) {
    lines.push("- In den letzten 4 Wochen keins.");
  } else {
    for (const state of others) {
      const since = state.days_since_last_session !== undefined ? `, zuletzt vor ${state.days_since_last_session} Tagen` : "";
      lines.push(
        `- ${name(state.sport)}: letzte 7 Tage ${state.sessions_last_seven_days} Einheiten, ${Math.round(state.minutes_last_seven_days)} min, ${formatDistance(state.meters_last_seven_days)}; im Schnitt ${Math.round(state.average_weekly_minutes)} min pro Woche${since}.`
      );
    }
  }
  const total = snapshot.total_load;
  const ratio = total.acute_chronic_ratio !== undefined ? `, Verhältnis zum Schnitt ${total.acute_chronic_ratio.toFixed(2)}` : "";
  lines.push(
    `- Gesamt über alle Sportarten: ${Math.round(total.minutes_last_seven_days)} min und Last ${Math.round(total.load_last_seven_days)} in den letzten 7 Tagen, im Schnitt ${Math.round(total.average_weekly_minutes)} min und Last ${Math.round(total.average_weekly_load)} pro Woche${ratio}.`,
    `Du planst weiterhin nur ${planned}. Berücksichtige die Belastung aus den anderen Sportarten: Nach einem langen oder harten Tag dort plane ${planned} lockerer, und liegt die Gesamtlast deutlich über dem Schnitt (Verhältnis über 1,3), steigere nicht weiter.`
  );
  return lines.join("\n");
}

function formatDistance(meters: number): string {
  return meters >= 5000 ? `${(meters / 1000).toFixed(1).replace(".", ",")} km` : `${Math.round(meters)} m`;
}

function formatDuration(seconds: number): string {
  const minutes = Math.round(seconds / 60);
  return minutes >= 120 ? `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, "0")} min` : `${minutes} min`;
}

function formatHours(hours: number): string {
  return `${String(hours).replace(".", ",")} h`;
}
