/**
 * Alle Saetze der Sicherheitsschicht, je Sprache eine Datei (de.ts, en.ts, ...). TypeScript prueft, dass jede Sprache
 * jeden Satz hat. Eingesetzte Werte sind schon in der Sprache geschrieben: Sportarten, Tage, Gruende; Mengen wie
 * "2500 m" oder "45 min" sind in allen Sprachen gleich. Deutsch ist das Original (Kommentar je Satz).
 */
export interface SafetyCatalog {
  // --- Woerter ---
  /** Sportarten nach Kennung (swim, bike, run). */
  sports: Record<string, string>;
  /** Kraft und Mobilitaet (strength, mobility). */
  extras: Record<string, string>;
  /** Hilfsmittel beim Schwimmen (pull_buoy, ...). */
  equipment: Record<string, string>;
  /** Drinnen und Freiwasser (indoor_trainer, treadmill, open_water). */
  venues: Record<string, string>;
  /** Leistungstests nach Kennung. */
  tests: Record<string, string>;
  /** easy, moderate, hard; Deutsch bleibt bei der Kennung ("moderate"). */
  intensities: Record<string, string>;
  /** "Montag, 06.10." */
  day(iso: string): string;
  /** "06.10." */
  date(iso: string): string;
  /** "Woche ab 06.10." */
  week(iso: string): string;
  /** "A oder B", "A und B", "A, B" */
  list(items: string[], kind: "or" | "and" | "plain"): string;
  /** "Montag, 06.10.: text" */
  onDay(day: string, text: string): string;

  // --- Hinweis an der Begruendung ---
  /** "Hinweis: Zur Sicherheit angepasst (a; b; c; und 2 weitere)." */
  safetyNote(first: string[], more: number): string;
  /** "Hinweis: Zur Sicherheit an 3 Stellen angepasst, die Wochen zeigen die geprüften Umfänge." */
  macroNote(count: number): string;
  /** "Heute ist Ruhe angesagt: Erholung schlecht." */
  restToday(reason: string): string;
  /** "Heute ist Ruhe angesagt: Die geplanten Einheiten passen heute nicht in die Grenzen." */
  restNothingFits(): string;

