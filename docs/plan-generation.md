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

## Wochenplan: `POST /v1/plan/week`

Claude plant die Woche als **Gerüst**: je Tag Typ, Intensität, Umfang, Dauer und ein kurzer Schwerpunkt. Die
Abschnitte einer Einheit (Wiederholungen, Pausen, Equipment) entstehen erst am Tag selbst über
`POST /v1/plan/today`, passend zur Vorgabe der Woche. Der Wochenplan ist kurz (rund 1.000 Token Ausgabe).

Anfrage (`Authorization: Bearer <Token>`, Body JSON):

| Feld | Bedeutung |
|---|---|
| `snapshot` | der Zustand (wie beim Tagesplan) |
| `week_start` | Montag der Woche, `YYYY-MM-DD` |
| `from_date` | erster zu planender Tag: heute (laufende Woche neu planen) oder `week_start` (kommende Woche) |
| `today` | heute beim Athleten |
| `unavailable_dates` | Tage ohne Zeit (werden Ruhetage), optional |
| `swum_this_week` | `[{date, meters}]`: was vor `from_date` schon geschwommen wurde, optional |
| `wishes` | Wunsch für die Woche, höchstens 500 Zeichen, optional (steht im Prompt als JSON-String, ändert Grenzen nie) |

Ungültige Daten (kein Montag, `from_date` außerhalb der Woche, unmögliche Kalendertage) lehnt der Server mit
`400` und `details` je Feld ab. Antwort `200`:

```json
{
  "week_start": "2026-09-28",
  "generated_at": "2026-09-30T10:00:00.000Z",
  "plan": {
    "rationale": "…",
    "total_distance_meters": 3600,
    "days": [
      { "date": "2026-09-30", "session_type": "endurance", "intensity": "moderate",
        "target_distance_meters": 1200, "estimated_duration_minutes": 40, "focus": "Ausdauer" }
    ]
  },
  "adjustments": ["Samstag, 03.10.: harte Einheit auf \"moderate\" gesenkt (…)"],
  "wishes": "mehr Technik"
}
```

`days` enthält genau die Tage ab `from_date` bis Sonntag. Der Server **speichert den Wochenplan nicht**: Die App
hält ihn und die Änderungen des Athleten selbst. Scheitert Claude, antwortet der Server `503` mit
`reason` (wie beim Tagesplan, ohne Ersatzplan), die App behält ihren bisherigen Wochenplan. Jeder Aufruf zählt
gegen dasselbe Budget wie ein Tagesplan.

**Sicherheitsschicht** (`weekSanity.ts`, die Grenzen gehen vorab auch an Claude): genau die angefragten Tage
(fehlende werden Ruhetage, fremde und doppelte verworfen), Tage ohne Zeit sind Ruhetage, die Grenzen für heute
gelten für den heutigen Tag, keine Einheit über dem Einheiten-Limit (längste Einheit mal 1,25, höchstens 4.500 m),
höchstens zwei harte Tage und nie an aufeinanderfolgenden Tagen, höchstens fünf Einheiten pro Woche (schon
geschwommene Tage zählen mit), Wochenumfang höchstens Wochenschnitt mal 1,3 abzüglich Geschwommenem (bei schlechter
Erholung, Umfangsspitze und Trainingspause gekürzt, aber nur für die laufende Woche), in einer vollen Woche
mindestens ein Ruhetag. Korrekturen stehen in `adjustments` und an der Begründung.

**Vorgabe für den Tagesplan:** `POST /v1/plan/today` nimmt optional `day_plan` (`session_type`, `intensity`,
`target_distance_meters`, `focus`). Claude hält sich daran, soweit die Grenzen es erlauben, ein Wunsch geht der
Vorgabe vor. Die Vorgabe gehört zum Cache-Schlüssel.

## Anfrage und Antwort

Anfrage: `Authorization: Bearer <Token>` und als Body `{"snapshot": { ... }}` (das JSON aus
`AthleteStateSnapshot`). Ungültige Snapshots lehnt der Server mit `400` ab. Unbekannte Felder
werden verworfen und erreichen Claude nie.

Optional `"wishes": "…"`: Freitext des Athleten für heute (höchstens 500 Zeichen, die App sendet bis 300,
leer oder nur Leerraum zählt als kein Wunsch). Er steht in der Nutzernachricht als JSON-String und als Daten
gekennzeichnet, kann die Grenzen für heute nie ändern und gehört zum Cache-Schlüssel: Ein anderer Wunsch bei
gleichem Zustand ergibt einen neuen Plan. Zu lang oder kein String: `400`. Die Antwort enthält den Wunsch als `wishes`, wenn der Plan mit einem erzeugt wurde, und das Log die Länge als `wishChars`.

Optional `"regenerate": true`: Der Server überspringt dann seinen Cache und fragt Claude auch bei
unverändertem Zustand neu (die App schickt das beim Ziehen zum Aktualisieren). Das zählt gegen das
Budget, bei Ausfall oder erschöpftem Budget kommt wie sonst der letzte Plan. Kein Boolean: `400`.

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
        "instructions": "gleichmäßig",
        "equipment": ["pull_buoy", "paddles"]
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

