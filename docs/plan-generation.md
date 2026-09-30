# Plan-Erzeugung (`POST /v1/plan/today`)

Die App schickt den Zustands-Snapshot (siehe [AthleteStateSnapshot.md](AthleteStateSnapshot.md)),
der Server lässt Claude daraus einen Tagesplan schreiben, prüft ihn mit einer Sicherheitsschicht
und liefert ihn zurück. Fällt Claude aus, bekommt die App den letzten gültigen Plan.

## Ablauf

```
App ──POST {snapshot}──▶ Server
                          1. Snapshot prüfen (Schema, Wertebereiche, unbekannte Felder verwerfen)
                          2. Gleicher Zustand heute schon geplant?  ──ja──▶ gespeicherten Plan liefern (source: cache)
                          3. Aufrufbudget frei und API-Key da?      ──nein─▶ Fallback
                          4. Claude aufrufen (fester System-Prompt, strukturierte JSON-Ausgabe,
                             dazu die berechneten Grenzen für heute)
                          5. Antwort gegen das Plan-Schema prüfen   ──Fehler─▶ Fallback
                          6. Sicherheitsschicht: korrigieren oder blocken   ──blockiert─▶ Fallback
                          7. Plan speichern, liefern (source: claude)

Fallback = letzter gespeicherter Plan, vorher erneut durch die Sicherheitsschicht gegen den
heutigen Zustand geprüft (source: fallback). Gibt es keinen, antwortet der Server mit 503.
```

## Anfrage und Antwort

Anfrage: `Authorization: Bearer <Token>` und als Body `{"snapshot": { ... }}` (das JSON aus
`AthleteStateSnapshot`). Ungültige Snapshots lehnt der Server mit `400` ab. Unbekannte Felder
werden verworfen und erreichen Claude nie.

Antwort `200`:

```json
{
  "source": "claude",
  "date": "2026-09-30",
  "generated_at": "2026-09-30T10:00:00.000Z",
  "stale": false,
  "adjustments": ["Umfang von 4000 m auf 2400 m gekürzt (Grenze für heute: 2400 m)"],
  "plan": {
    "session_type": "endurance",
    "intensity": "moderate",
    "rationale": "…",
    "total_distance_meters": 1600,
    "estimated_duration_minutes": 45,
    "sets": [
      {
        "name": "Hauptsatz",
        "repetitions": 6,
        "distance_meters": 200,
        "target_pace_seconds_per_hundred_meters": 140,
        "rest_seconds": 30,
        "instructions": "gleichmäßig"
      }
    ],
    "coach_notes": ["Auf lockere Atmung achten."]
  }
}
```

| Feld | Bedeutung |
|---|---|
| `source` | `claude` frisch erzeugt, `cache` heute schon für denselben Zustand erzeugt, `fallback` letzter gültiger Plan |
| `date` | Tag, für den der Plan erstellt wurde |
| `stale` | `true`, wenn der Plan nicht von heute ist (nur bei `fallback`) |
| `fallback_reason` | Nur bei `fallback`, warum Claude nicht geantwortet hat (siehe unten) |
| `adjustments` | Korrekturen der Sicherheitsschicht auf Deutsch, die App kann sie anzeigen |
| `plan.session_type` | `rest`, `recovery`, `technique`, `endurance`, `threshold`, `intervals`, `test` |
| `plan.intensity` | `rest`, `easy`, `moderate`, `hard` |

Ein Ruhetag hat `session_type: "rest"`, keine `sets` und `total_distance_meters: 0`.

Fehlerantworten: `400 invalid_request` (mit `details` je fehlerhaftem Feld), `401 unauthorized`,
`503 plan_unavailable` (mit `reason`, wenn Claude ausfällt und noch kein Plan existiert).

### `fallback_reason`

| Wert | Bedeutung |
|---|---|
| `unreachable` / `timeout` | Claude war nicht erreichbar oder zu langsam (Zeitlimit 75 s) |
| `rate_limited` / `upstream_error` | Claude meldete Limit (429) oder Serverfehler (5xx, 529) |
| `refusal` | Claudes Sicherheitsklassifikatoren haben abgelehnt (und auch der Server-Fallback) |
| `truncated` / `empty_response` / `invalid_json` / `schema_invalid` | Antwort unbrauchbar |
| `sanity_blocked` | Der Plan war so kaputt, dass die Sicherheitsschicht ihn verworfen hat |
| `budget_exceeded` | Aufrufbudget erschöpft (Kostenbremse, siehe unten) |
| `not_configured` | Kein `ANTHROPIC_API_KEY` gesetzt |
| `auth` / `bad_request` / `unknown` | Konfigurations- oder Programmfehler, steht als `error` im Server-Log |

## Sicherheitsschicht

Reiner Code ohne Netzwerk (`backend/src/plan/sanity.ts`). Sie korrigiert deterministisch und
schreibt jede Korrektur in `adjustments`. Die Schwellen stehen in `DEFAULT_LIMITS`.