  // --- Wochen- und Tagesplan ---
  /** "3 fehlende Tage als Ruhetag ergänzt (Montag, 06.10., ...)" */
  missingDays(count: number, days: string): string;
  /** "keine Zeit, als Ruhetag gesetzt" */
  noTimeRest(): string;
  /** "laut Kalender keine Zeit, als Ruhetag gesetzt" */
  calendarNoTimeRest(): string;
  /** "Ruhetag laut Wochenraster" (auch als Grund) */
  scheduleRest(): string;
  /** "laut Wochenraster nur Laufen, andere Sportarten gestrichen" */
  scheduleOnly(sport: string): string;
  /** "auf 2 Einheiten gekürzt" */
  sessionsCut(count: number): string;
  /** "Auf 2 Einheiten gekürzt" (Tagesplan, ohne Tag davor) */
  sessionsCutToday(count: number): string;
  /** "Einheiten von Sportarten ohne Schwerpunkt entfernt (Laufen)" */
  unplannedSessions(sports: string): string;
  /** "Tagesumfang von 120 min auf höchstens 90 min gekürzt" + " (freie Zeit laut Kalender)" */
  dayCapped(from: number, to: number, calendar: boolean): string;
  /** 'nur eine harte Einheit am Tag, die anderen auf "moderate" gesenkt' */
  oneHardPerDay(): string;
  /** 'Nur eine harte Einheit am Tag, die andere auf "moderate" gesenkt' (Tagesplan) */
  oneHardToday(): string;
  /** "Laufen: Wochenumfang von 200 min auf höchstens 150 min gekürzt" */
  weeklyCut(sport: string, from: string, to: string): string;
  /** "als Ruhetag gesetzt (höchstens 5 Trainingstage)" */
  restDaySet(reason: string): string;
  /** "Gesamtumfang von 600 min auf höchstens 480 min gekürzt (Wochenstunden des Ziels)" */
  totalCut(from: number, to: number): string;
  /** "Laufen gestrichen (Grund)" */
  dropped(sport: string, reason: string): string;
  /** 'Laufen auf "easy" gesenkt (Grund)' */
  lowered(sport: string, intensity: string, reason: string): string;
  /** "Laufen von 60 min auf 45 min gekürzt (Grund)" */
  cut(sport: string, from: string, to: string, reason: string): string;
  /** "Laufen als eigene Einheit (Koppeltraining nur direkt nach Radfahren)"; ohne Sportart davor "keiner Sportart" */
  brickSeparate(sport: string, after: string): string;
  /** "Laufen draußen (kein Laufband angegeben)"; ohne `venue` "(drinnen gibt es nicht)" */
  outdoor(sport: string, venue: string): string;
  /** "Gewitter angesagt, Laufen drinnen (Laufband)" */
  indoorForWeather(weather: string, sport: string, venue: string): string;
  /** "Gewitter angesagt: Laufen drinnen (Laufband)" (Tagesplan) */
  indoorForWeatherToday(weather: string, sport: string, venue: string): string;
  /** "Schwimmen im Becken (Freiwasser gibt es nicht)" / "(kein Zugang zu Freiwasser angegeben)" */
  pool(sport: string, noOpenWater: boolean): string;
  /** "Gewitter angesagt, Schwimmen im Becken" */
  poolForWeather(weather: string, sport: string): string;
  /** "Gewitter angesagt: Schwimmen im Becken" (Tagesplan) */
  poolForWeatherToday(weather: string, sport: string): string;
  /** "Schwimmen im Freiwasser (Ziel im Freiwasser)" */
  openWaterForRace(sport: string): string;
  /** "kein Krafttraining in den letzten 10 Tagen vor dem Ziel" */
  noStrengthBeforeGoal(days: number): string;
  /** "kein Krafttraining (Grund)" */
  noStrength(reason: string): string;
  /** "kein Krafttraining am Tag vor einer harten Einheit" */
  noStrengthBeforeHard(): string;
  /** "Kraft gestrichen (höchstens 2-mal pro Woche)" */
  extraMaxPerWeek(extra: string, count: number): string;
  /** "Kraft gestrichen (Tageszeit ausgeschöpft)" */
  extraNoTime(extra: string): string;
  /** "Laufen locker (Wiedereinstieg nach Pause)" */
  easyAfterPause(sport: string): string;
  /** "Laufen von 15 min auf 20 min angehoben (kleinste sinnvolle Einheit)" */
  raised(sport: string, from: string, to: string): string;
  /** "Laufen unter 20 min gestrichen" */
  belowMinimum(sport: string, minimum: string): string;
  /** "kein Leistungstest Laufen (Grund), lockere Einheit statt dessen" */
  noTest(sport: string, reason: string): string;
  /** "Kein Leistungstest Laufen heute (Grund), lockere Einheit statt dessen" (Tagesplan) */
  noTestToday(sport: string, reason: string): string;
  /** 'harte Einheit auf "moderate" gesenkt (Grund)' */
  hardLowered(reason: string): string;
  /** "Leistungstest Laufen auf Donnerstag, 09.10. verlegt (Grund)" */
  testMoved(sport: string, day: string, reason: string): string;
  /** "Ruhetag erzwungen (Grund)" */
  forcedRest(reason: string): string;
  /** "Ruhetag erzwungen: Grund" (Tagesplan) */
  forcedRestToday(reason: string): string;
  /** "… und 3 weitere Korrekturen" */
  moreCorrections(count: number): string;

