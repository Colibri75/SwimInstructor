# Bewertung der Planung für mehrere Sportarten (Plan v2)

Quelle: Claude (claude-opus-5-5, Effort high), mit Aufzeichnung.
Die Prüfungen sind Heuristiken, die zeigen, wo man hinschauen sollte; die harten Grenzen setzt die Sicherheitsschicht.

## Überblick

| Szenario | Stufe | Status | Korrekturen | Prüfungen erfüllt |
|---|---|---|---|---|
| 02-olympisch-schwimmen | Gesamt | ok | 8 | 5/5 |
| 02-olympisch-schwimmen | 7 Tage | ok | 0 | 3/3 |
| 02-olympisch-schwimmen | Tag | ok | 0 | 2/3 |
| 02-olympisch-schwimmen | Feedback | ok | 6 | 2/2 |
| 06-laufen-nach-verletzung | Gesamt | ok | 12 | 4/5 |
| 06-laufen-nach-verletzung | 7 Tage | ok | 0 | 1/3 |
| 06-laufen-nach-verletzung | Tag | ok | 0 | 2/2 |
| 06-laufen-nach-verletzung | Feedback | ok | 13 | 2/2 |

Geschätzte Kosten: $1.22 (8 Aufrufe).

## 02-olympisch-schwimmen

Olympische Distanz im Juli, Schwerpunkt Schwimmen (50 %). Erfahrener Schwimmer mit getesteter CSS, fährt etwas Rad, läuft kaum. Danach Feedback: mehr Laufen.

Heute 2026-09-30, Ziel am 2027-07-04: Schwimmen 1500 m, Radfahren 40000 m, Laufen 10000 m; Schwerpunkte Schwimmen 50 %, Radfahren 30 %, Laufen 20 %; 5 Tage, 7.5 h pro Woche.

### Gesamtplan

Bis zur Zielwoche sind es 39 Wochen; du startest bei etwa 3600 m Schwimmen, 100 min Rad und 30 min Laufen pro Woche (rund 3,5 h). Am Höhepunkt in den Wochen 37 und 38 stehen 9500 m Schwimmen, 155 min Rad und 100 min Laufen, zusammen etwa 445 von 450 erlaubten Minuten. Gesteigert wird höchstens um 10 % pro Woche, beim Laufen bewusst langsamer in 3-min-Schritten von heute 15 min Wochenschnitt aus, mit einer Entlastungswoche nach jeweils höchstens drei Belastungswochen. Das Schwimmen bekommt den größten Anteil; das Rad trägt anfangs mehr Umfang, solange das Schwimmen noch wächst, und wird später auf etwa 155 min gehalten. Mit deiner CSS von 1:45/100 m sind die 1500 m in 30 min gut erreichbar, die 40 km in 80 min (30 km/h) sind ehrgeizig, aber realistisch, und der 10-km-Lauf bleibt wegen der knappen Laufbasis der Engpass. Hinweis: Zur Sicherheit an 8 Stellen angepasst, die Wochen zeigen die geprüften Umfänge.

