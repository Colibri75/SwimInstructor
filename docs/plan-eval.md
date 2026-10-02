# Plan-Bewertung der fünf Szenarien (M5)

Die Szenarien aus M3 liegen als Snapshots in `backend/scenarios/`. Der Lauf gegen die echte Claude-API
kommt aus `backend/scripts/eval-in-docker.sh` (Server) oder `npm run eval:scenarios` (Rechner mit Node),
siehe [plan-generation.md](plan-generation.md).

Die Rohausgabe jedes Laufs liegt in `docs/eval-runs/` (Zeitstempel im Namen). Dieses Dokument dagegen ist
gepflegt und wird vom Skript nie überschrieben.

Dieses Dokument hält fest, was die Läufe gezeigt haben. Die Einschätzungen darin sind die von Claude
(dem Entwicklungsassistenten) und **keine Trainerfreigabe**. Ob ein Plan sinnvoll ist, entscheidest du
am Ende in der Tabelle unten. Das ist der manuelle Teil der Definition of Done.

## Lauf 1 (30.09.2026): erster echter Aufruf, vor den Korrekturen

Modell `claude-opus-5-5`, Effort `medium`, ausgeführt auf dem Produktionsserver.

**Technisch hat alles funktioniert.** Claude lieferte in allen fünf Fällen schema-konformes JSON, kein
Fallback war nötig, keine Ablehnung.

| Szenario | Dauer | Token ein / aus | Kosten |
|---|---|---|---|
| 01 Anfänger | 18,8 s | 3.318 / 1.584 | $0,045 |
| 02 Fortschritt | 17,1 s | 3.443 / 1.351 | $0,041 |
| 03 Trainingspause | 12,6 s | 3.361 / 1.100 | $0,035 |
| 04 Zieldatum nah | 18,1 s | 3.354 / 1.731 | $0,048 |
| 05 Übertraining | 6,4 s | 3.474 / 458 | $0,023 |
| **Summe** | | | **$0,192** |

Die Kosten liegen unter meiner ersten Schätzung: Die Ausgabe ist deutlich kürzer als erwartet, die
Eingabe etwa doppelt so groß wie der reine Prompt.

### Einschätzung je Szenario

| Szenario | Claudes Plan (roh) | Sicherheitsschicht | Einschätzung |
|---|---|---|---|
| **01 Anfänger** | Technik, locker, 300 m, Hauptsatz 2 × 50 m, Begründung mit konkreten Zahlen | nichts geändert | Sinnvoll und vorsichtig. Eher kurz: Der Athlet schwamm zuletzt 400 bis 500 m, erlaubt waren 1.000 m. Kein Fehler, eher konservativ. |
| **02 Fortschritt** | Technik, locker, 1.700 m nach der harten Einheit von gestern | auf 850 m gekürzt (Wochengrenze 855 m) | Claudes Plan war inhaltlich gut. Die Kürzung zerstörte ihn: Technik 8 × 50 m wurde 3 × 50 m, Hauptsatz 4 × 200 m wurde ein einzelner 200er. **Die Begründung nannte weiter "1700 m".** |
| **03 Trainingspause** | Technik, locker, 1.000 m, vorsichtiger Wiedereinstieg | auf 800 m gekürzt (Pausengrenze) | Sinnvoll. Der Hauptsatz schrumpfte von 4 × 100 m auf 2 × 100 m, brauchbar. **Begründung nannte weiter "1000 m".** |
| **04 Zieldatum nah** | Intervalle, hart, 2.200 m, 10 × 100 m im Zieltempo, realistische Hinweise zum Rennen | auf 1.500 m gekürzt (Wochengrenze) | Claudes Plan war trainingsmethodisch stimmig (zielpace-spezifisch, Hinweis auf gleichmäßiges Rennen). Die Kürzung ließ vom Hauptsatz nur 3 × 100 m übrig, die Einheit verlor ihren Kern. **Begründung nannte weiter "2200 m".** |
| **05 Übertraining** | Ruhetag mit konkreten Zahlen (+7 bpm, −20 % HRV, 5,5 h Schlaf, +233,3 %) und Erholungstipps | nichts geändert | Das beste Ergebnis. Claude wählte den Ruhetag selbst, die Begründung ist nachvollziehbar, die Hinweise sind sinnvoll. |

