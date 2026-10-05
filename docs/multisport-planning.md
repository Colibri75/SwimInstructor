# Planung für mehrere Sportarten (Plan v2, T3)

Der Server plant Schwimmen, Rad und Laufen gemeinsam: einen Gesamtplan bis zum Ziel, die nächsten sieben Tage und
den Tag mit allen Schritten. Plan v2 läuft neben v1 auf denselben Pfaden. Die App wählt ihn mit `plan_version: 2`
im Body; ohne das Feld (oder mit `1`) antworten die Routen von v1 genau wie bisher, alte Apps merken nichts.

Ablauf wie bei v1 (siehe [plan-generation.md](plan-generation.md)): Snapshot prüfen, Claude mit festem
System-Prompt und strukturierter Ausgabe, Antwort gegen das Schema prüfen, Sicherheitsschicht korrigiert oder blockt.
Dieselben Grenzen gehen vorher an Claude und prüfen danach den Plan; beide lesen sie aus einer Quelle
(`backend/src/plan/multi/limits.ts` und die Module in `backend/src/sports/modules/`).

## Endpunkte

Alle mit `Authorization: Bearer <Token>` und Snapshot v2 (siehe [AthleteStateSnapshot.md](AthleteStateSnapshot.md)).
Ein Snapshot v1 mit `plan_version: 2` ist ein Fehler 400. Die Antworten stehen als Beispiele in
`contracts/wire/plan-v2-*-response.json`; App und Server prüfen sie.

| Pfad | Body (zusätzlich zu `plan_version: 2` und `snapshot`) | Antwort |
|---|---|---|
| `POST /v1/plan/today` | `wishes` (bis 500 Zeichen), `day_plan` (Vorgabe aus dem Wochenplan: Einheiten mit Sportart, Typ, Intensität, Umfang, `test_id`), `equipment`, `recent_training`, `test_settings`, `regenerate` | `plan.sessions[]` mit Schritten, `source` (`claude`, `cache`, `fallback`), `stale`, `adjustments`, bei Ausfall `fallback_reason` |
| `POST /v1/plan/week` | `from_date`, `today`, `unavailable_dates`, `recent_training`, `macro_weeks` (bis 3 Wochen des Gesamtplans), `wishes`, `equipment`, `test_settings` | `plan.days[]` mit 0 bis 2 Einheiten je Tag, `adjustments` |
| `POST /v1/plan/macro` | `today`, `test_settings` | `goal_day`, `plan.weeks[]` mit Phase, Entlastung, Umfang je Sportart und Testterminen |
| `POST /v1/plan/macro/revise` | `today`, `plan` (der Gesamtplan, wie die App ihn hält), `feedback` (1 bis 1000 Zeichen), `history` (bis 5 frühere Runden), `test_settings`; `plan_version` ist hier optional, den Pfad gibt es nur in v2 | wie `/plan/macro`, dazu `changes` (was sich ändert) und `feedback` |

`recent_training` sind die Einheiten der letzten Tage (`date`, `sport`, `minutes`, `meters`, `hard`). Sie zählen für
"nie zwei harte Tage hintereinander" und für die Grenzen von heute. `test_settings`: `offer` (Tests anbieten,
Standard ja), `interval_weeks` (4 bis 12, Standard 6), `preferred` (bevorzugter Test je Sportart).

Fehlerfälle wie bei v1: Zeitüberschreitung, ungültiges JSON, Budget aufgebraucht, kein API-Key oder ein Plan, den die
Sicherheitsschicht blockt. Der Tagesplan liefert dann den letzten gespeicherten Plan (`latest-plan-v2.json`, getrennt
von v1, vorher gegen den heutigen Zustand geprüft), sonst 503 mit Grund. Woche, Gesamtplan und Überarbeitung antworten
mit 503 und Grund.

## Einheiten