**Zwei Schutzebenen mit denselben Zahlen.** `dailyLimits` berechnet aus dem Zustand die Grenzen für
heute: Umfang, höchste Intensität, schnellste Zielpace oder einen Pflicht-Ruhetag. Diese Grenzen gehen
**vorher** als verbindliche Vorgabe an Claude, damit der Plan von Anfang an hineinpasst. Die Prüfung
**nachher** setzt dieselben Grenzen durch, falls Claude sie trotzdem überschreitet. Das Vorab-Nennen war
die Konsequenz aus dem ersten echten Lauf: Wenn die Prüfung einen Plan erst hinterher kürzt, verliert die
Einheit ihre Struktur (aus 4 × 200 m im Hauptsatz wurde ein einzelner 200er).

| Regel | Wirkung |
|---|---|
| Übertrainingsrisiko (Flag `overreaching_risk`) | Ruhetag erzwungen |
| 5 oder mehr Einheiten in 7 Tagen | Ruhetag erzwungen |
| Wochenumfang ausgeschöpft (über dem 1,3-Fachen des Wochenschnitts) | Ruhetag erzwungen |
| Schlechte Erholung (`recovery_poor`) | höchstens `easy`, Umfang halbiert |
| Mäßige Erholung | höchstens `moderate` |
| Trainingspause (`training_pause`) | höchstens `easy`, höchstens 800 m |
| Umfangsspitze (`volume_spike`) | höchstens `moderate`, Umfang auf 60 Prozent |
| Harte Einheit gestern oder heute | höchstens `moderate` (nie zwei harte hintereinander) |
| Einheit länger als die längste der letzten 4 Wochen mal 1,25 | Umfang gekürzt (mindestens 1000 m Spielraum, höchstens 4500 m) |
| Zielpace unrealistisch schnell | auf das schnellste erlaubte Tempo begrenzt |
| Falsche Summe der Abschnitte | Gesamtdistanz neu berechnet |
| Formalien (Distanz nicht auf 25 m, Pausen über 10 min, zu lange Texte) | stillschweigend normalisiert |

Beim Kürzen schrumpft der größte Abschnitt zuerst, Ein- und Ausschwimmen bleiben meist erhalten.
Eine Herabstufung der Intensität entfernt die Zielzeiten, weil sie zur härteren Einheit gehörten.
Bei einem erzwungenen Ruhetag ersetzt die Sicherheitsschicht auch die Begründung, weil die von
Claude zu einem anderen Plan gehörte. Bei allen anderen inhaltlichen Korrekturen hängt sie einen
Hinweis an die Begründung ("Hinweis: Zur Sicherheit angepasst (...)"), damit die Begründung nicht den
alten Umfang behauptet. Rein rechnerische Korrekturen (falsche Summe) erscheinen dort nicht.

**Geblockt** (nicht korrigiert) wird ein Plan bei unmöglichen Werten (negative oder nicht endliche
Zahlen), fehlender Begründung, Trainingstag ohne Abschnitte, mehr als 20 Abschnitten oder einem
Umfang von über 13,5 km. Dann greift der Fallback.

Die Pace im Snapshot enthält Pausen (siehe Grenzen in der
[Snapshot-Doku](AthleteStateSnapshot.md)). Die Obergrenze für das Tempo ist deshalb locker
gewählt und fängt nur Unsinn ab, sie ist keine Trainingsempfehlung.

## Kostenbremse

Der Server ruft Claude höchstens 5-mal pro Stunde und 20-mal pro Tag auf (`PLAN_MAX_GENERATIONS_PER_HOUR`,
`PLAN_MAX_GENERATIONS_PER_DAY`). Darüber liefert er den letzten gültigen Plan
(`fallback_reason: budget_exceeded`). Ein durchgesickerter Token kann so nur begrenzt Kosten
erzeugen. Der Zähler liegt im Speicher und beginnt nach einem Neustart neu. Zusätzlich wird derselbe
Zustand am selben Tag nur einmal geplant (Cache).

Setze außerdem in der Anthropic Console unter *Limits* ein monatliches Ausgabenlimit.

## Kosten (gemessen)

Standardmodell ist `claude-opus-5-5` ($4 pro Million Eingabe-Token, $20 pro Million Ausgabe-Token).
Gemessen im ersten echten Lauf am 30.09.2026 (fünf Szenarien, Effort `medium`, siehe
[plan-eval.md](plan-eval.md)):

| | Eingabe-Token | Ausgabe-Token | Dauer | Kosten |
|---|---|---|---|---|
| Durchschnitt | rund 3.400 | rund 1.250 | rund 15 s | rund $0,038 |
| Spanne | 3.318 bis 3.474 | 458 bis 1.731 | 6 bis 19 s | $0,023 bis $0,048 |

Ein Ruhetag ist am günstigsten (wenig Text). Die Eingabe ist größer als der reine Prompt (System-Prompt
rund 1.000, Nutzernachricht rund 400 Token): Der Rest von rund 2.000 Token entfällt vermutlich auf das
JSON-Schema der strukturierten Ausgabe. Die Ausgabe enthält das adaptive Denken, es fiel bei `medium`
geringer aus als zuerst geschätzt.