### Befunde und Korrekturen

1. **Die Sicherheitsschicht kürzte erst hinterher und zerschnitt dabei die Struktur der Einheit.**
   Claude kannte die Tagesgrenzen nicht und plante darüber hinaus. Die Schicht hielt die Grenze ein,
   aber der Hauptsatz blieb nur als Rest übrig.
   *Korrektur:* Die Grenzen für heute (Umfang, Intensität, Tempo, Pflicht-Ruhetag) gehen jetzt vorher
   als verbindliche Vorgabe an Claude. Die Prüfung nachher bleibt als harte Absicherung.
2. **Nach einer Kürzung stimmte die Begründung nicht mehr** (sie nannte den alten Umfang).
   *Korrektur:* Die Sicherheitsschicht hängt die Korrekturen als Hinweis an die Begründung.

Beide Korrekturen sind per Test abgesichert. Ob sie in der Praxis wirken, zeigt Lauf 2.

### Was nicht geprüft wurde

- Lauf 1 lief mit Effort `medium`. Ob `high` bessere Pläne liefert, ist offen und würde die Kosten
  erhöhen.
- Ein einzelner Lauf je Szenario ist keine Stichprobe. Claude kann bei demselben Snapshot andere Pläne
  liefern.

## Lauf 2 (30.09.2026): nach den Korrekturen

Gleiche Einstellungen wie Lauf 1 (`claude-opus-5-5`, Effort `medium`), ausgeführt auf dem Produktionsserver.
Die Rohausgabe entstand noch mit der alten Skriptversion und steht deshalb nicht in `docs/eval-runs/`.

**Die Sicherheitsschicht musste in keinem Szenario eingreifen.** Claude hielt die vorab genannten
Grenzen ein und erhielt dadurch die Struktur der Einheiten. Gesamtkosten rund $0,19, wie in Lauf 1.

| Szenario | Plan von Claude | Grenze für heute | Einschätzung |
|---|---|---|---|
| **01 Anfänger** | Technik, 500 m | 1.000 m | Sinnvoll, etwas länger als in Lauf 1 und näher an dem, was der Athlet schwimmt. |
| **02 Fortschritt** | Technik, locker, 850 m, Aufbau erhalten | 855 m | Die Schwäche aus Lauf 1 ist behoben: Claude plant direkt passend, nichts wird zerschnitten. |
| **03 Trainingspause** | 700 m, vorsichtiger Wiedereinstieg | 800 m | Sinnvoll. |
| **04 Zieldatum nah** | Schwelle, hart, 1.500 m, Hauptsatz 8 × 100 m mit 95 s Pace | 1.500 m | Zielpace-spezifisch und trotz der Wochengrenze mit vollem Kern. Die Einheit bleibt erhalten. |
| **05 Übertraining** | Ruhetag mit konkreten Zahlen | Pflicht-Ruhetag | Weiter das beste Ergebnis. |

Beide Korrekturen aus Lauf 1 haben damit gewirkt.

## Deine Bewertung (Definition of Done)

Bewertung von Lauf 2 durch Steffen am 30.09.2026.

| Szenario | sinnvoll | Begründung |
|---|---|---|
| 01 Anfänger | [x] | |
| 02 Fortschritt | [x] | "Aber die Übungen sollten erklärt werden, also sowas wie Zipper." |
| 03 Trainingspause | [x] | |
| 04 Zieldatum nah | [x] | |
| 05 Übertraining | [x] | |

### Folge aus der Bewertung: Übungen erklären

Die Pläne nennen Technikübungen (etwa "Zipper" oder "Abschlagschwimmen"), ohne zu sagen, wie sie
gehen. Wer ohne Trainer schwimmt, kann damit nichts anfangen.

