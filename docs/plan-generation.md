# Plan-Erzeugung auf dem Server

Die App schickt den Zustands-Snapshot (siehe [AthleteStateSnapshot.md](AthleteStateSnapshot.md)), der Server lässt
Claude daraus Gesamtplan, die nächsten sieben Tage, den Tag oder den Plan für den Wettkampftag schreiben, prüft das Ergebnis mit einer Sicherheitsschicht
und liefert es zurück. Fällt Claude aus, bekommt die App beim Tagesplan den letzten gültigen Plan. Welche Pfade es gibt,
was sie annehmen, die Grenzen je Sportart und die Regeln der Sicherheitsschicht stehen in
[multisport-planning.md](multisport-planning.md). Dieses Dokument beschreibt den Ablauf, Ausfallgründe, Kosten und
Konfiguration, die für alle Pläne gleich sind.

## Ablauf

```
App ──POST {plan_version: 2, snapshot, …}──▶ Server
                          1. Anfrage prüfen (Schema, Wertebereiche, unbekannte Felder verwerfen)
                          2. Tagesplan: gleicher Zustand heute schon geplant?  ──ja──▶ gespeicherten Plan liefern (source: cache)
                          3. Aufrufbudget frei und API-Key da?      ──nein─▶ Fallback bzw. 503
                          4. Claude aufrufen (fester System-Prompt, strukturierte JSON-Ausgabe,
                             dazu die berechneten Grenzen für den Plan)
                          5. Antwort gegen das Schema prüfen        ──Fehler─▶ Fallback bzw. 503
                          6. Sicherheitsschicht: korrigieren oder blocken   ──blockiert─▶ Fallback bzw. 503
                          7. Tagesplan speichern, liefern (source: claude)

Fallback (nur Tagesplan) = letzter gespeicherter Plan, vorher erneut durch die Sicherheitsschicht gegen den heutigen
Zustand geprüft (source: fallback). Gibt es keinen, und bei Woche, Gesamtplan, Überarbeitung und Wettkampftag immer:
503 mit Grund.
Die App behält dann ihren bisherigen Plan und kann es später erneut versuchen.
```

Der Server wiederholt Claude-Aufrufe nicht selbst: Eine Wiederholung nach einem Zeitlimit würde doppelt kosten und über
das Zeitlimit des Reverse-Proxys laufen.

### `fallback_reason`

| Wert | Bedeutung |
|---|---|
| `unreachable` / `timeout` | Claude war nicht erreichbar oder zu langsam (Zeitlimit 75 s, bei Gesamtplan, Überarbeitung und Wettkampftag 180 s) |
| `rate_limited` / `upstream_error` | Claude meldete Limit (429) oder Serverfehler (5xx, 529) |
| `refusal` | Claudes Sicherheitsklassifikatoren haben abgelehnt (und auch der Server-Fallback) |
| `truncated` / `empty_response` / `invalid_json` / `schema_invalid` | Antwort unbrauchbar |
| `sanity_blocked` | Der Plan war so kaputt, dass die Sicherheitsschicht ihn verworfen hat |
| `budget_exceeded` | Aufrufbudget erschöpft (Kostenbremse, siehe unten) |
| `not_configured` | Kein `ANTHROPIC_API_KEY` gesetzt |
| `auth` / `bad_request` / `unknown` | Konfigurations- oder Programmfehler, steht als `error` im Server-Log |

## Sicherheitsschicht

