import { SPORTS } from "../../sports/registry";
import { SportDefinition } from "../../sports/types";
import { weekdayIndex, WEEKDAYS_DE } from "../calendar";
import { AthleteProfile, PainArea, SnapshotV2, SportProfile } from "../snapshot";
import type { StepGrid } from "./steps";

/**
 * Das Athletenprofil ("Über mich" in der App): eigene Angaben zu Alter, Erfahrung, Verletzungen, Koennen, Wunschtag der
 * langen Einheit, Bahn, Alltag und Intensitaet. Die meisten Angaben lenken nur Claude (Abschnitt "Über den Athleten",
 * Leitplanke 13); verbindlich setzt der Server zwei davon durch: das Streckenraster der Bahnlaenge und die Tage mit
 * Zugang zur Bahn.
 */

const INJURY_AREA_TEXT: Record<PainArea, string> = {
  knee: "Knie",
  shin: "Schienbein",
  achilles: "Achillessehne",
  foot: "Fuß",
  hip: "Hüfte",
  back: "Rücken",
  shoulder: "Schulter",
  other: "andere Stelle"
};

const INJURY_STATUS_TEXT = {
  current: "gerade aktuell",
  recurring: "kommt immer wieder",
  past: "früher, ausgeheilt"
} as const;

const STRESS_TEXT = {
  low: "wenig Belastung durch Beruf und Familie",
  normal: "normale Belastung durch Beruf und Familie",
  high: "hohe Belastung durch Beruf oder Familie"
} as const;

const INTENSITY_TEXT = {
  easy: "lieber locker (harte Einheiten nur, wo das Ziel sie braucht)",
  balanced: "ausgewogen",
  intense: "lieber öfter knackig (mittlere und harte Anteile innerhalb der Grenzen ausschöpfen)"
} as const;

/** Die Angaben des Athleten zu einer Sportart, `undefined` ohne. */
export function sportProfile(snapshot: SnapshotV2, sportId: string): SportProfile | undefined {
  return snapshot.athlete_profile?.sports?.find((entry) => entry.sport === sportId);
}

/**
 * Raster fuer Strecken an der Bahn des Athleten: Ist seine Bahn kuerzer als das Raster der Sportart und geht darin auf
 * (25 m bei einem 50-m-Raster), sind Vielfache der Bahnlaenge erlaubt. Sonst (keine Angabe, 50-m-Bahn, Freiwasser) das
 * Raster der Sportart.
 */
export function lapGrid(snapshot: SnapshotV2, sport: SportDefinition, openWater: boolean): StepGrid | undefined {
  const lap = sportProfile(snapshot, sport.id)?.lap_length_meters;
  const planning = sport.planning;
  if (openWater || lap === undefined || planning.pool === null) return undefined;
  if (lap >= planning.distanceStepMeters || planning.distanceStepMeters % lap !== 0) return undefined;
  return { step: lap, min: Math.min(lap, planning.minStepMeters) };
}

/** An diesem Tag kommt der Athlet nicht an seine Bahn (laut Profil); ohne Angabe immer ja. */
export function poolClosed(snapshot: SnapshotV2, sport: SportDefinition, date: string): boolean {
  const days = sportProfile(snapshot, sport.id)?.pool_weekdays;
  return sport.planning.pool !== null && days !== undefined && !days.includes(weekdayIndex(date) + 1);
}

const weekdayList = (days: readonly number[]) => [...days].sort((a, b) => a - b).map((day) => WEEKDAYS_DE[day - 1]).join(", ");