*Umsetzung:* Der System-Prompt verlangt jetzt, jede Technikübung im Feld `instructions` in ein bis zwei
Sätzen zu erklären und keinen Fachbegriff unerklärt zu lassen. Die Beschreibung des Feldes im Schema sagt
dasselbe. Die Sicherheitsschicht kürzt Anweisungen erst ab 600 Zeichen statt wie bisher ab 400, damit
die Erklärung nicht abgeschnitten wird.

*Nicht nachbewertet:* Diese Prompt-Änderung kam nach Lauf 2 und wurde noch nicht gegen die echte API
gelaufen. Ein weiterer Lauf (rund $0,20) zeigt, ob die Erklärungen tatsächlich kommen. Langfristig
(M7) wäre ein Übungslexikon in der App sinnvoll, statt die Erklärung in jedem Plan zu wiederholen.

## Lauf 3 (30.09.2026): Tages-, 7-Tage- und Gesamtplan gegen das Gesamtziel

Modell `claude-opus-5-5`, Effort `high`, 27 Anfragen (neun Szenarien, je Tag, 7 Tage, Gesamtplan), ca. $1,52.
**Technisch lief alles:** kein Schema-Fehler, kein Fallback, nichts von der Sicherheitsschicht geblockt. Dauer 12 bis
27 s je Tages- und 7-Tage-Plan, **höchstens 41 s je Gesamtplan über 40 Wochen** (Grenze 75 s, also genug Luft).

Deine Bewertung: Tagespläne alle sinnvoll, Gesamtpläne sinnvoll, 7-Tage-Pläne bei **01** und **03** nicht sinnvoll,
dazu zwei Kommentare. Die automatische Zielprüfung war bis auf drei offene Punkte grün.

| Befund | Ursache | Korrektur |
|---|---|---|
| **01 Anfänger, 7 Tage: am Ende nur 200 m** (Grenze 1.500 m). **03 Trainingspause: 825 m** in Einheiten von 250 bis 300 m | Der Prompt sagte "höchstens etwa 10 % über dem Wochenschnitt". Claude nahm das als Ziel (350 m Schnitt werden 375 m), und die Sicherheitsschicht machte aus 175 m einen Ruhetag. Außerdem lief der Test ohne Gesamtplan, der in der App die Richtung vorgibt | Prompt: Zielumfang ist die Vorgabe des Gesamtplans, die Wochengrenze wird sinnvoll genutzt. **Eine Einheit hat mindestens 400 m** (Code: eine halbe Einheit wird auf 400 m angehoben, darunter Ruhetag). Der gleiche Mindestwert gilt im Gesamtplan (mindestens zwei Einheiten, also 800 m pro Trainingswoche). Neue Zielprüfung: Wochenumfang mindestens die Hälfte der Grenze |
| **Kein Satz unter 50 m** (Kommentar von dir; im Tagesplan 01 standen 4 × 25 m) | Prompt erlaubte 25-m-Schritte für alles | Prompt: jeder Satz mindestens 50 m. Code: kürzere Sätze werden zusammengelegt (4 × 25 m wird 2 × 50 m, die Strecke bleibt), auch beim Kürzen auf die Tagesgrenze unterschreitet nie ein Satz 50 m |
| Typen im Bericht auf Englisch (`technique`, `intervals` …) | Der Bericht schrieb die Schema-Schlüssel. Die App zeigte schon Deutsch | Bericht nutzt dieselben Namen wie die App (Technik, Ausdauer, Schwelle, Intervalle, Regeneration, Test, Ruhetag) |
| **04 Zieldatum nah, 7 Tage: 5.500 m bei 5.000 m Wochenschnitt** (Zuspitzen verlangt weniger; automatische Prüfung offen) | Zuspitzen war nur ein Prompt-Satz, keine Grenze | Code: 8 bis 14 Tage vor dem Ziel höchstens 85 % des Wochenschnitts, in den letzten 7 Tagen höchstens 70 %, mindestens das 1,2-Fache der Zieldistanz (damit der Versuch passt) |
| Test plante nur 5 Tage ("für diese fünf Tage") | Das Skript war noch auf die alte Kalenderwoche bis Sonntag eingestellt | Das Skript plant wie die App 7 Tage ab heute, mit der Vorwoche, und reicht die Pläne wie in der App weiter: Gesamtplan, dann 7 Tage mit Gesamtplan, dann Tag mit der Vorgabe des 7-Tage-Plans |
| **01 Anfänger, Gesamtplan: Höhepunkt 6.200 m** statt der erwarteten 7.600 m (die Zieldistanz zweimal pro Woche), elf Korrekturen der Sicherheitsschicht | Start bei nur 700 m, und Claude steigerte unter den erlaubten 10 % | Mit dem Mindestumfang startet die erste Woche höher (800 m), und die Nutzernachricht nennt jetzt die Orientierung für den Höhepunkt samt Hinweis, die vollen 10 % zu nutzen |

