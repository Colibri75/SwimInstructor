# Athleten-Zustands-Snapshot (Schema v1 und v2)

Der Snapshot fasst Workouts, Erholungswerte und Ziel in einem kompakten JSON zusammen. Die App
berechnet ihn lokal (`AthleteStateCalculator` in `SwimInstructorCore`) und schickt ihn ans
Backend, das ihn an Claude weitergibt. Das Schema ist ab M3 stabil: Felder werden nur ergänzt,
nie umbenannt oder entfernt. Bei einem inkompatiblen Umbau steigt `schema_version`.

Dass die Schlüssel stabil bleiben, prüft `testSnapshotJSONSchemaKeysAreStable`.

## Format

- Schlüssel in `snake_case`, Datumswerte als ISO 8601 (UTC).
- Optionale Felder **fehlen**, wenn es keinen Wert gibt (z. B. keine Vergleichsdaten). Sie sind nie `null`.
- Zahlen sind auf eine Nachkommastelle gerundet.

## Beispiel (Szenario "guter Fortschritt")

```json
{
  "flags": [],
  "generated_at": "2026-09-30T12:00:00Z",
  "goal": {
    "days_until_goal": 277,
    "distance_meters": 3800,
    "target_date": "2027-07-04T10:00:00Z",
    "target_duration_seconds": 3600,
    "target_pace_seconds_per_hundred_meters": 94.7
  },
  "load": {
    "days_since_last_hard_session": 1,
    "days_since_last_workout": 1
  },
  "pace": {
    "gap_to_target_seconds_per_hundred_meters": 25.3,
    "previous_pace_seconds_per_hundred_meters": 160.0,
    "recent_pace_seconds_per_hundred_meters": 120.0,
    "trend_seconds_per_hundred_meters": -40.0
  },
  "recovery": {
    "hrv_deviation_percent": 0.0,
    "recent_average_sleep_hours": 7.5,
    "resting_heart_rate_deviation_bpm": 0.0,
    "status": "good",
    "warning_signals": []
  },
  "schema_version": 1,
  "volume": {
    "average_weekly_meters": 3350.0,
    "last_seven_days_meters": 3500.0,
    "longest_session_meters": 2000.0,
    "sessions_last_four_weeks": 8,
    "sessions_last_seven_days": 2,
    "weekly_change_percent": 6.1
  }
}
```

## Felder

| Feld | Typ | Bedeutung |
|---|---|---|
| `schema_version` | Int | Aktuell `1` |
| `generated_at` | Datum | Zeitpunkt der Berechnung |
| `flags` | [String] | Warnhinweise, siehe unten |
| **goal** | | |
| `distance_meters` | Zahl | Zieldistanz (3800) |
| `target_duration_seconds` | Zahl | Zielzeit (3600) |
| `target_pace_seconds_per_hundred_meters` | Zahl | Zielpace, Zielzeit geteilt durch Zieldistanz in 100 m |
| `target_date` | Datum | Zieldatum (04.07.2027), als Mittag gespeichert, damit der Kalendertag in jeder Zeitzone gleich bleibt |
| `days_until_goal` | Int | Kalendertage bis zum Ziel, mindestens 0 |
| **volume** | | |
| `last_seven_days_meters` | Zahl | Distanz der letzten 7 Tage |
| `average_weekly_meters` | Zahl | Wochenschnitt der letzten 4 Wochen |
| `weekly_change_percent` | Zahl? | Letzte 7 Tage gegenüber der Woche davor; fehlt, wenn die Woche davor 0 m hatte |
| `sessions_last_seven_days` | Int | Einheiten der letzten 7 Tage |
| `sessions_last_four_weeks` | Int | Einheiten der letzten 4 Wochen |
| `longest_session_meters` | Zahl | Längste Einheit der letzten 4 Wochen (0, wenn keine) |
| **pace** (Sekunden pro 100 m) | | |
| `recent_pace_seconds_per_hundred_meters` | Zahl? | Pace der letzten 4 Wochen |
| `previous_pace_seconds_per_hundred_meters` | Zahl? | Pace der 4 Wochen davor (Woche 5 bis 8) |
| `trend_seconds_per_hundred_meters` | Zahl? | Recent minus previous; **negativ = schneller geworden** |
| `gap_to_target_seconds_per_hundred_meters` | Zahl? | Recent minus Zielpace; **positiv = noch zu langsam fürs Ziel** |
| **load** | | |
| `days_since_last_workout` | Int? | Kalendertage seit der letzten Einheit; fehlt ohne Einheiten |
| `days_since_last_hard_session` | Int? | Kalendertage seit der letzten harten Einheit |
| **recovery** | | |
| `status` | String | `good`, `moderate`, `poor` oder `unknown` |
| `resting_heart_rate_deviation_bpm` | Zahl? | Ruhepuls der letzten 3 Tage minus Baseline; positiv ist schlechter |
| `hrv_deviation_percent` | Zahl? | HRV der letzten 3 Tage gegenüber Baseline in %; negativ ist schlechter |
| `recent_average_sleep_hours` | Zahl? | Durchschnittlicher Schlaf der letzten 3 Tage |
| `warning_signals` | [String] | `elevated_resting_heart_rate`, `low_heart_rate_variability`, `short_sleep` |

## Definitionen und Schwellenwerte

Alle Zeitfenster zählen in Kalendertagen ab heute (Tag 0). Die Schwellen stehen in
`AthleteStateConfiguration` und sind Startwerte, die sich mit echten Daten justieren lassen.

