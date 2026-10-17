import { addDays, daysBetween } from "../calendar";
import { Intensity } from "../vocabulary";
import { SecondaryRace, SnapshotV2 } from "../snapshot";
import { dateText, say, Text } from "./texts";

/**
 * Nebenwettkaempfe neben dem Hauptziel. Am Tag selbst plant der Coach kein Training (der Wettkampf ist die Einheit).
 * B: kurzes Zuspitzen (die 3 Tage davor weniger Umfang und hoechstens mittel), danach 2 Tage locker. C: zaehlt wie eine
 * harte Einheit, am Tag davor und danach hoechstens mittel. Leistungstests nicht rund um einen Nebenwettkampf.
 */
export const SECONDARY_RACE_RULES = {
  b: { daysBefore: 3, beforeIntensity: "moderate", beforeAmountFactor: 0.6, daysAfter: 2, afterIntensity: "easy", testDaysBefore: 7, testDaysAfter: 2 },
  c: { daysBefore: 1, beforeIntensity: "moderate", beforeAmountFactor: 1, daysAfter: 1, afterIntensity: "moderate", testDaysBefore: 2, testDaysAfter: 1 }
} as const satisfies Record<SecondaryRace["priority"], {
  daysBefore: number;
  beforeIntensity: Intensity;
  beforeAmountFactor: number;
  daysAfter: number;
  afterIntensity: Intensity;
  testDaysBefore: number;
  testDaysAfter: number;
}>;

/** Die Nebenwettkaempfe nach Datum. */
export function secondaryRaces(snapshot: SnapshotV2): SecondaryRace[] {
  return [...(snapshot.training_goal.secondary_races ?? [])].sort((a, b) => a.date.localeCompare(b.date));
}

/** Der Nebenwettkampf am Tag `date`, sonst `undefined`. */
export function secondaryRaceOn(snapshot: SnapshotV2, date: string): SecondaryRace | undefined {
  return secondaryRaces(snapshot).find((race) => race.date === date);
}

const INTENSITY_RANK: Record<Intensity, number> = { rest: 0, easy: 1, moderate: 2, hard: 3 };

export interface SecondaryRaceRestriction {
  maxIntensity: Intensity;
  amountFactor: number;
  reason: Text;
}

/** Was ein Nebenwettkampf an einem Tag davor oder danach begrenzt (der strengste gilt), sonst `null`. */
export function secondaryRaceRestriction(snapshot: SnapshotV2, date: string): SecondaryRaceRestriction | null {
  let result: SecondaryRaceRestriction | null = null;
  for (const race of secondaryRaces(snapshot)) {
    const rules = SECONDARY_RACE_RULES[race.priority];
    const offset = daysBetween(race.date, date);
    let next: SecondaryRaceRestriction | null = null;
    if (offset < 0 && -offset <= rules.daysBefore) {
      next = { maxIntensity: rules.beforeIntensity, amountFactor: rules.beforeAmountFactor, reason: say("beforeSecondaryRace", dateText(race.date)) };
    } else if (offset > 0 && offset <= rules.daysAfter) {
      next = { maxIntensity: rules.afterIntensity, amountFactor: 1, reason: say("afterSecondaryRace", dateText(race.date)) };
    }
    if (next === null) continue;
    const stricter = INTENSITY_RANK[next.maxIntensity] - (result === null ? Infinity : INTENSITY_RANK[result.maxIntensity]);
    if (result === null || stricter < 0 || (stricter === 0 && next.amountFactor < result.amountFactor)) result = next;
  }
  return result;
}

/** Kein Leistungstest kurz vor oder nach einem Nebenwettkampf (der Tag selbst zaehlt mit). */
export function secondaryRaceTestReason(snapshot: SnapshotV2, date: string): Text | null {
  for (const race of secondaryRaces(snapshot)) {
    const rules = SECONDARY_RACE_RULES[race.priority];
    if (date >= addDays(race.date, -rules.testDaysBefore) && date <= addDays(race.date, rules.testDaysAfter)) {
      return say("testNearSecondaryRace", dateText(race.date));
    }
  }
  return null;
}