Was gut war (unverändert lassen): Begründungen nennen das Ziel und sagen bei unrealistischem Ziel ehrlich, dass es nicht
reicht (06, 04, 01). Szenario 07 (Zieltag vorbei) verweist auf ein neues Ziel und plant erhaltend. Szenario 05
(Übertraining) beginnt mit Ruhetagen und hält den Gesamtplan trotzdem zielgerichtet. Die Zielwoche (09) ist kurz und
ohne harte Einheit, und alle Gesamtpläne reichen bis zur Zielwoche, mit Entlastungswochen und sinkendem Umfang beim
Zuspitzen. Die Kurzbeschreibungen für die Uhr (`cue`) sind drei bis vier Wörter lang.

## Lauf 4 (ausstehend): nach den Korrekturen aus Lauf 3

**Noch nicht ausgeführt.** Prüfen, ob die 7-Tage-Pläne jetzt sinnvolle Umfänge haben (01 und 03 bei etwa 1.000 bis
1.500 m in zwei bis drei Einheiten von je mindestens 400 m), ob nirgends mehr ein Satz unter 50 m steht und ob 04 beim
Zuspitzen unter dem Wochenschnitt bleibt.

Auf dem Server (27 Anfragen, kostet rund $1,50):

```bash
cd /opt/stack/swiminstructor && git pull --ff-only origin main
backend/scripts/eval-in-docker.sh
```

Danach die Ausgabe (`docs/eval-runs/plan-eval-<Datum-Uhrzeit>.md`) lesen oder sie Claude im Chat geben. Worauf zu achten ist:

| Szenario | Tagesplan | Nächste 7 Tage | Gesamtplan |
|---|---|---|---|
| 06 Ziel unrealistisch | bleibt in den Tagesgrenzen, sagt ehrlich, dass das Ziel so wohl nicht ganz erreichbar ist | wie der Tagesplan, Aufbau statt Sprung | steigt so steil wie sicher möglich, sagt ehrlich, dass es nicht reicht |
| 07 Zieltag vorbei | locker und erhaltend, Hinweis auf ein neues Ziel in den Einstellungen | keine harten Einheiten, Hinweis auf neues Ziel | nur eine Woche, Erhalten, Hinweis auf neues Ziel |
| 08 Eigenes Ziel (1.500 m) | Begründung nennt 1.500 m und 28 min, nicht 3.800 m; zielspezifisch | wie der Tagesplan, mindestens ein Tag mit Zielbezug | 12 Wochen bis 23.12., Höhepunkt trägt 1.500 m mehrfach |
| 09 Zielwoche | kurz, locker, höchstens kurze Zielpace-Stücke | Umfang unter dem Wochenschnitt, keine harte Einheit | eine Woche (Zielwoche), kurz |
| 01 bis 05 | wie in Lauf 2; zusätzlich nennt die Begründung das Ziel | sinnvolle Verteilung, Ruhetage, höchstens zwei harte Tage | 40 Wochen bis 04.07.2027, etwa 10 % Steigerung, Entlastung, Zuspitzen |

Das Ergebnis (und deine Bewertung) wird hier nachgetragen.