| Woche ab | Phase | Entlastung | Schwimmen | Radfahren | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 3600 m / 3× | 100 min / 2× | 30 min / 2× | 202 | Radfahren: 30-Minuten-Test, Laufen: Einstiegstest locker | Einstieg: Schwimmtechnik und lockere Grundlage |
| 2026-10-05 | Aufbau | – | 3800 m / 3× | 110 min / 2× | 35 min / 2× | 221 | – | Einstieg: Schwimmtechnik und lockere Grundlage |
| 2026-10-12 | Aufbau | – | 4000 m / 3× | 120 min / 2× | 35 min / 2× | 235 | – | Einstieg: Schwimmtechnik und lockere Grundlage |
| 2026-10-19 | Aufbau | ja | 2800 m / 3× | 80 min / 2× | 20 min / 1× | 156 | – | Einstieg: Schwimmtechnik und lockere Grundlage |
| 2026-10-26 | Aufbau | – | 4400 m / 3× | 125 min / 3× | 40 min / 2× | 253 | Schwimmen: CSS-Test 400/200 m | Grundlage aufbauen, Laufen langsam steigern |
| 2026-11-02 | Aufbau | – | 4800 m / 3× | 135 min / 3× | 40 min / 2× | 271 | – | Grundlage aufbauen, Laufen langsam steigern |
| 2026-11-09 | Aufbau | – | 5200 m / 3× | 145 min / 3× | 45 min / 2× | 294 | – | Grundlage aufbauen, Laufen langsam steigern |
| 2026-11-16 | Aufbau | ja | 3600 m / 3× | 100 min / 3× | 30 min / 2× | 202 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Grundlage aufbauen, Laufen langsam steigern |
| 2026-11-23 | Aufbau | – | 5600 m / 4× | 150 min / 3× | 50 min / 3× | 312 | – | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-11-30 | Aufbau | – | 6000 m / 4× | 155 min / 3× | 50 min / 3× | 325 | – | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-12-07 | Aufbau | – | 6400 m / 4× | 155 min / 3× | 55 min / 3× | 338 | – | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-12-14 | Aufbau | ja | 4400 m / 4× | 105 min / 3× | 35 min / 2× | 228 | Schwimmen: CSS-Test 400/200 m | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-12-21 | Aufbau | – | 6800 m / 4× | 155 min / 3× | 55 min / 3× | 346 | – | Grundlage, erste CSS-Serien im Wasser |
| 2026-12-28 | Aufbau | – | 7200 m / 4× | 160 min / 3× | 60 min / 3× | 364 | – | Grundlage, erste CSS-Serien im Wasser |
| 2027-01-04 | Aufbau | – | 7600 m / 4× | 160 min / 3× | 65 min / 3× | 377 | – | Grundlage, erste CSS-Serien im Wasser |
| 2027-01-11 | Aufbau | ja | 5300 m / 4× | 110 min / 3× | 45 min / 3× | 261 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Grundlage, erste CSS-Serien im Wasser |
| 2027-01-18 | Aufbau | – | 8000 m / 4× | 160 min / 3× | 65 min / 3× | 385 | – | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-01-25 | Aufbau | – | 8300 m / 4× | 160 min / 3× | 70 min / 3× | 396 | – | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-02-01 | Aufbau | – | 8600 m / 4× | 160 min / 3× | 70 min / 3× | 402 | – | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-02-08 | Aufbau | ja | 6000 m / 4× | 110 min / 3× | 45 min / 3× | 275 | Schwimmen: CSS-Test 400/200 m | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-02-15 | Aufbau | – | 8800 m / 4× | 160 min / 3× | 75 min / 3× | 411 | – | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-02-22 | Aufbau | – | 9000 m / 4× | 160 min / 3× | 80 min / 3× | 420 | – | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-03-01 | Aufbau | – | 9200 m / 4× | 160 min / 3× | 80 min / 3× | 424 | – | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-03-08 | Aufbau | ja | 6400 m / 4× | 110 min / 3× | 55 min / 3× | 293 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-03-15 | Aufbau | – | 9200 m / 4× | 155 min / 3× | 85 min / 3× | 424 | – | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-03-22 | Aufbau | – | 9350 m / 4× | 155 min / 3× | 85 min / 3× | 427 | – | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-03-29 | Aufbau | – | 9500 m / 4× | 155 min / 3× | 90 min / 3× | 435 | – | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-04-05 | Aufbau | ja | 6600 m / 4× | 105 min / 3× | 60 min / 3× | 297 | Schwimmen: CSS-Test 400/200 m | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-04-12 | Aufbau | – | 9200 m / 4× | 150 min / 3× | 90 min / 3× | 424 | – | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-04-19 | Aufbau | – | 9350 m / 4× | 155 min / 3× | 95 min / 3× | 437 | – | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-04-26 | zielspezifisch | – | 9500 m / 4× | 155 min / 3× | 95 min / 3× | 440 | – | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-05-03 | zielspezifisch | ja | 6600 m / 4× | 105 min / 3× | 65 min / 3× | 302 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-05-10 | zielspezifisch | – | 9300 m / 4× | 150 min / 3× | 95 min / 3× | 431 | – | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-05-17 | zielspezifisch | – | 9400 m / 4× | 155 min / 3× | 100 min / 3× | 443 | – | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-05-24 | zielspezifisch | – | 9500 m / 4× | 155 min / 3× | 100 min / 3× | 445 | – | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-05-31 | zielspezifisch | ja | 6600 m / 4× | 105 min / 3× | 70 min / 3× | 307 | Schwimmen: CSS-Test 400/200 m | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-06-07 | zielspezifisch | – | 9500 m / 4× | 155 min / 3× | 100 min / 3× | 445 | – | Höhepunkt: wettkampfnahe Intervalle, Koppeln |
| 2027-06-14 | zielspezifisch | – | 9500 m / 4× | 155 min / 3× | 100 min / 3× | 445 | – | Höhepunkt: wettkampfnahe Intervalle, Koppeln |
| 2027-06-21 | Zuspitzen | – | 5500 m / 3× | 90 min / 2× | 60 min / 2× | 260 | – | Zuspitzen: weniger Umfang, Intensität halten |
| 2027-06-28 | Zielwoche | – | 3000 m / 2× | 60 min / 2× | 40 min / 2× | 160 | – | Zielwoche: kurz, frisch, Wettkampf |

Korrekturen der Sicherheitsschicht:

- Woche ab 19.10.: Radfahren von 85 min auf 80 min begrenzt (Entlastungswoche)
- Woche ab 19.10.: Laufen von 25 min auf 20 min begrenzt (Entlastungswoche)
- Woche ab 14.12.: Radfahren von 110 min auf 105 min begrenzt (Entlastungswoche)
- Woche ab 08.02.: Laufen von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 05.04.: Radfahren von 110 min auf 105 min begrenzt (Entlastungswoche)
- Woche ab 05.04.: Laufen von 65 min auf 60 min begrenzt (Entlastungswoche)
- Woche ab 03.05.: Radfahren von 110 min auf 105 min begrenzt (Entlastungswoche)
- Woche ab 31.05.: Radfahren von 110 min auf 105 min begrenzt (Entlastungswoche)

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 41 % (Schwerpunkt 50 %), Radfahren 40 % (Schwerpunkt 30 %), Laufen 19 % (Schwerpunkt 20 %)
- [x] Höhepunkt vor dem Zuspitzen: höchste Woche ab 2027-05-24 (445 min), Zuspitzen ab 2027-06-21
- [x] Einstiegstests in den ersten zwei Wochen: Radfahren, Laufen
- [x] Leistungstests im Plan: Radfahren ab 2026-09-28; Laufen ab 2026-09-28; Schwimmen ab 2026-10-26; Radfahren ab 2026-11-16; Laufen ab 2026-11-16; Schwimmen ab 2026-12-14; Radfahren ab 2027-01-11; Laufen ab 2027-01-11; Schwimmen ab 2027-02-08; Radfahren ab 2027-03-08; Laufen ab 2027-03-08; Schwimmen ab 2027-04-05; Radfahren ab 2027-05-03; Laufen ab 2027-05-03; Schwimmen ab 2027-05-31
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 11314 Token ein, 10620 Token aus, 102.2 s, ca. $0.258