Reiner Code ohne Netzwerk (`backend/src/plan/multi/`): Dieselben Grenzen gehen vorab an Claude (Nutzernachricht) und
prüfen danach den Plan. Sie korrigiert deterministisch (Umfang kürzen, Intensität senken, Sätze auf Vielfache von 50 m
bringen, Ruhetage erzwingen) und hängt jede inhaltliche Korrektur an die Begründung und an `adjustments`, damit Plan und
Text zusammenpassen. Was nicht mehr zu retten ist, blockt sie (`sanity_blocked`). Regeln, Zahlen und Quellen:
[multisport-planning.md](multisport-planning.md#grenzen-je-sportart) und
[Übergreifende Regeln](multisport-planning.md#übergreifende-regeln).

## Kostenbremse

Der Server ruft Claude je Nutzer höchstens 5-mal pro Stunde und 20-mal pro Tag auf (`PLAN_MAX_GENERATIONS_PER_HOUR`,
`PLAN_MAX_GENERATIONS_PER_DAY`), über alle Nutzer höchstens 15-mal pro Stunde und 60-mal pro Tag
(`PLAN_MAX_GENERATIONS_TOTAL_PER_HOUR`, `_TOTAL_PER_DAY`); alle Pläne zählen zusammen. Darüber liefert er den letzten gültigen Tagesplan
(`fallback_reason: budget_exceeded`) bzw. 503. Ein durchgesickerter Token kann so nur begrenzt Kosten erzeugen. Der
Zähler liegt im Speicher und beginnt nach einem Neustart neu. Zusätzlich wird derselbe Zustand am selben Tag nur einmal
geplant (Cache), außer die Anfrage verlangt `regenerate`.

Setze außerdem in der Anthropic Console unter *Limits* ein monatliches Ausgabenlimit.

## Kosten (gemessen)

Standardmodell ist `claude-opus-5-5` ($4 pro Million Eingabe-Token, $20 pro Million Ausgabe-Token), Effort `high`.
Gemessen in den Bewertungsläufen vom 03. und 04.10.2026 (siehe `docs/eval-runs/`):

| Plan | Eingabe-Token | Ausgabe-Token | Dauer | Kosten |
|---|---|---|---|---|
| Tag | rund 8.500 bis 9.600 | rund 1.700 bis 3.700 | rund 20 bis 40 s | rund $0,07 bis 0,11 |
| Gesamtplan (24 bis 40 Wochen, drei Sportarten) | rund 12.000 bis 16.500 | rund 9.000 bis 10.000 | rund 85 bis 105 s | rund $0,25 |

Die Woche liegt dazwischen. Ein Bewertungslauf aller Szenarien (29 Anfragen) kostet rund $4. Die Eingabe ist größer als
der Prompt allein: Das JSON-Schema der strukturierten Ausgabe zählt mit. Die Ausgabe enthält das adaptive Denken.

Die Kostenbremse deckelt den Worst Case bei 20 Aufrufen pro Tag. Das Modell lässt sich per `PLAN_MODEL` wechseln
(z. B. `claude-sonnet-5-5`, halber Preis), die Denktiefe per `PLAN_EFFORT` (`low` bis `max`). Jeder Aufruf schreibt
Modell, Token und Dauer ins Server-Log (`docker logs swiminstructor-backend`) und in die Nutzungsdatei; Tageskosten,
Fehlerquote und Dauer zeigt `GET /v1/admin/usage`, Alarme kommen per Webhook (siehe
[backend-deploy.md](backend-deploy.md#monitoring)).

## Datenschutz

An Anthropic geht nur der Snapshot: aggregierte Zahlen (Umfänge, Tempo, Erholungsabweichungen, Warnhinweise, Leistungswerte
und Zonen), keine Namen, keine einzelnen Workouts, keine Rohdaten aus Health. Dazu kommen die Angaben, die der Athlet
selbst macht (Ziel, Wünsche, Feedback, Rückmeldung zu Anstrengung und Beschwerden, Notizen zum Wettkampf). Mit "Wetter
berücksichtigen" schickt die App einen auf 0,1° (etwa 10 km) gerundeten Ort; der Server fragt damit Open-Meteo nach der
Vorhersage, an Anthropic geht nur das Wetter in Worten. Aus dem Kalender gehen nur freie Minuten je Tag an den Server,
keine Termine. Der Server speichert je Nutzer nur den letzten Tagesplan, den Snapshot selbst
nicht, dazu die Nutzung je Anfrage (Nutzerkennung, Plan-Art, Ergebnis, Token, Dauer, keine Trainingsdaten).

## Konfiguration

| Variable | Standard | Bedeutung |
|---|---|---|
| `ANTHROPIC_API_KEY` | (leer) | Ohne Key startet der Server trotzdem, die Plan-Endpunkte liefern dann nur Cache und Fallback bzw. 503 |
| `PLAN_MODEL` | `claude-opus-5-5` | Modell für die Pläne |
| `PLAN_EFFORT` | `high` | Denktiefe: `low`, `medium`, `high`, `xhigh`, `max` |
| `PLAN_TIMEOUT_MS` | `75000` | Zeitlimit für Tages- und Wochenpläne (1.000 bis 85.000, bleibt unter den 95 s der App) |
| `PLAN_MACRO_TIMEOUT_MS` | `180000` | Zeitlimit für Gesamtplan, Überarbeitung und Wettkampftag (1.000 bis 230.000, bleibt unter den 240 s von Caddy und den 245 s der App) |
| `PLAN_SERVER_FALLBACK` | `true` | Bei Ablehnung durch Claudes Sicherheitsklassifikatoren automatisch ein anderes Modell versuchen |
| `DATA_DIR` | `./data` (im Container `/data`) | Letzter Tagesplan (`latest-plan-v2.json`, weitere Nutzer unter `users/<kennung>/`), Nutzer (`users.json`), Nutzung (`metrics/`) |
| `PLAN_TIMEZONE` | `Europe/Berlin` | Zeitzone für "heute" |
| `PLAN_MAX_GENERATIONS_PER_HOUR` | `5` | Kostenbremse je Nutzer |
| `PLAN_MAX_GENERATIONS_PER_DAY` | `20` | Kostenbremse je Nutzer |
| `PLAN_MAX_GENERATIONS_TOTAL_PER_HOUR` | `15` | Kostenbremse des ganzen Servers |
| `PLAN_MAX_GENERATIONS_TOTAL_PER_DAY` | `60` | Kostenbremse des ganzen Servers |
| `ALERT_WEBHOOK_URL` und weitere `ALERT_*` | (leer) | Alarme, siehe [backend-deploy.md](backend-deploy.md#alarme) |

## Bewertung der Pläne

Wie echte Läufe gegen die Claude-API ausgewertet werden (Szenarien, automatische Prüfungen, Aufzeichnung und
Wiedergabe): [multisport-planning.md, Abschnitt Bewertung](multisport-planning.md#bewertung). Auf dem Server, ohne
Node: `backend/scripts/eval-in-docker.sh`.

## Woher die Regeln kommen

Die ersten Bewertungsläufe (September und Oktober 2026, damals nur Schwimmen) haben die Regeln geprägt, die heute in
den Modulen stehen: Claude bekommt die Grenzen vorab, weil ein nachträgliches Kürzen die Einheit zerschneidet; die
Begründung nennt nach einer Korrektur die neuen Zahlen; Technikübungen werden erklärt; jede Einheit hat eine
Mindestlänge und jeder Schwimmsatz ist ein Vielfaches von 50 m (passt für 25- und 50-m-Becken); beim Zuspitzen sinkt der
Umfang als harte Grenze, die Zielwoche trägt aber den Versuch auf die Zieldistanz. Die Rohausgaben der Läufe von Plan v2
liegen in `docs/eval-runs/`.