`amount` steht immer in der Einheit der Sportart, `unit` sagt welche: `meters` beim Schwimmen, `minutes` bei Rad und
Laufen. Dazu rechnet der Server mit dem Trainingstempo des Athleten (aus dem Snapshot, sonst dem typischen Tempo des
Moduls) `minutes` bzw. `duration_minutes` und `distance_meters`. Schritte haben ein Maß (`distance` oder `duration`)
und ein Ziel, das die Sportart kennt (Pace, Pulszone, Leistung, Trittfrequenz, gefühlte Anstrengung).

## Grenzen je Sportart

Jedes Modul bringt seine Grenzen mit (`SportPlanning.limits`). "Längste" und "Schnitt" kommen aus den letzten vier
Wochen im Snapshot.

| | Schwimmen | Rad | Laufen |
|---|---|---|---|
| Einheit höchstens | längste × 1,25, mindestens 1500 m, höchstens 4500 m | längste × 1,25, mindestens 60 min, höchstens 360 min | längste × 1,1, mindestens 30 min, höchstens 210 min |
| Woche höchstens | Schnitt × 1,3, mindestens 2500 m | Schnitt × 1,3, mindestens 120 min | Schnitt × 1,3, mindestens 60 min (geplant wird mit etwa +10 %) |
| Wiedereinstieg (über 14 Tage Pause, ohne Startniveau) | 800 m je Einheit, nur locker | 45 min je Einheit, nur locker | 20 min je Einheit, nur locker |
| kürzeste Einheit | 400 m | 20 min | 15 min |
| Einheiten pro Woche | 5 | 4 | 4 |
| Gesamtplan: Steigerung je Woche | 10 % | 10 % | 10 % |

Laufen hat die strengsten Grenzen: Eine Einheit höchstens 10 % länger als die längste der letzten vier Wochen
(Frandsen et al. 2025), die Woche hart bei +30 % (Nielsen et al. 2014), der Prompt verlangt etwa +10 %. ACWR ist keine
Sperre, nur Information für Claude.

## Selbst angegebenes Startniveau

Health zeigt oft weniger, als jemand kann: Training ohne Uhr, eine Pause, ein Wechsel des Geräts. Deshalb gibt der
Athlet in den Einstellungen je Sportart an, was er zurzeit schafft (Wochenumfang, längste Einheit) und wie sein
Trainingsstand ist (Snapshot: `starting_levels`, siehe [AthleteStateSnapshot.md](AthleteStateSnapshot.md)).

Der Server plant dann mit dem höheren Wert aus Health und dem Anteil der Angabe, der für den Trainingsstand gilt.
"Längste" und "Schnitt" in der Tabelle oben sind dann diese Werte, die Untergrenzen bleiben. Mit gültiger Angabe gibt
es keinen Wiedereinstieg aus der Lücke in Health; die Angabe ersetzt ihn.

| Trainingsstand | Schwimmen | Rad | Laufen |
|---|---|---|---|
| regelmäßig | 100 % | 100 % | 100 % |
| Pause 2 bis 8 Wochen | 70 % | 70 % | 50 % |
| Pause über 8 Wochen | 50 % | 50 % | zählt nicht (Wiedereinstieg wie ohne Angabe) |
| Einsteiger | zählt nicht | zählt nicht | zählt nicht |
| Gesamtplan bis zum Niveau vor der Pause | +20 % pro Woche | +20 % pro Woche | +10 % pro Woche |

- Die Angabe gilt 28 Tage ab `reported_at` (`MULTI_RULES.startingLevelValidDays`), danach zählt nur noch Health. Die
  App zeigt, bis wann sie gilt; der Athlet kann sie erneuern.
- Sie wird auf die absoluten Grenzen des Moduls gekappt (längste Einheit höchstens `absoluteMaxSession`, Woche
  höchstens `absoluteMaxSession` mal Einheiten pro Woche).
- Im Gesamtplan darf der Umfang bis zum angegebenen Wochenumfang vor der Pause um `returnGrowthFactor` steigen statt
  um `macroGrowthFactor`, nie darüber hinaus.
- Die Nutzernachricht von Tag, Woche und Gesamtplan nennt Angabe, geltenden Anteil und die Werte aus Health; Claude
  soll in der Begründung sagen, dass der Plan von der Angabe ausgeht.