function sportLine(sport: SportDefinition, entry: SportProfile): string | null {
  const parts: string[] = [];
  const planning = sport.planning;
  if (entry.skills !== undefined && planning.skills.length > 0) {
    const can = planning.skills.filter((skill) => entry.skills?.includes(skill.id)).map((skill) => skill.displayName);
    const cannot = planning.skills.filter((skill) => !entry.skills?.includes(skill.id)).map((skill) => skill.displayName);
    parts.push(`kann ${can.length > 0 ? can.join(", ") : "nichts davon"}${cannot.length > 0 ? `; kann nicht: ${cannot.join(", ")}` : ""}`);
  }
  if (planning.pool !== null && entry.lap_length_meters !== undefined) {
    const grid = entry.lap_length_meters < planning.distanceStepMeters && planning.distanceStepMeters % entry.lap_length_meters === 0;
    parts.push(`${planning.pool.displayName} ${entry.lap_length_meters} m${grid ? ` (Strecken als Vielfache von ${entry.lap_length_meters} m erlaubt)` : ""}`);
  }
  if (planning.pool !== null && entry.pool_weekdays !== undefined && entry.pool_weekdays.length < 7) {
    const venue = planning.openWater !== null ? ` (an den anderen Tagen nur ${planning.openWater.displayName}, wenn erlaubt, sonst keine Einheit ${sport.displayName})` : "";
    parts.push(`${planning.pool.displayName} nur ${weekdayList(entry.pool_weekdays)}${venue}`);
  }
  if (entry.long_session_weekday !== undefined) parts.push(`lange Einheit am liebsten ${WEEKDAYS_DE[entry.long_session_weekday - 1]}`);
  return parts.length === 0 ? null : `- ${sport.displayName}: ${parts.join(". ")}.`;
}

/** Die Zeilen des Abschnitts "Über den Athleten"; leer ohne Angaben. */
export function athleteProfileLines(snapshot: SnapshotV2): string[] {
  const profile: AthleteProfile | undefined = snapshot.athlete_profile;
  if (profile === undefined) return [];
  const lines: string[] = [];
  const person = [
    ...(profile.age !== undefined ? [`${profile.age} Jahre alt`] : []),
    ...(profile.training_years !== undefined ? [profile.training_years === 0 ? "neu im Ausdauersport" : `seit ${profile.training_years} ${profile.training_years === 1 ? "Jahr" : "Jahren"} im Ausdauersport`] : [])
  ];
  if (person.length > 0) lines.push(`- ${person.join(", ")}.`);
  const injuries = profile.injuries ?? [];
  if (injuries.length > 0) {
    lines.push(`- Verletzungen: ${injuries.map((injury) => `${INJURY_AREA_TEXT[injury.area]} (${INJURY_STATUS_TEXT[injury.status]})`).join(", ")}.`);
  }
  const planned = new Set(snapshot.training_goal.emphasis.filter((entry) => entry.percent > 0).map((entry) => entry.sport));
  for (const entry of profile.sports ?? []) {
    const sport = SPORTS.get(entry.sport);
    if (sport === undefined || !planned.has(sport.id)) continue;
    const line = sportLine(sport, entry);
    if (line !== null) lines.push(line);
  }
  const everyday = [
    ...(profile.life_stress !== undefined ? [STRESS_TEXT[profile.life_stress]] : []),
    ...(profile.shift_work === true ? ["Schichtarbeit"] : [])
  ];
  if (everyday.length > 0) lines.push(`- Alltag: ${everyday.join(", ")}.`);
  if (profile.intensity_preference !== undefined) lines.push(`- Intensität: ${INTENSITY_TEXT[profile.intensity_preference]}.`);
  return lines.length === 0 ? [] : ["Über den Athleten (eigene Angaben, siehe Leitplanke 13):", ...lines];
}

/** Sportarten, deren Bahn an einem der Tage nicht erreichbar ist, als Zeile fuer die Nutzernachricht des Tages. */
export function poolClosedLines(snapshot: SnapshotV2, date: string): string[] {
  return SPORTS.sports
    .filter((sport) => snapshot.training_goal.emphasis.some((entry) => entry.sport === sport.id && entry.percent > 0) && poolClosed(snapshot, sport, date))
    .map((sport) => {
      const pool = sport.planning.pool?.displayName ?? "";
      const venue = sport.planning.openWater !== null ? `nur im ${sport.planning.openWater.displayName} (open_water true), wenn erlaubt, sonst` : "";
      return `- Heute kein ${pool} (laut Athlet): ${sport.displayName} ${venue} nicht.`.replace(/ +/g, " ");
    });
}