- **Zeitfenster:** letzte 7 Tage = Tag 0 bis 6, Woche davor = Tag 7 bis 13, letzte 4 Wochen = Tag 0 bis 27, 4 Wochen davor = Tag 28 bis 55.
- **Pace:** gewichtet, also Gesamtzeit geteilt durch Gesamtdistanz (in 100 m), nur über Einheiten mit Distanz.
- **Harte Einheit:** mindestens 2000 m **oder** durchschnittliche Herzfrequenz von mindestens 150 bpm.
- **Duplikate:** Zwei Workouts, die sich zu mindestens der Hälfte des kürzeren überlappen, zählen als eine Einheit (z. B. Apple Watch plus Drittanbieter-App). Es bleibt das vollständigere, die Distanz wiegt am schwersten.
- **Erholung:** Baseline = Mittel der Tage 3 bis 30 (mindestens 5 Tageswerte pro Größe), aktuell = Mittel der Tage 0 bis 2.
  Signale: Ruhepuls mindestens 5 bpm über Baseline, HRV mindestens 15 % unter Baseline, Schlaf unter 6 Stunden.
  Status: kein Signal = `good`, ein Signal = `moderate`, zwei oder mehr = `poor`, keine Daten = `unknown`.

### Flags

| Flag | Bedingung |
|---|---|
| `training_pause` | Letzte Einheit mindestens 14 Tage her oder gar keine Einheit |
| `volume_spike` | Letzte 7 Tage mehr als das 1,3-Fache des Wochenschnitts der Tage 7 bis 27 (der Schnitt muss über 0 liegen) |
| `recovery_poor` | Erholungsstatus `poor` |
| `overreaching_risk` | Erholungsstatus `poor` und mindestens 3 Einheiten in den letzten 7 Tagen |
| `goal_within_four_weeks` | Höchstens 28 Tage bis zum Zieldatum |

## Grenzen

- Die Dauer eines Workouts ist die von Health gemeldete Dauer. Pausen zwischen den Bahnen können darin enthalten sein, dann liegt die Pace über dem echten Schwimmtempo. Eine Pace aus reiner Schwimmzeit kommt später, wenn die Bahnzeiten (Lap-Events) ausgewertet werden.
- Die Erholungswerte holt seit M6 der `SnapshotBuilder` aus Health (`HealthKitDailyVitalsRepository`): Ruhepuls und HRV als Tagesmittel, Schlaf als Summe der Schlafphasen pro Nacht (ohne "im Bett" und "wach"), gezählt zum Aufwachtag. Überlappende Abschnitte mehrerer Quellen zählen nur einmal.

## Schema v2 (Triathlon-Umbau, T2)

v2 ist v1 plus drei Blöcke; alle v1-Felder bleiben unverändert und beziehen sich weiter aufs Schwimmen. Die App
schickt v2, sobald ein Gesamtziel eingestellt ist (immer, seit T2). Vollständiges Beispiel und Prüfung beider Seiten:
[`contracts/wire/snapshot-v2.json`](../contracts/wire/snapshot-v2.json).

- `training_goal`: das Gesamtziel aus dem Ziel-Assistenten. `template` (Vorlage, fehlt bei eigenem Ziel),
  `target_date`, `days_until_goal`, `training_days_per_week` (1 bis 7), `weekly_hours` (0,5 bis 40),
  `disciplines` (Sportart, `distance_meters`, optional `target_duration_seconds`) und `emphasis` (Sportart, `percent`,
  zusammen genau 100; jede Disziplin braucht mehr als 0 %). Das Zieltempo jeder Disziplin muss im Fenster
  `goal_speed` des Sport-Moduls liegen (`contracts/sports.json`).
- `sports`: je Sportart mit Training in den letzten 4 Wochen oder mit Schwerpunkt/Disziplin: Einheiten, Minuten
  und Meter der letzten 7 Tage, Wochenschnitt der letzten 4 Wochen, längste Einheit (Meter und Minuten), Last
  (`TrainingLoadCalculator`: TRIMP mit Puls, sonst Minuten, mal Faktor des Moduls) und Tage seit der letzten Einheit.
- `total_load`: Minuten und Last über alle Sportarten (7 Tage und Wochenschnitt) und `acute_chronic_ratio`
  (7-Tage-Last durch Wochenschnitt; fehlt ohne Vergleichswert). Nur ein Hinweis für die Planung, keine harte Grenze.

Der v1-Teil (`goal` usw.) bleibt bis T3 das Schwimmziel: die Schwimm-Disziplin des Gesamtziels (ohne Zielzeit mit
2:00 pro 100 m), ohne Schwimm-Disziplin ein Platzhalter (1500 m in 45 Minuten), den der Server dann nur als Ausgleich
nimmt.

**Verträglichkeit:**

- Der Server nimmt v1 und v2 an. Ein v1-Snapshot ergibt Zeichen für Zeichen dieselben Prompts wie vor v2
  (Golden-Test `backend/test/golden/v1Prompts.test.ts`). `trainingGoalOf` und `sportStatesOf` liefern die v2-Sicht
  auch für v1.
- Kennt der Server v2 noch nicht (400 auf `snapshot.schema_version`), schickt die App dieselbe Anfrage einmal mit dem
  v1-Teil (`PlanAPIClient.postSnapshot`).