- Die Anteile sind Praxiswerte (Modul: `planning.startingLevel`), im Betatest justieren.

Beispiel: 6000 m pro Woche und 2500 m am Stück angegeben, Pause 2 bis 8 Wochen, Health zeigt 570 m pro Woche. Der
Plan rechnet mit 4200 m pro Woche und 1750 m längster Einheit: Eine Einheit darf bis 2150 m lang sein (1750 × 1,25,
abgerundet), die Woche bis 5450 m. Ohne Angabe wären es 800 m je Einheit (Wiedereinstieg).

Beim Schwimmen liegen die Untergrenzen seit dem Betatest höher als im früheren Schwimmplan (1500 statt 1000 m je
Einheit, 2500 statt 1500 m in 7 Tagen): Mit wenig Schwimmverlauf blieben sonst oft nur wenige hundert Meter am Tag.

## Zielarten und Wochenraster (P2)

Das Ziel hat eine Art (`training_goal.kind`): Wettkampf, Zeit über eine Strecke, Strecke schaffen oder fit werden und
bleiben. Zeit und Strecke planen wie ein Wettkampf, nur steht am Zieltag ein eigener Versuch statt eines Rennens. Ein
Fitnessziel hat keine Disziplinen, kein Zuspitzen und keine Zielwoche: Jede Woche bis zum Ende des Planungszeitraums
ist Aufbau, der Umfang steigt bis zu den Wochenminuten und bleibt dann; Tests sind bis zum Ende erlaubt
(`phaseOf`, `taperWeeks`, `testBlackoutReason` in `limits.ts`).

Der Wochenraster (`training_goal.weekly_schedule`, `schedule.ts`) legt je Wochentag fest, ob, wann und wie lange
trainiert wird, auf Wunsch mit fester Sportart. Er ersetzt Trainingstage und Wochenstunden des Ziels:

| Regel | Tag | Sieben Tage | Gesamtplan |
|---|---|---|---|
| Tag ohne Training | Pflicht-Ruhetag ("Ruhetag laut Wochenraster") | Einheiten gestrichen | – |
| Minuten des Tages | Tagesgrenze (bei schlechter Erholung die Hälfte) | Tagesgrenze je Tag | – |
| Feste Sportart | andere Sportarten heute gesperrt | andere Sportarten gestrichen | – |
| Summe | – | höchstens die Summe pro Woche | höchstens die Summe pro Woche |
| Trainingstage | – | höchstens die Tage mit Training | Einheiten höchstens zwei je Trainingstag |

Eine feste Sportart ohne Schwerpunkt zählt nicht. Passt die feste Sportart wegen ihrer Grenzen nicht, wird die Einheit
kürzer oder fällt aus; eine andere Sportart kommt dafür nicht. Ohne Wochenraster (App vor P2) gelten Trainingstage und
Wochenstunden des Ziels wie bisher.

In der App liegt der Wochenraster getrennt vom Ziel (`WeeklySchedule`, Einstellungen → Wochenraster). Ohne gespeicherten
Wochenraster rechnet die App einen aus Trainingstagen und Stunden des Ziels. Trainingstage und Stunden im Snapshot kommen
aus dem Wochenraster, damit ältere Server dasselbe sehen. Der Gesamtplan hängt nur an Zielart, Disziplinen, Zieltag und
Schwerpunkten (`TrainingGoal.planKey`); eine Änderung am Wochenraster gilt ab der nächsten Abstimmung der sieben Tage.
Beim ersten Start führt die App durch Ziel, Wochenraster und Startniveau (`OnboardingView`), erst danach entsteht der
Gesamtplan. Wer die App schon nutzt, sieht die Einrichtung nach dem Update einmal, vorausgefüllt mit dem gespeicherten Ziel.

## Ziel ändern mit Entwurf (P3)

In den Einstellungen ist das Ziel ein Entwurf; erst "Übernehmen" ändert es. Vorher zeigt die App, was mit dem
Gesamtplan passiert (`TrainingGoal.change(to:)`):