### Die nächsten sieben Tage

Erholung ist gut und die Belastung liegt mit einem Verhältnis von 1,08 im grünen Bereich, daher startet die Woche mit dem lockeren Lauf-Einstiegstest und legt den 30-Minuten-Radtest auf den frischen Samstag nach einem Ruhetag. Das Schwimmen trägt mit 4300 m in drei lockeren Technik- und Grundlageneinheiten den größten Anteil, weil Rad (120 min) und Laufen (50 min) an ihren Grenzen bzw. am vorsichtigen Laufaufbau liegen. Der Samstag ist der einzige harte Tag, alles andere bleibt locker im Sinne der Aufbauphase. Mit 277 Tagen bis zum Ziel ist die Olympische Distanz gut erreichbar.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Laufen 30 min locker (Einstiegstest locker) | 30 | Lauf-Einstiegstest locker |
| Donnerstag 2026-10-01 | Schwimmen 1500 m locker (Technik) | 30 | Schwimmtechnik |
| Freitag 2026-10-02 | Ruhetag | 0 | Ruhetag |
| Samstag 2026-10-03 | Radfahren 58 min hart (30-Minuten-Test) | 58 | Rad-Schwellentest |
| Sonntag 2026-10-04 | Schwimmen 1400 m locker (Ausdauer) + Laufen 20 min locker (Regeneration) | 48 | Lockere Grundlage Schwimmen und Laufen |
| Montag 2026-10-05 | Ruhetag | 0 | Ruhetag |
| Dienstag 2026-10-06 | Radfahren 60 min locker (Ausdauer) + Schwimmen 1400 m locker (Technik) | 88 | Grundlage Rad und Schwimmtechnik |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 34 % (Schwerpunkt 50 %), Radfahren 46 % (Schwerpunkt 30 %), Laufen 20 % (Schwerpunkt 20 %)
- [x] Tests aus dem Gesamtplan eingeplant: Laufen am 2026-09-30, Radfahren am 2026-10-03
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9884 Token ein, 3099 Token aus, 30.7 s, ca. $0.102

### Heute

Laut Wochenplan steht heute der lockere Einstiegstest Laufen an. Mit 25 min liegt er genau auf deiner längsten Laufeinheit der letzten 4 Wochen (25 min) und innerhalb der Grenze von 30 min. Bei guter Erholung und einem Belastungsverhältnis von 1,08 ergänzt eine kurze Technikeinheit Schwimmen über 800 m deinen Schwerpunkt Schwimmen (50 %), ohne dass der Tag hart wird. In der Aufbauphase mit 39 Wochen bis zur Zielwoche zählen jetzt Grundlage, Technik und verlässliche Laufwerte für die Olympische Distanz.

**Laufen: Leistungstest: Einstiegstest locker**, locker, 30 min, ca. 30 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Lauf locker | 25 min | perceived_effort 3 | 0 s | Locker, gleichmäßig | 25 Minuten locker und gleichmäßig, so dass du dich noch unterhalten kannst. Pace und Puls ergeben eine erste Schätzung deiner Schwelle. |
| Gehen | 5 min | perceived_effort 1 | 0 s | Gehen | Fünf Minuten gehen. |

**Schwimmen: Technik**, locker, 800 m, ca. 19 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einschwimmen | 200 m | perceived_effort 3 | 30 s | Locker kraulen | Schwimm 200 m locker Kraul und atme ruhig aus, während das Gesicht im Wasser ist. |
| Technik Abschlagschwimmen | 4 × 50 m | perceived_effort 3 | 20 s | Hand trifft Hand | Beim Abschlagschwimmen bleibt ein Arm vorne gestreckt, bis die andere Hand ihn nach dem Zug berührt, erst dann zieht er. So übst du eine lange Gleitphase und einen ruhigen Armzug. |
| Hauptteil | 3 × 100 m | pace_per_100m 118 | 20 s | Gleichmäßig 1:58 | Schwimm jede 100 m gleichmäßig in etwa 1:58 pro 100 m, deutlich langsamer als deine CSS-Pace von 1:45. Achte auf einen langen Zug und gleichmäßige Atmung. |
| Ausschwimmen | 100 m | perceived_effort 2 | 0 s | Ganz locker | Schwimm 100 m ganz locker in einer Lage deiner Wahl und lass die Schultern entspannen. |

Die Sicherheitsschicht hat nichts geändert.

> Lauf den Einstiegstest wirklich locker, du solltest dich dabei unterhalten können.
> Schwimm erst nach dem Lauftest oder mit einigen Stunden Abstand, damit der Test unverfälscht bleibt.
> Die Pulswerte für Rad und Laufen sind nur geschätzt; der heutige Test hilft, sie genauer zu machen.

Prüfungen:

- [ ] Vorgabe des Wochenplans: geplant Laufen + Schwimmen, Vorgabe Laufen
- [x] Leistungstest der Vorgabe: Einstiegstest locker mit 2 Schritten
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 10940 Token ein, 1928 Token aus, 20.2 s, ca. $0.082

### Feedback zum Gesamtplan

Feedback: "Mehr Laufen bitte, beim Laufen habe ich am meisten Nachholbedarf. Dafür darf das Schwimmen etwas weniger werden."

Änderungen laut Claude:

- Laufen beginnt mit 42 statt 30 Minuten pro Woche und erreicht am Höhepunkt 135 statt 100 Minuten.
- Ab Woche 5 gibt es drei statt zwei Laufeinheiten pro Woche.
- Laufen steigt nur um etwa 10 Prozent pro Woche; schneller geht es wegen der Laufgrenzen nicht.
- Schwimmen beginnt mit 3400 statt 3600 Metern und erreicht am Höhepunkt 8000 statt 9500 Meter.
- Radfahren bleibt ab Woche 9 bei 150 statt 155 bis 160 Minuten, damit die Woche unter 450 Minuten bleibt.
- Entlastungswochen bleiben im Rhythmus aus drei Belastungswochen und einer Entlastungswoche.
- Zuspitzen: Laufen 80 statt 60 Minuten, Schwimmen 4800 statt 5500 Meter.
- Zielwoche: Laufen 50 statt 40 Minuten, Schwimmen und Rad bleiben gleich.

| Woche ab | Phase | Entlastung | Schwimmen | Radfahren | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 3400 m / 3× | 100 min / 2× | 40 min / 2× | 208 | Radfahren: 30-Minuten-Test, Laufen: Einstiegstest locker | Einstieg: Schwimmtechnik, lockere Grundlage, Laufen |
| 2026-10-05 | Aufbau | – | 3600 m / 3× | 110 min / 2× | 45 min / 2× | 227 | – | Einstieg: Schwimmtechnik, lockere Grundlage, Laufen |
| 2026-10-12 | Aufbau | – | 3800 m / 3× | 120 min / 2× | 50 min / 2× | 246 | – | Einstieg: Schwimmtechnik, lockere Grundlage, Laufen |
| 2026-10-19 | Aufbau | ja | 2650 m / 3× | 80 min / 2× | 35 min / 2× | 168 | – | Einstieg: Schwimmtechnik, lockere Grundlage, Laufen |
| 2026-10-26 | Aufbau | – | 4000 m / 3× | 125 min / 3× | 55 min / 3× | 260 | Schwimmen: CSS-Test 400/200 m | Grundlage aufbauen, drei lockere Läufe pro Woche |
| 2026-11-02 | Aufbau | – | 4300 m / 3× | 135 min / 3× | 60 min / 3× | 281 | – | Grundlage aufbauen, drei lockere Läufe pro Woche |
| 2026-11-09 | Aufbau | – | 4600 m / 3× | 145 min / 3× | 65 min / 3× | 302 | – | Grundlage aufbauen, drei lockere Läufe pro Woche |
| 2026-11-16 | Aufbau | ja | 3200 m / 3× | 100 min / 3× | 45 min / 3× | 209 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Grundlage aufbauen, drei lockere Läufe pro Woche |
| 2026-11-23 | Aufbau | – | 4900 m / 4× | 150 min / 3× | 70 min / 3× | 318 | – | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-11-30 | Aufbau | – | 5200 m / 4× | 150 min / 3× | 75 min / 3× | 329 | – | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-12-07 | Aufbau | – | 5500 m / 4× | 150 min / 3× | 80 min / 3× | 340 | – | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-12-14 | Aufbau | ja | 3850 m / 4× | 105 min / 3× | 55 min / 3× | 237 | Schwimmen: CSS-Test 400/200 m | Grundlage, Schwimmtechnik, längere Ausfahrt |
| 2026-12-21 | Aufbau | – | 5800 m / 4× | 150 min / 3× | 85 min / 3× | 351 | – | Grundlage, erste CSS-Serien, längerer Lauf |
| 2026-12-28 | Aufbau | – | 6100 m / 4× | 150 min / 3× | 90 min / 3× | 362 | – | Grundlage, erste CSS-Serien, längerer Lauf |
| 2027-01-04 | Aufbau | – | 6400 m / 4× | 150 min / 3× | 95 min / 3× | 373 | – | Grundlage, erste CSS-Serien, längerer Lauf |
| 2027-01-11 | Aufbau | ja | 4450 m / 4× | 105 min / 3× | 65 min / 3× | 259 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Grundlage, erste CSS-Serien, längerer Lauf |
| 2027-01-18 | Aufbau | – | 6700 m / 4× | 150 min / 3× | 100 min / 3× | 384 | – | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-01-25 | Aufbau | – | 6950 m / 4× | 150 min / 3× | 110 min / 3× | 399 | – | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-02-01 | Aufbau | – | 7200 m / 4× | 150 min / 3× | 115 min / 3× | 409 | – | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-02-08 | Aufbau | ja | 5000 m / 4× | 105 min / 3× | 80 min / 3× | 285 | Schwimmen: CSS-Test 400/200 m | Grundlage, Tempoabschnitte auf dem Rad |
| 2027-02-15 | Aufbau | – | 7400 m / 4× | 150 min / 3× | 120 min / 3× | 418 | – | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-02-22 | Aufbau | – | 7600 m / 4× | 150 min / 3× | 120 min / 3× | 422 | – | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-03-01 | Aufbau | – | 7800 m / 4× | 150 min / 3× | 125 min / 3× | 431 | – | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-03-08 | Aufbau | ja | 5450 m / 4× | 105 min / 3× | 85 min / 3× | 299 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Grundlage, längerer Dauerlauf, CSS-Serien |
| 2027-03-15 | Aufbau | – | 7900 m / 4× | 150 min / 3× | 130 min / 3× | 438 | – | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-03-22 | Aufbau | – | 7950 m / 4× | 150 min / 3× | 130 min / 3× | 439 | – | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-03-29 | Aufbau | – | 8000 m / 4× | 150 min / 3× | 130 min / 3× | 440 | – | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-04-05 | Aufbau | ja | 5600 m / 4× | 105 min / 3× | 90 min / 3× | 307 | Schwimmen: CSS-Test 400/200 m | Grundlage festigen, Schwelle auf dem Rad dosiert |
| 2027-04-12 | Aufbau | – | 8000 m / 4× | 150 min / 3× | 130 min / 3× | 440 | – | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-04-19 | Aufbau | – | 8000 m / 4× | 150 min / 3× | 135 min / 3× | 445 | – | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-04-26 | zielspezifisch | – | 8000 m / 4× | 150 min / 3× | 135 min / 3× | 445 | – | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-05-03 | zielspezifisch | ja | 5600 m / 4× | 105 min / 3× | 90 min / 3× | 307 | Radfahren: 30-Minuten-Test, Laufen: 30-Minuten-Test | Übergang: Schwelle und erste Koppeleinheiten |
| 2027-05-10 | zielspezifisch | – | 8000 m / 4× | 150 min / 3× | 135 min / 3× | 445 | – | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-05-17 | zielspezifisch | – | 8000 m / 4× | 150 min / 3× | 135 min / 3× | 445 | – | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-05-24 | zielspezifisch | – | 8000 m / 4× | 150 min / 3× | 135 min / 3× | 445 | – | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-05-31 | zielspezifisch | ja | 5600 m / 4× | 105 min / 3× | 90 min / 3× | 307 | Schwimmen: CSS-Test 400/200 m | Wettkampftempo, Koppeltraining Rad-Lauf |
| 2027-06-07 | zielspezifisch | – | 8000 m / 4× | 150 min / 3× | 135 min / 3× | 445 | – | Höhepunkt: wettkampfnahe Intervalle, Koppeln |
| 2027-06-14 | zielspezifisch | – | 8000 m / 4× | 150 min / 3× | 135 min / 3× | 445 | – | Höhepunkt: wettkampfnahe Intervalle, Koppeln |
| 2027-06-21 | Zuspitzen | – | 4800 m / 3× | 90 min / 2× | 80 min / 3× | 266 | – | Zuspitzen: weniger Umfang, Intensität halten |
| 2027-06-28 | Zielwoche | – | 3000 m / 2× | 60 min / 2× | 50 min / 2× | 170 | – | Zielwoche: kurz, frisch, Wettkampf |