  // --- Gruende im Wochenplan ---
  /** "höchstens 3 Einheiten pro Woche" */
  maxSessionsPerWeek(count: number): string;
  /** "höchstens 5 Trainingstage" */
  maxTrainingDays(count: number): string;
  /** "mindestens ein Ruhetag pro Woche" */
  minOneRestDay(): string;
  /** "nicht an zwei Tagen nacheinander" */
  notTwoDaysInRow(): string;
  /** "höchstens 2 harte Tage" */
  maxHardDays(count: number): string;
  /** "in 7 Tagen höchstens 150 min, davon schon 120 min" */
  rollingWindow(cap: string, used: string): string;
  /** "Grenze pro Einheit" */
  sessionCap(): string;
  /** "Grenze für heute" */
  todayCap(): string;
  /** "etwa 80 % der Woche locker" */
  easyShare(percent: number): string;
  /** "Leistungstests sind abgeschaltet" */
  testsOff(): string;
  /** "höchstens ein Test pro Tag" */
  oneTestPerDay(): string;
  /** "höchstens ein Test je Sportart pro Woche" */
  oneTestPerSport(): string;
  /** "passt nicht" */
  doesNotFit(): string;
  /** "Wiedereinstieg nach Pause" */
  reentry(): string;

  // --- Nur Tagesplan ---
  /** "Kraft und Mobilität heute gestrichen (nicht vorgesehen)" */
  extrasNotPlanned(extras: string): string;
  /** "Hilfsmittel entfernt, die du nicht hast: Flossen" */
  equipmentRemoved(items: string): string;
  /** "Zielwerte an die Grenzen für dich und die Intensität angepasst" */
  targetsAdjusted(): string;
  /** "Laufen: auf 12 Schritte gekürzt" */
  stepsCut(sport: string, count: number): string;
  /** "Laufen: Einheit ohne Schritte entfernt" */
  noSteps(sport: string): string;
  /** 'Laufen: Intensität von "hard" auf "easy" gesenkt (Gründe)' */
  intensityLowered(sport: string, from: string, to: string, reasons: string): string;
  /** "zu wenig sicherer Restumfang" */
  tooLittleLeft(): string;
  /** "Laufen: Umfang von 60 min auf 45 min gekürzt (Grenze für heute: 45 min)" */
  amountCutToday(sport: string, from: string, to: string, cap: string): string;

  // --- Gesamtplan ---
  /** "als Entlastungswoche gesetzt (spätestens nach 3 Belastungswochen)" */
  deloadSet(weeks: number): string;
  /** "Laufen von 200 min auf 150 min begrenzt (Grund)" */
  capped(sport: string, from: string, to: string, reason: string): string;
  /** "Grenze für die erste Woche" */
  firstWeekCap(): string;
  /** "Entlastungswoche" */
  deloadWeek(): string;
  /** "höchstens 10 % mehr als die letzte Woche ohne Entlastung" */
  growth(percent: number): string;
  /** "Rückkehr zum Niveau vor der Pause: höchstens 20 % mehr als die letzte Woche ohne Entlastung" */
  returnGrowth(percent: number): string;
  /** "Zuspitzen" */
  taper(): string;
  /** "Zielwoche" */
  goalWeek(): string;
  /** "Laufen mit 3 statt 2 Einheiten (beim Zuspitzen bleibt die Zahl der Einheiten)" */
  taperSessions(sport: string, kept: number, requested: number): string;
  /** "2 fehlende Wochen mit dem Umfang der Vorwoche ergänzt" */
  missingWeeks(count: number): string;
  /** "Sportarten ohne Schwerpunkt entfernt: Laufen" */
  unplannedSports(sports: string): string;
  /** "… und 3 weitere Korrekturen am Umfang" */
  moreVolumeCorrections(count: number): string;

