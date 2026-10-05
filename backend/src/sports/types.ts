import { PerformanceMetricDefinition, PerformanceSource, PerformanceTestDefinition } from "./performance";
import { StepMeasure, StepTarget } from "./vocabulary";

/**
 * Alles, was eine Sportart dem Backend beibringt. Der Kern (Schemas, Prompts, Sicherheitsschicht) fragt nie
 * "welche Sportart ist das?", sondern immer die Definition: Eine neue Sportart ist eine neue Definition unter
 * modules/ plus Tests.
 */
export interface SportDefinition {
  /** Kennung, z. B. "swim": Kleinbuchstaben, Ziffern, Unterstrich, beginnt mit einem Buchstaben, 2 bis 32 Zeichen. */
  readonly id: string;
  /** Deutscher Name, z. B. "Schwimmen". */
  readonly displayName: string;
  readonly measures: readonly StepMeasure[];
  readonly targets: readonly StepTarget[];
  /**
   * Durchschnittstempo, das ein Wettkampfziel dieser Sportart haben darf (Strecke durch Zielzeit, inklusive
   * Wenden und Pausen). Schuetzt den Plan vor Tippfehlern wie "10 km in 10 Minuten". Gegenstueck in Swift:
   * `SportModule.goalSpeedRange`, beide pruefen contracts/sports.json.
   */
  readonly goalSpeed: { readonly minMetersPerSecond: number; readonly maxMetersPerSecond: number };
  /** Wie stark eine Minute dieser Sportart belastet, verglichen mit einer Minute Laufen (1,0). Gegenstueck: `SportModule.loadFactor`. */
  readonly loadFactor: number;
  /** Leistungswerte dieser Sportart; die fuer alle Sportarten stehen in `ATHLETE_METRICS`. */
  readonly performanceMetrics: readonly PerformanceMetricDefinition[];
  /** Leistungstests; jeder ermittelt Werte aus `performanceMetrics`. */
  readonly performanceTests: readonly PerformanceTestDefinition[];
  /** Wie die Sportart geplant und begrenzt wird (Planung fuer mehrere Sportarten, src/plan/multi/). */
  readonly planning: SportPlanning;
}

/** Woran die Grenzen einer Sportart gemessen werden: an der Strecke (Meter) oder an der Dauer (Minuten). */
export type LimitUnit = "meters" | "minutes";

/**
 * Die Sicherheitsgrenzen einer Sportart, alle in `SportPlanning.limitUnit`. Startwerte aus dem Trainingswissen
 * (docs/multisport-planning.md), justierbar im Betatest.
 */
export interface SportLimits {
  /** Eine Einheit ist hoechstens so viel laenger als die laengste der letzten 4 Wochen. */
  readonly sessionGrowthFactor: number;
  /** Untergrenze der Einheitengrenze, damit auch ohne Verlauf trainiert werden darf. */
  readonly minSessionCap: number;
  /** Keine Einheit ist laenger, egal wie der Verlauf aussieht. */
  readonly absoluteMaxSession: number;
  /** Die naechsten 7 Tage (bzw. die letzten 7 Tage plus heute) liegen hoechstens so weit ueber dem Wochenschnitt. */
  readonly weeklyGrowthFactor: number;
  /** Untergrenze der Wochengrenze, fuer Einsteiger ohne Verlauf. */
  readonly minWeeklyCap: number;
  /** Kleinste sinnvolle Einheit: Bleibt weniger, faellt die Einheit weg. */
  readonly minSession: number;
  /** Wiedereinstieg (lange keine Einheit dieser Sportart): hoechstens so lang, und nur locker. */
  readonly pauseSessionCap: number;
  /** Ab so vielen Tagen ohne Einheit gilt der Wiedereinstieg. */
  readonly pauseAfterDays: number;
  readonly maxSessionsPerWeek: number;
  /** Gesamtplan: eine Woche hat hoechstens so viel mehr als die letzte Woche ohne Entlastung. */
  readonly macroGrowthFactor: number;
  /** Umfaenge werden auf Vielfache davon gerundet (z. B. 50 m oder 5 Minuten). */
  readonly amountStep: number;
}

/**
 * Die Werte einer Sportart aus dem Snapshot v2 (letzte 7 Tage, Schnitt der letzten 4 Wochen). Strukturell gleich
 * `SportState` aus src/plan/snapshot.ts, hier ohne Abhaengigkeit davon.
 */
export interface SportStateValues {
  readonly sessions_last_seven_days: number;
  readonly sessions_last_four_weeks: number;
  readonly minutes_last_seven_days: number;
  readonly average_weekly_minutes: number;
  readonly meters_last_seven_days: number;
  readonly average_weekly_meters: number;
  readonly longest_session_meters: number;
  readonly longest_session_minutes: number;
  readonly days_since_last_session?: number;
}

/** Ein Leistungswert aus dem Snapshot (T2b), mit Herkunft und Datum. */
export interface PerformanceValueView {
  readonly value: number;
  readonly source: PerformanceSource;
  /** ISO-Zeitpunkt der Messung oder Schaetzung. */
  readonly measuredAt: string;
}

/** Was der Snapshot ueber die Leistung in dieser Sportart weiss. */
export interface SportPerformance {
  /** Werte dieser Sportart und die fuer alle Sportarten (Maximalpuls, Ruhepuls), nach Kennung des Werts. */
  readonly values: Readonly<Record<string, PerformanceValueView>>;
  /** Die Ziele, fuer die die App Zonen gerechnet hat (z. B. heart_rate_zone). Nur fuer sie kann die Uhr Zonen anzeigen. */
  readonly zoneTargets: readonly StepTarget[];
}