Korrekturen der Sicherheitsschicht:

- Woche ab 19.10.: Radfahren von 85 min auf 80 min begrenzt (Entlastungswoche)
- Woche ab 04.01.: Laufen von 100 min auf 95 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 11.01.: Laufen von 70 min auf 65 min begrenzt (Entlastungswoche)
- Woche ab 08.03.: Laufen von 90 min auf 85 min begrenzt (Entlastungswoche)
- Woche ab 03.05.: Laufen von 95 min auf 90 min begrenzt (Entlastungswoche)
- Woche ab 31.05.: Laufen von 95 min auf 90 min begrenzt (Entlastungswoche)

Prüfungen:

- [x] Änderungen genannt: 8
- [x] Plan geändert: 40 Wochen anders

Modell `claude-opus-5-5`, 16544 Token ein, 9369 Token aus, 86.5 s, ca. $0.254

## 06-laufen-nach-verletzung

Halbmarathon im März nach sechs Wochen Laufpause (Knie). Hält sich mit Rad fit, Schwerpunkt Laufen 60 %, Rad 40 % als Ausgleich. Wünscht flache Strecken, danach Feedback: mehr Rad am Anfang.

Heute 2026-09-30, Ziel am 2027-03-21: Laufen 21097 m; Schwerpunkte Laufen 60 %, Radfahren 40 %; 5 Tage, 5 h pro Woche.

Wunsch für die Woche: "Mein Knie ist noch empfindlich: beim Laufen nur flach und locker, keine Intervalle."

### Gesamtplan

Bis zur Zielwoche sind es 24 Wochen, geplant als sechs Aufbauabschnitte, eine Woche Zuspitzen und die Zielwoche, jeweils mit Entlastungswochen nach spätestens drei Belastungswochen. Nach 45 Tagen Laufpause steigst du locker mit 55 min Laufen in 3 Einheiten ein und steigerst um höchstens etwa 8 bis 9 % pro Woche bis zum Höhepunkt von 180 min. Das Rad startet bei 140 min (jetzt 110 min Schnitt) und trägt anfangs die Ausdauer bis 190 min. Später gibt es Zeit an das Laufen ab und liegt am Höhepunkt bei 120 min, insgesamt also bei 300 min. Mit einem getesteten Schwellentempo von 5:15/km sind 2:00 h für 21,1 km realistisch, sofern der Laufaufbau verletzungsfrei gelingt. Im Wochenplan dürfen dafür nur die Long Runs schrittweise in Richtung 90 bis 100 min wachsen. Hinweis: Zur Sicherheit an 12 Stellen angepasst, die Wochen zeigen die geprüften Umfänge.