Bei ein bis zwei Plänen pro Tag sind das etwa $1 bis $3 im Monat. Die Kostenbremse deckelt den Worst
Case bei 20 Aufrufen pro Tag, das wären rund $1 pro Tag (rund $29 im Monat).

Das Modell lässt sich per `PLAN_MODEL` wechseln (z. B. `claude-sonnet-5-5`, halber Preis), die Denktiefe
per `PLAN_EFFORT` (`low` bis `max`, Standard `medium`). Jeder Aufruf schreibt Modell, Token und Dauer
ins Server-Log (`docker logs swiminstructor-backend`, Eintrag "plan generated").

## Datenschutz

An Anthropic geht nur der Snapshot: aggregierte Zahlen (Umfänge, Pace, Erholungsabweichungen,
Flags), keine Namen, keine einzelnen Workouts, keine Rohdaten aus Health. Der Server speichert nur
den letzten Plan, den Snapshot selbst nicht.

## Konfiguration

| Variable | Standard | Bedeutung |
|---|---|---|
| `ANTHROPIC_API_KEY` | (leer) | Ohne Key startet der Server trotzdem, der Plan-Endpunkt liefert dann nur Cache und Fallback |
| `PLAN_MODEL` | `claude-opus-5-5` | Modell für die Pläne |
| `PLAN_EFFORT` | `medium` | Denktiefe: `low`, `medium`, `high`, `xhigh`, `max` |
| `PLAN_TIMEOUT_MS` | `75000` | Zeitlimit pro Aufruf (1.000 bis 85.000, bleibt unter dem 90-s-Limit von Caddy) |
| `PLAN_SERVER_FALLBACK` | `true` | Bei Ablehnung durch Claudes Sicherheitsklassifikatoren automatisch ein anderes Modell versuchen |
| `DATA_DIR` | `./data` (im Container `/data`) | Hier liegt der letzte Plan |
| `PLAN_TIMEZONE` | `Europe/Berlin` | Zeitzone für "heute" |
| `PLAN_MAX_GENERATIONS_PER_HOUR` | `5` | Kostenbremse |
| `PLAN_MAX_GENERATIONS_PER_DAY` | `20` | Kostenbremse |

Der Server wiederholt Claude-Aufrufe nicht selbst: Eine Wiederholung nach einem Zeitlimit würde
doppelt kosten und über das Zeitlimit des Reverse-Proxys laufen. Bei einem Ausfall liefert er sofort
den letzten Plan, die App kann es später noch einmal versuchen.

## Die fünf Szenarien bewerten (Definition of Done M5)

Die Szenarien aus M3 liegen als Snapshots in `backend/scenarios/`. Sie gegen die echte API laufen
zu lassen kostet etwa fünf Anfragen (geschätzt unter $1). Es gibt zwei Wege, je nachdem, wo du bist.

**Auf dem Server (kein Node nötig).** Der Produktionsserver hat nur Docker. Das Hilfsskript startet
einen Wegwerf-Container, liest den Key aus `/etc/swiminstructor/backend.env` (er wird nie
angezeigt), fragt vorher die Kosten ab und schreibt das Ergebnis nach
`docs/eval-runs/plan-eval-<Datum-Uhrzeit>.md` (das gepflegte Dokument `docs/plan-eval.md` bleibt unberührt):

```bash
cd /opt/stack/swiminstructor && git pull --ff-only origin main
backend/scripts/eval-in-docker.sh
cat docs/eval-runs/plan-eval-*.md | less      # oder den neuesten Lauf: ls -t docs/eval-runs | head -1
```

**Auf einem Rechner mit Node 22:**

```bash
cd backend
npm ci
mkdir -p ../docs/eval-runs
ANTHROPIC_API_KEY=sk-ant-... npm run eval:scenarios > ../docs/eval-runs/plan-eval-$(date +%F).md
```

Das Skript druckt je Szenario den Snapshot, Claudes Rohplan, die Korrekturen der
Sicherheitsschicht, den korrigierten Plan sowie Token, Dauer und Kosten. Du bewertest jeden Plan
von Hand. Deine Bewertung kommt in die Tabelle am Ende von `docs/plan-eval.md` (am einfachsten sagst du sie Claude im Chat, der trägt sie ein). Orientierung:

| Szenario | Ein sinnvoller Plan ... |
|---|---|
| 01 Anfänger | ist kurz (unter 1.000 m), locker, technikorientiert, ohne ehrgeizige Zielzeiten |
| 02 Fortschritt | steigert maßvoll, nutzt die gute Erholung, geht nicht an die Grenze nach der harten Einheit von gestern |
| 03 Trainingspause | ist ein kurzer, lockerer Wiedereinstieg |
| 04 Zieldatum nah | ist zielpace-spezifisch und reduziert den Umfang (Tapering) |
| 05 Übertraining | ist ein Ruhetag oder eine sehr kurze, lockere Einheit, mit Hinweis auf Erholung |