| Art | Beispiele | Wirkung |
|---|---|---|
| Feinjustierung | Zielzeit, Ankommen statt Zielzeit, Schwerpunkte, Begleitsport, Zieltag um höchstens 14 Tage | sofort übernommen, Gesamtplan bleibt, fließt in die nächste Fortschreibung |
| Neues Ziel | Zielart, Zieldisziplin dazu oder weg, Strecke, Zieltag um mehr als 14 Tage | neue Zielversion, neuer Gesamtplan; die laufende Woche des alten bleibt |

Ein neues Ziel geht höchstens alle 7 Tage (`UserDefaultsTrainingGoalStore.lockDays`), außer der Zieltag ist vorbei. In
der Sperre lässt sich der Entwurf vormerken; die App übernimmt ihn beim ersten Lesen des Zustands nach dem Ende der
Sperre. Der Gesamtplan gehört zu einer Zielversion (`goal-vN`) statt zu `planKey`; ein Plan von vor P3 bekommt die
Version, solange er zu `planKey` passt. Die Einrichtung beim ersten Start speichert direkt und sperrt nichts.

## Fortschreibung (P4)

Der Gesamtplan entsteht nur beim Start und bei einem neuen Ziel neu; "Neu berechnen" gibt es nicht mehr. Danach schreibt
die App ihn fort (`POST /v1/plan/macro/review`, Timeout wie der Gesamtplan):

| Anlass | Wann | Wie |
|---|---|---|
| `scheduled` | alle 14 Tage ab dem Montag der Woche der Erstellung bzw. der letzten Fortschreibung | automatisch beim ersten Öffnen, im Hintergrund |
| `pause` | gemeldete Pause (Einstellungen → Pause melden) von mindestens 7 Tagen, eine laufende zählt sofort | automatisch, einmal je Meldung |
| `low_compliance` | zwei abgeschlossene Wochen nacheinander unter 60 % des Plans in einer Sportart | die App schlägt es im Tab Plan vor, der Athlet bestätigt |

Die App schickt den Plan ab vier Wochen vor der laufenden Woche, das Ist dieser Wochen je Sportart in der Planeinheit
(`MacroActualCalculator`), Anlass, Pause und optional Feedback. Claude antwortet mit Bilanz (`summary`), Änderungen und
den Wochen; die App behält die vergangenen Wochen und die laufende Woche des bisherigen Plans und ersetzt nur die
Wochen danach. Jede Fortschreibung hängt als `MacroReview` am Plan; danach geht wieder genau eine Feedback-Runde
(`canGiveFeedback`). Ein Fehlschlag lässt den Plan stehen; versucht wird höchstens einmal am Tag je Anlass. Nach einer
Fortschreibung stimmt die App die sieben Tage neu ab und meldet sich mit einer Mitteilung.

Neue bestätigte Leistungswerte seit dem letzten Stand (Test oder Eingabe, `PerformanceProfile.changes(since:)`) gehen
als `performance_changes` mit dem Wert davor mit ("CSS-Pace 1:50 → 1:44 pro 100 m"). Die Zonen der Tagespläne richten
sich schon ab dem Übernehmen danach; Umfänge ändert Claude nur, wenn ein Wert deutlich vom Bisherigen abweicht.

## Übergreifende Regeln

**Tag:** höchstens zwei Einheiten, höchstens eine harte. Ein Tag hat höchstens die Hälfte der Wochenstunden des
Ziels (mindestens 45 min), bei schlechter Erholung die Hälfte davon. Harte Einheiten heute nur, wenn gestern und
heute nichts Hartes war, die letzte harte Einheit mindestens zwei Tage zurückliegt und in den letzten sechs Tagen
höchstens ein harter Tag war; sonst höchstens `moderate`. Je Sportart gilt heute zusätzlich der Rest der rollenden
Wochengrenze.