  // --- Grenzen fuer einen Tag ---
  /** "Erholungswerte schlecht bei hoher Belastung (Übertrainingsrisiko)" */
  overreaching(): string;
  /** "Erholung schlecht" */
  recoveryPoor(): string;
  /** "Erholung mäßig" */
  recoveryModerate(): string;
  /** "gestern oder heute schon eine harte Einheit" */
  hardRecently(): string;
  /** "schon 2 harte Tage in den letzten 7 Tagen" */
  hardDaysRecently(count: number): string;
  /** "laut Wochenraster heute nur Laufen" */
  fixedSportToday(sport: string): string;
  /** "Grund: Pause bis 08.10." */
  painPause(pain: string, until: string): string;
  /** "Wochenumfang ausgeschöpft" */
  weekExhausted(): string;
  /** "zu wenig sicherer Umfang" */
  tooLittleSafe(): string;
  /** "deutliche Beschwerden (Knie) nach Laufen am 04.10."; Stufe 1 leicht, 2 deutlich, 3 stark; `area` leer ohne Angabe */
  pain(level: number, area: string, sport: string, date: string): string;
  /** Koerperstellen der Beschwerden (knee, shin, ...). */
  painAreas: Record<string, string>;
  /** "kein Test in den letzten 14 Tagen vor dem Ziel" */
  testBlackout(days: number): string;

  // --- Wetter ---
  /** "Gewitter angesagt" */
  thunderstorm(): string;
  /** "Sturm angesagt (bis 70 km/h)" */
  storm(kmh: number): string;
  /** "Starkregen angesagt (15 mm)" */
  heavyRain(mm: number): string;
  /** "Glätte möglich" */
  ice(): string;
  /** "zu kalt fürs Freiwasser (höchstens 14 °C)" */
  tooColdForOpenWater(celsius: number): string;

  // --- Leistungstests ---
  /** "kein Test für diese Sportart" */
  noTestForSport(): string;
  /** "CSS-Test: keine Vollbelastung (Grund)" */
  noMaxEffort(test: string, reason: string): string;
  /** 'höchstens "moderate"' */
  atMost(intensity: string): string;
  /** "CSS-Test: längste Einheit der letzten 4 Wochen unter 20 min" */
  longestTooShort(test: string, minutes: number): string;
  /** "CSS-Test: Testeinheit (2000 m) über der Grenze (1500 m)" */
  testOverAmount(test: string, amount: string, cap: string): string;
  /** "CSS-Test: Testeinheit (50 min) über der Tagesgrenze (40 min)" */
  testOverMinutes(test: string, minutes: number, cap: number): string;

  // --- Wettkampftag ---
  /** "Laufen: fehlte im Plan, mit geschätzter Zeit ergänzt" */
  raceMissing(sport: string): string;
  /** "Laufen: Zielzeit 30 min unplausibel, 45 min angenommen" */
  raceImplausible(sport: string, target: number, estimate: number): string;
  /** "Disziplinen ohne Bezug zum Ziel entfernt (Laufen)" */
  raceForeign(sports: string): string;
  /** "Pacing-Ziele an die Grenzen für dich angepasst" */
  racePacing(): string;
  /** "Schwimmen: keine Verpflegung während der Disziplin" */
  raceNoFuel(sport: string): string;
  /** "Verpflegung auf höchstens 90 g Kohlenhydrate, 800 ml Flüssigkeit und 1000 mg Natrium pro Stunde begrenzt" */
  raceFuel(carbs: number, fluid: number, sodium: number): string;
}

/** Datum mit Intl fuer die Sprachen ausser Deutsch (Tag und Monat nach Art der Sprache). */
export function intlDate(locale: string, iso: string, weekday: boolean): string {
  const date = new Date(`${iso.slice(0, 10)}T12:00:00Z`);
  return new Intl.DateTimeFormat(locale, { ...(weekday ? { weekday: "short" as const } : {}), day: "numeric", month: "numeric", timeZone: "UTC" }).format(date);
}

/** Aufzaehlung mit Intl ("A or B", "A, B and C"); `plain` mit Komma. */
export function intlList(locale: string, items: readonly string[], kind: "or" | "and" | "plain", plainSeparator = ", "): string {
  if (kind === "plain") return items.join(plainSeparator);
  return new Intl.ListFormat(locale, { type: kind === "or" ? "disjunction" : "conjunction" }).format(items);
}