| Woche ab | Phase | Entlastung | Radfahren | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 140 min / 2× | 55 min / 3× | 195 | Radfahren: 30-Minuten-Test | Lauf-Wiedereinstieg locker, Rad-Grundlage Zone 2 |
| 2026-10-05 | Aufbau | – | 150 min / 2× | 60 min / 3× | 210 | – | Lauf-Wiedereinstieg locker, Rad-Grundlage Zone 2 |
| 2026-10-12 | Aufbau | – | 160 min / 2× | 65 min / 3× | 225 | – | Lauf-Wiedereinstieg locker, Rad-Grundlage Zone 2 |
| 2026-10-19 | Aufbau | ja | 110 min / 2× | 45 min / 3× | 155 | Laufen: Einstiegstest locker | Lauf-Wiedereinstieg locker, Rad-Grundlage Zone 2 |
| 2026-10-26 | Aufbau | – | 165 min / 3× | 70 min / 3× | 235 | – | Grundlage aufbauen, Laufumfang behutsam steigern |
| 2026-11-02 | Aufbau | – | 175 min / 3× | 75 min / 3× | 250 | – | Grundlage aufbauen, Laufumfang behutsam steigern |
| 2026-11-09 | Aufbau | – | 180 min / 3× | 80 min / 3× | 260 | – | Grundlage aufbauen, Laufumfang behutsam steigern |
| 2026-11-16 | Aufbau | ja | 125 min / 3× | 55 min / 3× | 180 | Radfahren: 30-Minuten-Test | Grundlage aufbauen, Laufumfang behutsam steigern |
| 2026-11-23 | Aufbau | – | 180 min / 3× | 85 min / 4× | 265 | – | Grundlage, längerer Lauf, Rad trägt Ausdauer |
| 2026-11-30 | Aufbau | – | 185 min / 3× | 90 min / 4× | 275 | – | Grundlage, längerer Lauf, Rad trägt Ausdauer |
| 2026-12-07 | Aufbau | – | 190 min / 3× | 95 min / 4× | 285 | – | Grundlage, längerer Lauf, Rad trägt Ausdauer |
| 2026-12-14 | Aufbau | ja | 130 min / 3× | 65 min / 4× | 195 | Laufen: 30-Minuten-Test | Grundlage, längerer Lauf, Rad trägt Ausdauer |
| 2026-12-21 | Aufbau | – | 170 min / 2× | 100 min / 4× | 270 | – | Grundlage plus erste Tempoläufe, Long Run wächst |
| 2026-12-28 | Aufbau | – | 170 min / 2× | 110 min / 4× | 280 | – | Grundlage plus erste Tempoläufe, Long Run wächst |
| 2027-01-04 | Aufbau | – | 170 min / 2× | 120 min / 4× | 290 | – | Grundlage plus erste Tempoläufe, Long Run wächst |
| 2027-01-11 | zielspezifisch | ja | 115 min / 2× | 80 min / 4× | 195 | Radfahren: 30-Minuten-Test | Grundlage plus erste Tempoläufe, Long Run wächst |
| 2027-01-18 | zielspezifisch | – | 150 min / 2× | 130 min / 4× | 280 | – | Schwellenläufe und Halbmarathon-Tempo |
| 2027-01-25 | zielspezifisch | – | 145 min / 2× | 140 min / 4× | 285 | – | Schwellenläufe und Halbmarathon-Tempo |
| 2027-02-01 | zielspezifisch | – | 140 min / 2× | 150 min / 4× | 290 | – | Schwellenläufe und Halbmarathon-Tempo |
| 2027-02-08 | zielspezifisch | ja | 95 min / 2× | 105 min / 4× | 200 | Laufen: 30-Minuten-Test | Schwellenläufe und Halbmarathon-Tempo |
| 2027-02-15 | zielspezifisch | – | 130 min / 2× | 165 min / 4× | 295 | – | Höhepunkt: langer Lauf, Wettkampftempo-Abschnitte |
| 2027-02-22 | zielspezifisch | – | 125 min / 2× | 175 min / 4× | 300 | Radfahren: 30-Minuten-Test | Höhepunkt: langer Lauf, Wettkampftempo-Abschnitte |
| 2027-03-01 | zielspezifisch | – | 120 min / 2× | 180 min / 4× | 300 | – | Höhepunkt: langer Lauf, Wettkampftempo-Abschnitte |
| 2027-03-08 | Zuspitzen | – | 70 min / 2× | 105 min / 3× | 175 | – | Zuspitzen: weniger Umfang, kurze Tempoabschnitte |
| 2027-03-15 | Zielwoche | – | 40 min / 1× | 80 min / 3× | 120 | – | Zielwoche: frisch bleiben, Halbmarathon am Sonntag |

Korrekturen der Sicherheitsschicht:

- Woche ab 23.11.: Laufen von 90 min auf 85 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 30.11.: Laufen von 95 min auf 90 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 07.12.: Laufen von 105 min auf 95 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 14.12.: Laufen von 70 min auf 65 min begrenzt (Entlastungswoche)
- Woche ab 21.12.: Laufen von 110 min auf 100 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 28.12.: Laufen von 120 min auf 110 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 04.01.: Laufen von 130 min auf 120 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 11.01.: Laufen von 90 min auf 80 min begrenzt (Entlastungswoche)
- Woche ab 18.01.: Laufen von 140 min auf 130 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 25.01.: Laufen von 150 min auf 140 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 01.02.: Laufen von 160 min auf 150 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 08.02.: Laufen von 110 min auf 105 min begrenzt (Entlastungswoche)

Prüfungen:

- [ ] Schwerpunkte verteilt: Radfahren 59 % (Schwerpunkt 40 %), Laufen 41 % (Schwerpunkt 60 %)
- [x] Höhepunkt vor dem Zuspitzen: höchste Woche ab 2027-02-22 (300 min), Zuspitzen ab 2027-03-08
- [x] Einstiegstests in den ersten zwei Wochen: Radfahren
- [x] Leistungstests im Plan: Radfahren ab 2026-09-28; Laufen ab 2026-10-19; Radfahren ab 2026-11-16; Laufen ab 2026-12-14; Radfahren ab 2027-01-11; Laufen ab 2027-02-08; Radfahren ab 2027-02-22
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9491 Token ein, 3731 Token aus, 37.6 s, ca. $0.113

### Die nächsten sieben Tage