**Equipment:** Jeder Abschnitt hat `equipment`, eine Liste aus `pull_buoy`, `paddles`, `fins`, `snorkel`,
`kickboard`, `ankle_band` (leer, wenn nichts gebraucht wird). Die Sicherheitsschicht entfernt Doppelte und
begrenzt auf drei je Abschnitt. Pläne, die vor dieser Änderung gespeichert wurden, haben das Feld nicht: Der
Server liest sie mit leerer Liste (`StoredTrainingPlanSchema`), die App ebenso. Ein unbekanntes Hilfsmittel in
einem gespeicherten Plan macht ihn ungültig (kein Fallback darauf). Claude soll Hilfsmittel sparsam einsetzen,
Wünsche des Athleten dazu berücksichtigen und bei Abschnitten mit Hilfsmitteln keine Zielpace vorgeben.

**Gesamtziel:** Das Ziel (Distanz, Zielzeit, Zieltag) stellt der Athlet in der App ein ("Mein Ziel" in den
Einstellungen, Standard 3,8 km in 60 Minuten bis 04.07.2027, dauerhaft gespeichert, jederzeit änderbar). Es reist
im Snapshot (`goal`) mit jeder Anfrage. Die Nutzernachricht des Tages- und des Wochenplans enthält daraus den
Abschnitt "Gesamtziel" (`src/plan/goal.ts`), berechnet aus den Zahlen und nie Freitext: Distanz, Zielzeit, Zielpace,
Zieltag, Wochen bis dahin, längste Einheit in Prozent der Zieldistanz, Lücke zur Zielpace und die **Phase**
(`base` über 12 Wochen, `specific` bis 12 Wochen, `taper` die letzten zwei Wochen, `peak_week` die letzte Woche,
`past` nach dem Zieltag). Ist die Zieldistanz mit etwa 10 % Steigerung pro Woche in der Restzeit nicht sicher
erreichbar (Realismus-Hinweis), soll Claude das ehrlich in einem Satz sagen. Das Ziel hebt nie die Grenzen auf:
Umfang, Intensität und Ruhetage prüft weiter die Sicherheitsschicht, ein ferneres oder ehrgeizigeres Ziel macht die
Einheit von heute also nicht länger.

**Vorhandenes Equipment:** `POST /v1/plan/today` und `POST /v1/plan/week` nehmen optional `equipment`, die Liste
der Hilfsmittel, die der Athlet hat (Einstellungen der App). Fehlt das Feld, ist jedes erlaubt; eine leere Liste
heißt "keins". Die Nutzernachricht nennt die vorhandenen Hilfsmittel, die Sicherheitsschicht entfernt alle
anderen aus den Abschnitten und schreibt das in `adjustments` ("Hilfsmittel entfernt, die du nicht hast: …").
Die Auswahl gehört (sortiert) zum Cache-Schlüssel des Tagesplans: Ändert sie sich, entsteht ein neuer Plan. Beim
Wochenplan (nur Gerüst) wählt Claude keinen Schwerpunkt, der Hilfsmittel verlangt, die fehlen.

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
Zustand am selben Tag nur einmal geplant (Cache), außer die Anfrage verlangt `regenerate`.

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

## Die Szenarien bewerten (Definition of Done M5)

Die Szenarien liegen als Snapshots in `backend/scenarios/`: die fünf aus M3 und vier zum Gesamtziel (06 Ziel
unrealistisch, 07 Zieltag vorbei, 08 eigenes Ziel, 09 Zielwoche). Je Szenario läuft ein **Tagesplan** und ein
**Wochenplan** gegen die echte API, das sind 18 Anfragen (geschätzt rund $1; nur eine Art: `EVAL_SCOPE=day` oder
`EVAL_SCOPE=week`). Es gibt zwei Wege, je nachdem, wo du bist.

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

Das Skript druckt oben eine Übersichtstabelle und je Szenario den Snapshot, Claudes Rohplan, die Korrekturen der
Sicherheitsschicht, den korrigierten Plan, die **automatische Zielprüfung** (`src/plan/evaluation.ts`) sowie Token,
Dauer und Kosten. Die Zielprüfung ist eine Heuristik und ersetzt dein Urteil nicht: Sie zeigt, ob die Begründung das
Ziel nennt, ob bei unrealistischem Ziel ehrlich darauf hingewiesen wird, ob nach dem Zieltag erhaltend geplant und auf
ein neues Ziel verwiesen wird, ob die Zielwoche kurz und ohne harte Einheit bleibt, ob der Umfang beim Zuspitzen sinkt
und ob die zielspezifische Phase Abschnitte nahe der Zielpace enthält. Du bewertest jeden Plan
von Hand. Deine Bewertung kommt in die Tabelle am Ende von `docs/plan-eval.md` (am einfachsten sagst du sie Claude im Chat, der trägt sie ein). Orientierung:

| Szenario | Ein sinnvoller Plan ... |
|---|---|
| 01 Anfänger | ist kurz (unter 1.000 m), locker, technikorientiert, ohne ehrgeizige Zielzeiten |
| 02 Fortschritt | steigert maßvoll, nutzt die gute Erholung, geht nicht an die Grenze nach der harten Einheit von gestern |
| 03 Trainingspause | ist ein kurzer, lockerer Wiedereinstieg |
| 04 Zieldatum nah | ist zielpace-spezifisch und reduziert den Umfang (Tapering) |
| 05 Übertraining | ist ein Ruhetag oder eine sehr kurze, lockere Einheit, mit Hinweis auf Erholung |