**Sieben Tage:** genau die angefragten Tage; ein Tag ohne Zeit wird Ruhetag. Höchstens zwei harte Tage über alle
Sportarten, nie hintereinander, auch nicht direkt nach einem harten Tag vor dem Plan. Nicht mehr Trainingstage als im
Ziel, mindestens ein Ruhetag, insgesamt höchstens die Wochenstunden. Je Sportart Einheiten- und Wochengrenze und die
Zahl der Einheiten. Etwa 80 % der Zeit locker (Drei-Zonen-Modell): Von jeder mittleren oder harten Einheit zählt die
Hälfte als intensiv (Ein- und Auslaufen, Pausen); sind ab drei Einheiten mehr als 20 % der Wochenminuten intensiv,
werden mittlere Einheiten locker, die längsten zuerst (Tests und harte Einheiten bleiben). Was nicht passt, wird gekürzt, leichter oder gestrichen; jede Korrektur steht in `adjustments`
und als Hinweis in der Begründung.

**Gesamtplan:** Claude liefert ihn in Abschnitten von einer bis sechs Wochen: je Sportart den Umfang der ersten und
der letzten Belastungswoche (dazwischen gleichmäßig), die Einheiten je Woche und, wenn die letzte Woche entlastet, deren
Umfang. Der Server rechnet die Abschnitte in Wochen um und prüft dann jede Woche. Woche für Woche wäre die Antwort bei
40 Wochen und drei Sportarten zu lang für das Zeitlimit von 85 s (erster echter Lauf am 03.10.2026: Zeitüberschreitung).
Die Phase setzt der Code (Aufbau, zielspezifisch in den 8 Wochen vor dem Zuspitzen, Zuspitzen,
Zielwoche, nach dem Ziel erhalten). Je Sportart steigt der Umfang höchstens um 10 % über die letzte Woche ohne
Entlastung; spätestens nach drei Belastungswochen kommt eine Entlastungswoche mit höchstens 70 %. Zuspitzen: bei
Wettkämpfen ab vier Stunden zwei Wochen (60 % und 45 % des Höhepunkts), sonst eine (55 %), jeweils mit so vielen
Einheiten wie in der letzten Belastungswoche (Bosquet 2007: Umfang 41 bis 60 % weniger, Intensität und Häufigkeit
bleiben). Die Zielwoche hat höchstens
die Hälfte des Höhepunkts, mindestens aber das 1,2-Fache des Wettkampfs. Über alle Sportarten höchstens die
Wochenstunden. Reicht die Zeit für eine Disziplin nicht, um mit 10 % pro Woche die Wettkampfstrecke aufzubauen, sagt
der Prompt das, und Claude soll es ehrlich in der Begründung sagen.

**Feedback zum Gesamtplan:** Claude überarbeitet den Plan nach dem Feedback und nennt die Änderungen (höchstens acht).
Der neue Plan geht durch dieselbe Sicherheitsschicht; Feedback ändert nie die Grenzen.

## Leistungstests

Die Module bringen ihre Tests mit (CSS-Test 400/200 m und 1000-m-Test beim Schwimmen, 30-Minuten-Test bei Rad und
Laufen, lockerer Einstiegstest beim Laufen) und die Schritte dazu. Ein Test ist im Plan eine Einheit vom Typ `test`
mit `test` (Kennung, Name, Vollbelastung ja oder nein, welche Werte er ermittelt). Die Schritte setzt immer der
Server ein, nicht Claude.

**Termine im Gesamtplan setzt der Code:** ohne bestätigten Wert so früh wie möglich (die erste Woche mit noch
mindestens drei Tagen), sonst nach dem Intervall, Wiederholungen bevorzugt in einer Entlastungswoche. Der erste Test
ist ohne tragfähige Grundlage (längste Einheit kürzer als die Testbelastung) oder im Wiedereinstieg der ohne
Vollbelastung; könnte der Athlet ihn heute noch nicht machen, kommt er frühestens in der Woche danach. Höchstens zwei
Tests pro Woche, nie beim Zuspitzen, in der Zielwoche oder in den 14 Tagen vor dem Ziel.

**Woche und Tag:** höchstens ein Test pro Tag und je Sportart pro Woche, nie an zwei Tagen hintereinander. Ein Test
mit Vollbelastung ist ein harter Tag und braucht eine längste Einheit mindestens so lang wie die Testbelastung, der
Einstiegstest zählt nicht als hart. Die ganze Testeinheit muss in die Grenze der Sportart und die Tagesgrenze passen.
Tests gehen beim Verteilen der harten Tage vor normalen harten Einheiten. Passt ein Test nicht, wird er eine lockere
Einheit ("Locker statt Leistungstest") und der Grund steht in `adjustments`.