Nach 45 Tagen Laufpause steigst du knieschonend mit drei flachen, lockeren Läufen von 15 bis 20 min (zusammen 55 min) ein, wie gewünscht ohne Intervalle. Bleibt das Knie empfindlich oder schmerzt es, lass es bitte ärztlich abklären. Der Rad-Schwellentest liegt am Freitag nach einem Ruhetag, am Sonntag folgen 80 min lockere Grundlage in Zone 2. Mehr Laufumfang erlauben die Grenzen beim Wiedereinstieg noch nicht, die 2:00 h im März sind bei stabilem Knie mit deinem Schwellentempo von 5:15/km aber realistisch.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Laufen 15 min locker (Regeneration) | 15 | Lauf-Wiedereinstieg locker |
| Donnerstag 2026-10-01 | Ruhetag | 0 | Ruhetag |
| Freitag 2026-10-02 | Radfahren 58 min hart (30-Minuten-Test) | 58 | Rad-Leistungstest |
| Samstag 2026-10-03 | Laufen 20 min locker (Ausdauer) | 20 | Locker statt Leistungstest |
| Sonntag 2026-10-04 | Radfahren 80 min locker (Ausdauer) | 80 | Rad-Grundlage |
| Montag 2026-10-05 | Laufen 20 min locker (Ausdauer) | 20 | Lockerer Lauf |
| Dienstag 2026-10-06 | Ruhetag | 0 | Ruhetag |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [ ] Schwerpunkte verteilt: Radfahren 72 % (Schwerpunkt 40 %), Laufen 28 % (Schwerpunkt 60 %)
- [x] Tests aus dem Gesamtplan eingeplant: Radfahren am 2026-10-02
- [ ] Begründung nennt das Ziel: kein Wort wie "Ziel" oder "Wettkampf" in der Begründung

Modell `claude-opus-5-5`, 8532 Token ein, 2581 Token aus, 25.8 s, ca. $0.086

### Heute

Nach 45 Tagen ohne Lauf und 0 min längster Laufeinheit in den letzten 4 Wochen steigst du heute mit 17 min im Lauf-Geh-Wechsel locker wieder ein, wie im Wochenplan vorgesehen. Die Gesamtlast ist mit einem Verhältnis von 1,09 stabil, die Erholung ist gut, und die 120 Radminuten der letzten 7 Tage geben dir eine solide Grundlage. Für die 21,1 km in 2 h 00 min bleiben 24 Wochen Aufbau. Bei deinem getesteten Schwellentempo von 5:15 pro km ist das Ziel realistisch, wenn der Laufumfang geduldig um etwa 10 % pro Woche wächst.

**Laufen: Regeneration**, locker, 17 min, ca. 17 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einlaufen (Gehen) | 3 min | perceived_effort 2 | 0 s | Zügig gehen | Geh 3 Minuten zügig auf flachem Untergrund, damit sich Muskeln und Gelenke an die Bewegung gewöhnen. |
| Hauptteil Laufen mit Gehpausen | 4 × 2 min | perceived_effort 3 | 60 s | Locker, Gespräch möglich | Lauf jeweils 2 Minuten so locker, dass du dich problemlos unterhalten kannst, mit kurzen, leichten Schritten. Nach jedem Laufabschnitt gehst du 1 Minute. |
| Auslaufen (Gehen) | 2 min | perceived_effort 2 | 0 s | Ruhig ausgehen | Geh 2 Minuten ruhig aus und lass den Atem zur Ruhe kommen. |

Die Sicherheitsschicht hat nichts geändert.

> Lauf lieber zu langsam als zu schnell: Nach 45 Tagen Pause müssen sich Sehnen und Knochen erst wieder an die Stoßbelastung gewöhnen.
> Wenn du während des Laufens oder am Tag danach Schmerzen spürst, sag es im Feedback, dann wechseln wir aufs Rad.
> Trink nach der Einheit etwas und dehne locker Waden und Oberschenkel.

Prüfungen:

- [x] Vorgabe des Wochenplans: geplant Laufen, Vorgabe Laufen
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9609 Token ein, 1738 Token aus, 19.3 s, ca. $0.073

### Feedback zum Gesamtplan

Feedback: "Bitte in den ersten Wochen mehr Rad und weniger Laufen, das Knie braucht noch Zeit."

Änderungen laut Claude:

- Laufen startet mit 45 statt 55 min und bleibt bis Mitte Dezember 10 bis 15 min pro Woche unter dem bisherigen Plan.
- In den Wochen 1 bis 4 gibt es nur zwei kurze, lockere Läufe mit Gehpausen statt drei.
- Mehr Rad in Woche 1 ist nicht möglich, weil 140 min die Grenze sind; ab Woche 2 steigt das Rad auf bis zu 210 statt 190 min.
- Das Rad hat in den Wochen 1 bis 4 und 13 bis 20 drei statt zwei Einheiten, damit die längeren Umfänge verteilt sind.
- In den Wochen 9 bis 12 sind es drei statt vier Läufe, vier Läufe kommen erst ab Woche 13.
- Der Laufhöhepunkt liegt wegen des vorsichtigeren Starts bei 170 statt 180 min.
- Das Rad liegt im Höhepunkt mit 150 bis 130 min etwas höher als bisher, damit der Gesamtumfang erhalten bleibt.
- Den Lauftest in der Woche ab 16.11. machst du nur mit beschwerdefreiem Knie, sonst läufst du stattdessen locker.