/** Was ein Modul ueber den Athleten weiss, wenn es Grenzen fuer Zielwerte setzt. */
export interface SportPlanningContext {
  readonly state: SportStateValues;
  /** Die Disziplin des Ziels, wenn diese Sportart eine ist. */
  readonly discipline?: { readonly distance_meters: number; readonly target_duration_seconds?: number };
  /** Leistungswerte und Zonen aus dem Snapshot; fehlt ohne Profil (aeltere App). */
  readonly performance?: SportPerformance;
}

/**
 * Ein Schritt einer Einheit, wie ihn die Planung fuer mehrere Sportarten ausliefert und wie ein Modul ihn fuer einen
 * Leistungstest vorgibt. Einheiten der Ziele: siehe docs/multisport-planning.md.
 */
export interface SessionStep {
  readonly name: string;
  readonly repetitions: number;
  readonly measure: "distance" | "duration";
  /** Strecke einer Wiederholung (bei measure distance), sonst `null`. */
  readonly distance_meters: number | null;
  /** Dauer einer Wiederholung (bei measure duration), sonst `null`. */
  readonly duration_seconds: number | null;
  readonly target_type: StepTarget | null;
  readonly target_value: number | null;
  /** Pause nach jeder Wiederholung. */
  readonly rest_seconds: number;
  readonly instructions: string;
  /** Kurztext fuer die Uhr, hoechstens 30 Zeichen. */
  readonly cue: string;
  readonly equipment: readonly string[];
}

/** Erlaubter Bereich eines Zielwerts. Einheit je Ziel siehe docs/multisport-planning.md (z. B. s/km, Zone 1 bis 5). */
export interface TargetRange {
  readonly min: number;
  readonly max: number;
}

/** Trainingsstand, den der Athlet zu seinem Startniveau angibt (Snapshot v2, `starting_levels`). */
export type TrainingStatus = "regular" | "short_break" | "long_break" | "beginner";

/**
 * Wie eine Sportart ein selbst angegebenes Startniveau (Wochenumfang, laengste Einheit) nutzt. Startwerte aus der
 * Praxis, justierbar im Betatest (docs/multisport-planning.md).
 */
export interface StartingLevelRules {
  /** So viel der Angabe gilt je Trainingsstand (0: die Angabe zaehlt nicht, wie bei Einsteigern). */
  readonly factors: { readonly regular: number; readonly short_break: number; readonly long_break: number };
  /** Gesamtplan: bis zum angegebenen Niveau darf eine Woche so viel mehr haben als die letzte ohne Entlastung. */
  readonly returnGrowthFactor: number;
}

export interface SportPlanning {
  readonly limitUnit: LimitUnit;
  readonly limits: SportLimits;
  readonly startingLevel: StartingLevelRules;
  /**
   * Typisches Trainingstempo ohne eigene Daten (m/s, inklusive Pausen). Damit schaetzt der Kern die Dauer einer
   * Strecke und die Dauer eines Wettkampfs, wenn der Athlet keine Zielzeit angegeben hat.
   */
  readonly typicalSpeedMetersPerSecond: number;
  /** In diesen Massen plant der Kern Schritte; ein Schritt in einem anderen Mass wird umgerechnet. */
  readonly stepMeasures: readonly ("distance" | "duration")[];
  /** Strecken eines Schritts sind Vielfache davon (Schwimmen: 50 m fuer 25- und 50-m-Becken). */
  readonly distanceStepMeters: number;
  readonly minStepMeters: number;
  readonly maxStepMeters: number;
  readonly minStepSeconds: number;
  readonly maxStepSeconds: number;
  /**
   * Die Ziele, die der Planer in Schritten verwenden darf, mit erlaubtem Bereich fuer diesen Athleten; `null`, wenn
   * das Ziel fuer ihn nicht in Frage kommt (z. B. Watt ohne bekannte Schwellenleistung).
   */
  targetRange(target: StepTarget, context: SportPlanningContext): TargetRange | null;
  /**
   * Die Schritte jedes Leistungstests (nach Kennung des Tests): Ein- und Auslaufen plus die eigentliche Testbelastung.
   * Der Server setzt sie in eine Testeinheit ein, Claude plant nur den Termin. Fehlt einer, lehnt die Registry die
   * Sportart ab.
   */
  readonly testSessions: Readonly<Record<string, readonly SessionStep[]>>;
  /** Hilfsmittel, die ein Schritt verlangen kann, mit deutschem Namen. Leer, wenn die Sportart keine kennt. */
  readonly equipment: Readonly<Record<string, string>>;
  /**
   * Koppeltraining: Diese Sportart darf am selben Tag direkt im Anschluss an eine dieser Sportarten folgen (Laufen nach
   * dem Rad). Leer: nie. Gegenstueck in Swift: `SportModule.brickAfter`, beide pruefen contracts/sports.json.
   */
  readonly brickAfter: readonly string[];
  /** Draussen und damit vom Wetter abhaengig (Gewitter, Glaette, Sturm, Hitze). Gegenstueck: `SportModule.weatherSensitive`. */
  readonly weatherSensitive: boolean;
  /**
   * Drinnen moeglich mit diesem Hilfsmittel des Athleten (Rolle, Laufband); `null`, wenn es fuer die Sportart kein Drinnen
   * gibt oder sie ohnehin drinnen stattfindet. Gegenstueck: `SportModule.indoorEquipment`.
   */
  readonly indoor: { readonly equipment: string; readonly displayName: string } | null;
  /**
   * Regeln fuer Claude, wie diese Sportart geplant wird (Deutsch, ohne Datum und ohne Zahlen des Athleten). Sie
   * stehen im festen System-Prompt der Planung fuer mehrere Sportarten.
   */
  readonly promptRules: string;
}