Neue Werte aus einem Test gelten erst, wenn der Athlet sie in der App bestätigt (ab T4).

## Prompts

Je Plan ein fester System-Prompt (Tag, Woche, Gesamtplan, Überarbeitung), gebaut aus den Regelblöcken der Module
(`promptRules`, Ziele, Maße, Tests). Er enthält keine Daten des Athleten und bleibt so für das Prompt-Caching gleich.
Die Nutzernachricht bringt Snapshot, Grenzen, Vorgaben und Testangebote; Wünsche und Feedback stehen dort nur als
JSON-String und ändern nie eine Grenze.

Jede Tagesgrenze steht mit ihrer Rechnung in der Nutzernachricht (je Einheit, 7-Tage-Grenze und was davon schon
trainiert ist, Kürzung wegen schlechter Erholung). Liegt die Vorgabe des Wochenplans über der Grenze oder geht eine
Sportart heute nicht, soll Claude das in der Begründung in einfachen Worten sagen. Begründung und Hinweise liest der
Athlet: Der System-Prompt verbietet darin Feldnamen wie `acute_chronic_ratio`.

## Bewertung

Acht Szenarien in `backend/scenarios/multisport/` (Sprint-Einsteiger, Olympisch mit Schwerpunkt Schwimmen, 70.3,
nur Laufen, nur Schwimmen, Laufen nach Verletzungspause, Einsteiger ohne Profil, Schwimmen nach Pause mit
selbst angegebenem Startniveau) laufen wie in der App durch den
echten Service: Gesamtplan, die nächsten sieben Tage mit seiner Vorgabe, der Tag mit der Vorgabe der Woche und bei
Feedback die Überarbeitung. Automatische Prüfungen zeigen, wo man hinschauen sollte (Verteilung nach Schwerpunkten,
Höhepunkt vor dem Zuspitzen, Einstiegstests früh, Tests aus dem Gesamtplan in der Woche, Begründung mit Ziel und
ehrlich bei knapper Zeit).

```
cd backend
EVAL_REPLAY=1 npm run eval:multisport                     # Aufzeichnungen abspielen: ohne Netz, ohne Kosten
ANTHROPIC_API_KEY=... EVAL_RECORD=1 npm run eval:multisport > ../docs/eval-runs/multisport-$(date +%F).md
EVAL_ONLY=01,06 ...                                        # nur einige Szenarien
scripts/eval-in-docker.sh multisport                      # auf dem Server, nimmt die Antworten gleich auf
```

Die Aufzeichnungen liegen in `backend/scenarios/multisport/recorded/`. Bis zum ersten echten Lauf sind sie
synthetisch (von Hand nach Regeln gebaut, Modell `synthetisch`); sie zeigen den Ablauf und die Sicherheitsschicht,
nicht Claudes Qualität. `test/plan/multi/scenarios.test.ts` spielt sie in der CI ab. Ein Lauf mit Claude kostet für
alle neun Szenarien 29 Anfragen. Die Szenarien 08 und 09 sind noch synthetisch (Modell `synthetisch`), bis sie einmal
mit Claude aufgenommen sind (`EVAL_ONLY=08,09`). Nur ein Szenario, in dem jede Stufe klappt, ersetzt seine Aufzeichnung; schlägt ein
Aufruf fehl, zeigt die Konsole die Meldung und die Dauer.

## Eine Sportart dazunehmen

Ein neues Modul mit `planning` (Grenzen, Einheit, Tempo, Schrittregeln, Testschritte, `promptRules`) reicht. Grenzen,
Prompts, Sicherheitsschicht und Bewertung lesen alles aus der Registry; die Test-Sportart Rudern läuft in den Tests
durch dieselben Prüfungen. Alle Schritte für App und Server: [Neue Sportart hinzufügen](neue-sportart.md).