| Woche ab | Phase | Entlastung | Radfahren | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 140 min / 3× | 45 min / 2× | 185 | Radfahren: 30-Minuten-Test | Knie schonen: kurze Läufe mit Gehpausen, Rad Zone 2 |
| 2026-10-05 | Aufbau | – | 150 min / 3× | 50 min / 2× | 200 | – | Knie schonen: kurze Läufe mit Gehpausen, Rad Zone 2 |
| 2026-10-12 | Aufbau | – | 165 min / 3× | 55 min / 2× | 220 | – | Knie schonen: kurze Läufe mit Gehpausen, Rad Zone 2 |
| 2026-10-19 | Aufbau | ja | 115 min / 3× | 35 min / 2× | 150 | Laufen: Einstiegstest locker | Knie schonen: kurze Läufe mit Gehpausen, Rad Zone 2 |
| 2026-10-26 | Aufbau | – | 180 min / 3× | 60 min / 3× | 240 | – | Rad-Grundlage ausbauen, Laufen behutsam steigern |
| 2026-11-02 | Aufbau | – | 190 min / 3× | 65 min / 3× | 255 | – | Rad-Grundlage ausbauen, Laufen behutsam steigern |
| 2026-11-09 | Aufbau | – | 200 min / 3× | 70 min / 3× | 270 | – | Rad-Grundlage ausbauen, Laufen behutsam steigern |
| 2026-11-16 | Aufbau | ja | 140 min / 3× | 45 min / 3× | 185 | Radfahren: 30-Minuten-Test | Rad-Grundlage ausbauen, Laufen behutsam steigern |
| 2026-11-23 | Aufbau | – | 200 min / 3× | 75 min / 3× | 275 | – | Grundlage, Rad trägt Ausdauer, Lauf wächst langsam |
| 2026-11-30 | Aufbau | – | 205 min / 3× | 80 min / 3× | 285 | – | Grundlage, Rad trägt Ausdauer, Lauf wächst langsam |
| 2026-12-07 | Aufbau | – | 210 min / 3× | 85 min / 3× | 295 | – | Grundlage, Rad trägt Ausdauer, Lauf wächst langsam |
| 2026-12-14 | Aufbau | ja | 145 min / 3× | 55 min / 3× | 200 | Laufen: 30-Minuten-Test | Grundlage, Rad trägt Ausdauer, Lauf wächst langsam |
| 2026-12-21 | Aufbau | – | 200 min / 3× | 90 min / 4× | 290 | – | Grundlage, längerer Lauf, erste lockere Steigerungen |
| 2026-12-28 | Aufbau | – | 195 min / 3× | 95 min / 4× | 290 | – | Grundlage, längerer Lauf, erste lockere Steigerungen |
| 2027-01-04 | Aufbau | – | 190 min / 3× | 100 min / 4× | 290 | – | Grundlage, längerer Lauf, erste lockere Steigerungen |
| 2027-01-11 | zielspezifisch | ja | 130 min / 3× | 70 min / 4× | 200 | Radfahren: 30-Minuten-Test | Grundlage, längerer Lauf, erste lockere Steigerungen |
| 2027-01-18 | zielspezifisch | – | 175 min / 3× | 110 min / 4× | 285 | – | Schwellenläufe und Halbmarathon-Tempo |
| 2027-01-25 | zielspezifisch | – | 170 min / 3× | 120 min / 4× | 290 | – | Schwellenläufe und Halbmarathon-Tempo |
| 2027-02-01 | zielspezifisch | – | 160 min / 3× | 130 min / 4× | 290 | – | Schwellenläufe und Halbmarathon-Tempo |
| 2027-02-08 | zielspezifisch | ja | 110 min / 3× | 90 min / 4× | 200 | Laufen: 30-Minuten-Test | Schwellenläufe und Halbmarathon-Tempo |
| 2027-02-15 | zielspezifisch | – | 150 min / 2× | 140 min / 4× | 290 | – | Höhepunkt: langer Lauf, Wettkampftempo-Abschnitte |
| 2027-02-22 | zielspezifisch | – | 140 min / 2× | 150 min / 4× | 290 | Radfahren: 30-Minuten-Test | Höhepunkt: langer Lauf, Wettkampftempo-Abschnitte |
| 2027-03-01 | zielspezifisch | – | 130 min / 2× | 165 min / 4× | 295 | – | Höhepunkt: langer Lauf, Wettkampftempo-Abschnitte |
| 2027-03-08 | Zuspitzen | – | 70 min / 2× | 95 min / 3× | 165 | – | Zuspitzen: weniger Umfang, kurze Tempoabschnitte |
| 2027-03-15 | Zielwoche | – | 40 min / 1× | 80 min / 3× | 120 | – | Zielwoche: frisch bleiben, Halbmarathon am Sonntag |

Korrekturen der Sicherheitsschicht:

- Woche ab 05.10.: Radfahren von 155 min auf 150 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 12.10.: Radfahren von 170 min auf 165 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 14.12.: Laufen von 60 min auf 55 min begrenzt (Entlastungswoche)
- Woche ab 21.12.: Laufen von 95 min auf 90 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 28.12.: Laufen von 100 min auf 95 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 04.01.: Laufen von 110 min auf 100 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 11.01.: Laufen von 75 min auf 70 min begrenzt (Entlastungswoche)
- Woche ab 18.01.: Laufen von 120 min auf 110 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 25.01.: Laufen von 130 min auf 120 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 01.02.: Laufen von 140 min auf 130 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 08.02.: Laufen von 95 min auf 90 min begrenzt (Entlastungswoche)
- Woche ab 15.02.: Laufen von 150 min auf 140 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- … und 3 weitere Korrekturen am Umfang

Prüfungen:

- [x] Änderungen genannt: 8
- [x] Plan geändert: 24 Wochen anders

Modell `claude-opus-5-5`, 12432 Token ein, 10038 Token aus, 102.8 s, ca. $0.250

