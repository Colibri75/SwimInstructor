# Bewertung der Planung für mehrere Sportarten (Plan v2)

Quelle: Claude (claude-opus-5-5, Effort high), mit Aufzeichnung.
Die Prüfungen sind Heuristiken, die zeigen, wo man hinschauen sollte; die harten Grenzen setzt die Sicherheitsschicht.

## Überblick

| Szenario | Stufe | Status | Korrekturen | Prüfungen erfüllt |
|---|---|---|---|---|
| 01-sprint-einsteiger | Gesamt | ok | 8 | 5/5 |
| 01-sprint-einsteiger | 7 Tage | ok | 0 | 2/3 |
| 01-sprint-einsteiger | Tag | ok | 0 | 2/2 |
| 02-olympisch-schwimmen | Gesamt | timeout | 0 | 0/0 |
| 02-olympisch-schwimmen | 7 Tage | ok | 0 | 0/2 |
| 02-olympisch-schwimmen | Tag | ok | 0 | 2/2 |
| 03-mitteldistanz | Gesamt | ok | 0 | 5/5 |
| 03-mitteldistanz | 7 Tage | ok | 0 | 2/3 |
| 03-mitteldistanz | Tag | ok | 0 | 2/2 |
| 04-nur-laufen | Gesamt | ok | 3 | 4/5 |
| 04-nur-laufen | 7 Tage | ok | 0 | 3/3 |
| 04-nur-laufen | Tag | ok | 0 | 1/1 |
| 05-nur-schwimmen | Gesamt | ok | 0 | 4/4 |
| 05-nur-schwimmen | 7 Tage | ok | 0 | 2/2 |
| 05-nur-schwimmen | Tag | ok | 0 | 1/2 |
| 06-laufen-nach-verletzung | Gesamt | sanity_blocked | 0 | 0/0 |
| 06-laufen-nach-verletzung | 7 Tage | ok | 0 | 1/2 |
| 06-laufen-nach-verletzung | Tag | ok | 0 | 2/2 |
| 07-einsteiger-ohne-profil | Gesamt | ok | 12 | 5/5 |
| 07-einsteiger-ohne-profil | 7 Tage | ok | 0 | 2/3 |
| 07-einsteiger-ohne-profil | Tag | ok | 0 | 2/2 |

Geschätzte Kosten: $2.10 (21 Aufrufe).

## 01-sprint-einsteiger

Erster Sprint-Triathlon in viereinhalb Monaten. Schwimmt und fährt ein wenig, läuft noch gar nicht. Vier Tage, vier Stunden pro Woche, unter der Woche wenig Zeit.

Heute 2026-09-30, Ziel am 2027-02-14: Schwimmen 750 m, Radfahren 20000 m, Laufen 5000 m; Schwerpunkte Schwimmen 35 %, Radfahren 35 %, Laufen 30 %; 4 Tage, 4 h pro Woche.

Wunsch für die Woche: "Unter der Woche habe ich höchstens 45 Minuten am Tag, am Samstag und Sonntag gern länger."

### Gesamtplan

Bis zur Zielwoche sind es 19 Wochen, insgesamt 20 Wochen bis zum Sprinttriathlon am 14.02.2027. Der Plan startet mit etwa 165 min pro Woche (1500 m Schwimmen, 80 min Rad, 40 min Laufen mit Gehpausen) und steigt bis zum Höhepunkt in den Wochen 16 bis 18 auf etwa 238 min (2600 m, 86 min, 74 min), aufgeteilt nach den Schwerpunkten 35/35/30 Prozent. Das Laufen steigt vom Nullpunkt aus am vorsichtigsten um 3 bis 8 Prozent pro Woche. Nach drei Belastungswochen folgt jeweils eine Entlastungswoche mit rund 30 Prozent weniger Umfang. Das Ziel ist realistisch, die 30 Minuten Dauerlauf am Wettkampftag sind aber der kritische Punkt; bis zum Schwellentest steuerst du über die gefühlte Anstrengung, weil der Maximalpuls nur geschätzt ist. Hinweis: Zur Sicherheit an 8 Stellen angepasst, die Wochen zeigen die geprüften Umfänge.

| Woche ab | Phase | Entlastung | Schwimmen | Radfahren | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 1500 m / 2× | 80 min / 2× | 40 min / 2× | 167 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Wiedereinstieg Laufen mit Gehpausen, Technik, Tests |
| 2026-10-05 | Aufbau | – | 1600 m / 2× | 85 min / 2× | 45 min / 2× | 181 | Laufen: Einstiegstest locker | Wiedereinstieg Laufen mit Gehpausen, Technik, Tests |
| 2026-10-12 | Aufbau | – | 1700 m / 2× | 90 min / 2× | 45 min / 2× | 189 | – | Wiedereinstieg Laufen mit Gehpausen, Technik, Tests |
| 2026-10-19 | Aufbau | ja | 1150 m / 2× | 60 min / 2× | 30 min / 2× | 126 | – | Wiedereinstieg Laufen mit Gehpausen, Technik, Tests |
| 2026-10-26 | Aufbau | – | 1800 m / 2× | 90 min / 2× | 50 min / 2× | 197 | – | Grundlage locker, Schwimmtechnik, Laufen ohne Gehpausen |
| 2026-11-02 | Aufbau | – | 1900 m / 2× | 95 min / 2× | 55 min / 2× | 210 | – | Grundlage locker, Schwimmtechnik, Laufen ohne Gehpausen |
| 2026-11-09 | Aufbau | – | 2000 m / 2× | 95 min / 2× | 55 min / 2× | 213 | – | Grundlage locker, Schwimmtechnik, Laufen ohne Gehpausen |
| 2026-11-16 | Aufbau | ja | 1400 m / 2× | 65 min / 2× | 35 min / 2× | 144 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Grundlage locker, Schwimmtechnik, Laufen ohne Gehpausen |
| 2026-11-23 | Aufbau | – | 2100 m / 2× | 95 min / 2× | 60 min / 3× | 221 | Laufen: 30-Minuten-Test | Grundlage festigen, erste Schwellenreize |
| 2026-11-30 | Aufbau | – | 2200 m / 2× | 95 min / 2× | 65 min / 3× | 229 | – | Grundlage festigen, erste Schwellenreize |
| 2026-12-07 | zielspezifisch | ja | 1500 m / 2× | 65 min / 2× | 45 min / 3× | 157 | – | Grundlage festigen, erste Schwellenreize |
| 2026-12-14 | zielspezifisch | – | 2250 m / 2× | 90 min / 2× | 70 min / 3× | 231 | – | Schwelle, Wettkampftempo, erste Koppeleinheiten |
| 2026-12-21 | zielspezifisch | – | 2350 m / 2× | 90 min / 2× | 70 min / 3× | 234 | – | Schwelle, Wettkampftempo, erste Koppeleinheiten |
| 2026-12-28 | zielspezifisch | – | 2450 m / 2× | 90 min / 2× | 70 min / 3× | 237 | – | Schwelle, Wettkampftempo, erste Koppeleinheiten |
| 2027-01-04 | zielspezifisch | ja | 1700 m / 2× | 60 min / 2× | 45 min / 3× | 159 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Schwelle, Wettkampftempo, erste Koppeleinheiten |
| 2027-01-11 | zielspezifisch | – | 2500 m / 2× | 85 min / 2× | 70 min / 3× | 234 | Laufen: 30-Minuten-Test | Höhepunkt: Koppeltraining und wettkampfnahe Intervalle |
| 2027-01-18 | zielspezifisch | – | 2500 m / 2× | 80 min / 2× | 70 min / 3× | 229 | – | Höhepunkt: Koppeltraining und wettkampfnahe Intervalle |
| 2027-01-25 | zielspezifisch | – | 2550 m / 2× | 80 min / 2× | 70 min / 3× | 231 | – | Höhepunkt: Koppeltraining und wettkampfnahe Intervalle |
| 2027-02-01 | Zuspitzen | – | 1500 m / 2× | 50 min / 2× | 40 min / 2× | 137 | – | Zuspitzen: weniger Umfang, kurze Temporeize |
| 2027-02-08 | Zielwoche | – | 1200 m / 2× | 40 min / 2× | 30 min / 2× | 108 | – | Frisch zum Wettkampf, kurze Aktivierung |

Korrekturen der Sicherheitsschicht:

- Woche ab 19.10.: Radfahren von 65 min auf 60 min begrenzt (Entlastungswoche)
- Woche ab 16.11.: Laufen von 40 min auf 35 min begrenzt (Entlastungswoche)
- Woche ab 07.12.: Schwimmen von 1550 m auf 1500 m begrenzt (Entlastungswoche)
- Woche ab 04.01.: Radfahren von 65 min auf 60 min begrenzt (Entlastungswoche)
- Woche ab 04.01.: Laufen von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 18.01.: Gesamtumfang von 241 min auf höchstens 240 min gekürzt (Wochenstunden des Ziels)
- Woche ab 25.01.: Gesamtumfang von 242 min auf höchstens 240 min gekürzt (Wochenstunden des Ziels)
- Woche ab 01.02.: Laufen von 45 min auf 40 min begrenzt (Zuspitzen)

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 31 % (Schwerpunkt 35 %), Radfahren 41 % (Schwerpunkt 35 %), Laufen 28 % (Schwerpunkt 30 %)
- [x] Höhepunkt vor dem Zuspitzen: höchste Woche ab 2026-12-28 (237 min), Zuspitzen ab 2027-02-01
- [x] Einstiegstests in den ersten zwei Wochen: Schwimmen, Radfahren, Laufen
- [x] Leistungstests im Plan: Schwimmen ab 2026-09-28; Radfahren ab 2026-09-28; Laufen ab 2026-10-05; Schwimmen ab 2026-11-16; Radfahren ab 2026-11-16; Laufen ab 2026-11-23; Schwimmen ab 2027-01-04; Radfahren ab 2027-01-04; Laufen ab 2027-01-11
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9778 Token ein, 8122 Token aus, 78.9 s, ca. $0.202

### Die nächsten sieben Tage

Unter der Woche bleibt jeder Tag wie gewünscht unter 45 Minuten, die längeren Einheiten liegen am Wochenende. Die beiden vorgesehenen Tests sind harte Tage mit einem lockeren Tag dazwischen: der CSS-Test mit 1000 m am Freitag nach einem Ruhetag und der 30-Minuten-Test auf dem Rad (60 min) am Sonntag. Laufen startest du nach der Pause locker mit 20 und 15 Minuten, mit Gehpausen und nach Gefühl, weil noch keine Zonen bekannt sind. Mit insgesamt etwa 175 Minuten und Montag und Dienstag als Ruhetagen bleibt die Woche nach der Pause bewusst moderat, und dein Ziel am 14.02. ist auf diesem Weg gut erreichbar.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Laufen 20 min locker (Ausdauer) | 20 | Wiedereinstieg Laufen mit Gehpausen |
| Donnerstag 2026-10-01 | Ruhetag | 0 | Ruhetag |
| Freitag 2026-10-02 | Schwimmen 1000 m hart (CSS-Test 400/200 m) | 43 | CSS-Test Schwimmen |
| Samstag 2026-10-03 | Radfahren 40 min locker (Ausdauer) + Laufen 15 min locker (Ausdauer) | 55 | Lockeres Koppeltraining |
| Sonntag 2026-10-04 | Radfahren 58 min hart (30-Minuten-Test) | 58 | 30-Minuten-Test Rad |
| Montag 2026-10-05 | Ruhetag | 0 | Ruhetag |
| Dienstag 2026-10-06 | Ruhetag | 0 | Ruhetag |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [ ] Schwerpunkte verteilt: Schwimmen 24 % (Schwerpunkt 35 %), Radfahren 56 % (Schwerpunkt 35 %), Laufen 20 % (Schwerpunkt 30 %)
- [x] Tests aus dem Gesamtplan eingeplant: Schwimmen am 2026-10-02, Radfahren am 2026-10-04
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9254 Token ein, 3806 Token aus, 40.3 s, ca. $0.113

### Heute

Du bist in den letzten 4 Wochen keinen Meter gelaufen (längste Laufeinheit 0 min), deshalb steigst du heute mit 20 min im Wechsel aus Laufen und Gehen ein, wie im Wochenplan vorgesehen. Deine Erholung ist gut und die Belastung mit einem Verhältnis von 1,06 stabil, nach Rad am Samstag und 1000 m Schwimmen am Montag passt ein lockerer Lauftag. Mit 137 Tagen bis zum Sprint-Triathlon ist genug Zeit, die 5 km Laufen behutsam aufzubauen. Das Ziel ist bei regelmäßigem, geduldigem Aufbau gut erreichbar.

**Laufen: Ausdauer**, locker, 20 min, ca. 20 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Gehen zum Aufwärmen | 3 min | perceived_effort 2 | 0 s | Zügig gehen | Geh zügig und locker, lass die Arme mitschwingen und atme ruhig. |
| Hauptteil Laufen mit Gehpausen | 6 × 1.5 min | perceived_effort 3 | 60 s | Locker laufen, dann gehen | Lauf 90 Sekunden so locker, dass du dich problemlos unterhalten könntest, mit kurzen, leichten Schritten. Danach jeweils 60 Sekunden gehen, bis der Atem wieder ganz ruhig ist. |
| Gehen zum Ausklang | 2 min | perceived_effort 2 | 0 s | Ruhig ausgehen | Geh ruhig aus und lass Puls und Atmung herunterkommen. |

Die Sicherheitsschicht hat nichts geändert.

> Lieber zu langsam als zu schnell: Du solltest beim Laufen jederzeit sprechen können.
> Muskelkater in Waden oder Schienbeinen ist anfangs normal; stechende oder anhaltende Schmerzen bitte ernst nehmen und bei Bedarf ärztlich abklären lassen.
> Morgen ist locker oder Ruhe angesagt, damit sich Sehnen und Gelenke an das Laufen gewöhnen.

Prüfungen:

- [x] Vorgabe des Wochenplans: geplant Laufen, Vorgabe Laufen
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 10038 Token ein, 1883 Token aus, 20.4 s, ca. $0.078

## 02-olympisch-schwimmen

Olympische Distanz im Juli, Schwerpunkt Schwimmen (50 %). Erfahrener Schwimmer mit getesteter CSS, fährt etwas Rad, läuft kaum. Danach Feedback: mehr Laufen.

Heute 2026-09-30, Ziel am 2027-07-04: Schwimmen 1500 m, Radfahren 40000 m, Laufen 10000 m; Schwerpunkte Schwimmen 50 %, Radfahren 30 %, Laufen 20 %; 5 Tage, 7.5 h pro Woche.

### Gesamtplan

**Kein Gesamtplan:** timeout

Prüfungen:

Keine automatischen Prüfungen.

Aufruf fehlgeschlagen nach 85.0 s: Request timed out.

### Die nächsten sieben Tage

In der Aufbauphase ist die Woche fast nur locker, mit dem Rad-Schwellentest am frischen Freitag als erstem harten Tag und CSS-Serien am Dienstag als zweitem. Schwimmen bekommt 4300 m (Grenze 4350 m) und Rad 118 von 120 min. Deshalb erreicht die Woche nicht die 7,5 h, und die Verteilung weicht von 50/30/20 ab. Laufen steigt nur von 20 auf 22 min, weil die längste Einheit erst 25 min beträgt; den 30-min-Lauftest verschieben wir deshalb, bis die Grundlage länger ist.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Schwimmen 800 m locker (Technik) + Laufen 20 min locker (Ausdauer) | 36 | Schwimmtechnik und lockerer Lauf |
| Donnerstag 2026-10-01 | Ruhetag | 0 | Ruhetag |
| Freitag 2026-10-02 | Radfahren 58 min hart (30-Minuten-Test) | 58 | Rad-Schwellentest 30 min |
| Samstag 2026-10-03 | Schwimmen 2000 m locker (Ausdauer) | 40 | Lockere Schwimmausdauer |
| Sonntag 2026-10-04 | Radfahren 60 min locker (Ausdauer) | 60 | Lockere Radgrundlage |
| Montag 2026-10-05 | Ruhetag | 0 | Ruhetag |
| Dienstag 2026-10-06 | Schwimmen 1500 m hart (Schwelle) | 30 | CSS-Serien Schwimmen |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [ ] Schwerpunkte verteilt: Schwimmen 38 % (Schwerpunkt 50 %), Radfahren 53 % (Schwerpunkt 30 %), Laufen 9 % (Schwerpunkt 20 %)
- [ ] Begründung nennt das Ziel: kein Wort wie "Ziel" oder "Wettkampf" in der Begründung

Modell `claude-opus-5-5`, 9548 Token ein, 3074 Token aus, 33.1 s, ca. $0.100

### Heute

Die Erholung ist gut und das Verhältnis akut zu chronisch liegt bei 1,08, nach dem harten Schwimmtag am 27.09. bleibt heute alles locker. Beim Schwimmen arbeiten wir in der Aufbauphase an der Technik, die Tempi orientieren sich an deiner getesteten CSS von 1:45/100 m (Z2 ab etwa 2:00). Der Lauf bleibt mit 20 min unter deiner längsten Einheit von 25 min, denn bis zum 10-km-Lauf (etwa 60 min) wächst der Laufumfang behutsam um rund 10 % pro Woche. Mit 39 Wochen bis zur Zielwoche ist das Ziel gut erreichbar, wenn die Grundlage stetig wächst.

**Schwimmen: Technik**, locker, 800 m, ca. 20 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einschwimmen | 200 m | pace_per_100m 128 | 30 s | Locker kraulen | Locker und gleichmäßig kraulen, ruhig ausatmen und den Körper lang machen. |
| Technik Seitlage | 2 × 50 m | perceived_effort 3 | 20 s | Seitlage, lang machen | Seitlage-Beinschlag: Auf der Seite liegen, unterer Arm nach vorn gestreckt, oberer Arm am Körper, ruhig kraulbeinen; nach 25 m die Seite wechseln. Das Gesicht schaut zum Atmen kurz seitlich heraus, sonst nach unten. |
| Technik Abschlag | 4 × 50 m | perceived_effort 3 | 20 s | Abschlag, lang ziehen | Abschlagschwimmen: Ein Arm wartet vorn gestreckt, bis die andere Hand ihn nach dem Zug berührt, erst dann zieht er. So spürst du einen langen, ruhigen Armzug mit früh gefasstem Wasser. |
| Hauptteil | 2 × 100 m | pace_per_100m 122 | 30 s | Zielpace halten | Normal kraulen und das Gefühl aus den Übungen mitnehmen: lange Züge, flache Wasserlage, gleichmäßiges Tempo um 2:02/100 m. |
| Ausschwimmen | 100 m | perceived_effort 2 | 0 s | Ganz locker | Ganz locker ausschwimmen, gern im Wechsel Kraul und Rücken. |

**Laufen: Ausdauer**, locker, 20 min, ca. 20 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einlaufen | 5 min | perceived_effort 3 | 0 s | Locker einlaufen | Sehr locker loslaufen, kurze Schritte und entspannte Schultern. |
| Hauptteil | 12 min | perceived_effort 4 | 0 s | Gespräch möglich | Gleichmäßig locker laufen, du solltest dich jederzeit in ganzen Sätzen unterhalten können. |
| Auslaufen | 3 min | perceived_effort 2 | 0 s | Locker austraben | Tempo weiter rausnehmen und locker austraben. |

Die Sicherheitsschicht hat nichts geändert.

> Schwimmen und Laufen gern mit einigen Stunden Abstand, die Reihenfolge ist frei.
> Wird der Lauf schwer, lieber langsamer oder kurz gehen, statt durchzudrücken.
> Bei Schmerzen in Schulter oder Beinen die Einheit abbrechen und bei anhaltenden Beschwerden ärztlichen Rat einholen.

Prüfungen:

- [x] Vorgabe des Wochenplans: geplant Laufen + Schwimmen, Vorgabe Laufen + Schwimmen
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 11012 Token ein, 2518 Token aus, 27.0 s, ca. $0.094

## 03-mitteldistanz

Mitteldistanz (70.3) im Mai, Schwerpunkt Rad. Trainiert regelmäßig in allen drei Sportarten, CSS und FTP getestet. Tests alle 8 Wochen, beim Schwimmen lieber der 1000-m-Test.

Heute 2026-09-30, Ziel am 2027-05-16: Schwimmen 1900 m, Radfahren 90000 m, Laufen 21097 m; Schwerpunkte Schwimmen 25 %, Radfahren 45 %, Laufen 30 %; 6 Tage, 10 h pro Woche.

### Gesamtplan

Bis zum Wettkampf am 16.05.2027 sind es 33 Wochen; das Ziel (1900 m in 38 min bei CSS 1:38, 90 km in 3 h bei 245 W FTP, 21,1 km in 110 min bei 4:28 Schwellentempo) ist realistisch. Weil die Wochengrenze von 600 min schon jetzt fast ausgeschöpft ist (Woche 1: 7000 m Schwimmen, 300 min Rad, 150 min Laufen, etwa 590 min), wächst nicht der Gesamtumfang, sondern die Verteilung verschiebt sich Richtung Schwerpunkte: Laufen steigt um etwa 5 % je Woche auf 180–185 min, das Rad bleibt bei 265–295 min. Am Höhepunkt in den Wochen 28 bis 30 stehen etwa 6000 m Schwimmen, 295 min Rad und 180 min Laufen (rund 595 min) mit langer Ausfahrt bis 180 min, Koppelläufen und Schwellenarbeit. Nach je zwei bis drei Belastungswochen folgt eine Entlastungswoche mit 30 % weniger Umfang. Danach folgen 2 Wochen Zuspitzen auf 75 % und 55 % sowie eine kurze Zielwoche mit höchstens 50 %.

| Woche ab | Phase | Entlastung | Schwimmen | Radfahren | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 7000 m / 3× | 300 min / 3× | 150 min / 3× | 590 | Laufen: 30-Minuten-Test, Schwimmen: 1000-m-Test | Grundlage, Technik und Leistungstests |
| 2026-10-05 | Aufbau | – | 7000 m / 3× | 295 min / 3× | 160 min / 3× | 595 | – | Grundlage, Technik und Leistungstests |
| 2026-10-12 | Aufbau | – | 7000 m / 3× | 290 min / 3× | 165 min / 3× | 595 | – | Grundlage, Technik und Leistungstests |
| 2026-10-19 | Aufbau | ja | 4900 m / 3× | 200 min / 3× | 115 min / 3× | 413 | Radfahren: 30-Minuten-Test | Grundlage, Technik und Leistungstests |
| 2026-10-26 | Aufbau | – | 7000 m / 3× | 280 min / 3× | 165 min / 3× | 585 | – | Laufumfang behutsam steigern, Rad locker in Zone 2 |
| 2026-11-02 | Aufbau | – | 7000 m / 3× | 280 min / 3× | 175 min / 3× | 595 | – | Laufumfang behutsam steigern, Rad locker in Zone 2 |
| 2026-11-09 | Aufbau | – | 7000 m / 3× | 275 min / 3× | 180 min / 3× | 595 | – | Laufumfang behutsam steigern, Rad locker in Zone 2 |
| 2026-11-16 | Aufbau | ja | 4900 m / 3× | 190 min / 3× | 125 min / 3× | 413 | – | Laufumfang behutsam steigern, Rad locker in Zone 2 |
| 2026-11-23 | Aufbau | – | 6800 m / 3× | 275 min / 3× | 175 min / 3× | 586 | Laufen: 30-Minuten-Test, Schwimmen: 1000-m-Test | Grundlage festigen, Tests, erste Tempoabschnitte |
| 2026-11-30 | Aufbau | – | 7000 m / 3× | 270 min / 3× | 180 min / 3× | 590 | – | Grundlage festigen, Tests, erste Tempoabschnitte |
| 2026-12-07 | Aufbau | – | 7200 m / 3× | 265 min / 3× | 185 min / 3× | 594 | – | Grundlage festigen, Tests, erste Tempoabschnitte |
| 2026-12-14 | Aufbau | ja | 5000 m / 3× | 185 min / 3× | 125 min / 3× | 410 | Radfahren: 30-Minuten-Test | Grundlage festigen, Tests, erste Tempoabschnitte |
| 2026-12-21 | Aufbau | – | 7000 m / 3× | 270 min / 3× | 175 min / 3× | 585 | – | Winter-Grundlage, lange lockere Einheiten |
| 2026-12-28 | Aufbau | – | 7000 m / 3× | 275 min / 3× | 180 min / 3× | 595 | – | Winter-Grundlage, lange lockere Einheiten |
| 2027-01-04 | Aufbau | – | 7000 m / 3× | 275 min / 3× | 180 min / 3× | 595 | – | Winter-Grundlage, lange lockere Einheiten |
| 2027-01-11 | Aufbau | ja | 4900 m / 3× | 190 min / 3× | 125 min / 3× | 413 | – | Winter-Grundlage, lange lockere Einheiten |
| 2027-01-18 | Aufbau | – | 6500 m / 3× | 280 min / 3× | 175 min / 3× | 585 | Laufen: 30-Minuten-Test, Schwimmen: 1000-m-Test | Tests, längere Ausfahrten, Tempo- und Schwellenteile |
| 2027-01-25 | Aufbau | – | 6500 m / 3× | 285 min / 3× | 175 min / 3× | 590 | – | Tests, längere Ausfahrten, Tempo- und Schwellenteile |
| 2027-02-01 | Aufbau | – | 6500 m / 3× | 290 min / 3× | 175 min / 3× | 595 | – | Tests, längere Ausfahrten, Tempo- und Schwellenteile |
| 2027-02-08 | Aufbau | ja | 4550 m / 3× | 200 min / 3× | 120 min / 3× | 411 | Radfahren: 30-Minuten-Test | Tests, längere Ausfahrten, Tempo- und Schwellenteile |
| 2027-02-15 | Aufbau | – | 6500 m / 3× | 280 min / 3× | 175 min / 3× | 585 | – | Grundlage abschließen, Übergang zu spezifisch |
| 2027-02-22 | Aufbau | – | 6500 m / 3× | 290 min / 3× | 175 min / 3× | 595 | – | Grundlage abschließen, Übergang zu spezifisch |
| 2027-03-01 | zielspezifisch | ja | 4550 m / 3× | 200 min / 3× | 120 min / 3× | 411 | – | Grundlage abschließen, Übergang zu spezifisch |
| 2027-03-08 | zielspezifisch | – | 6500 m / 3× | 290 min / 3× | 175 min / 3× | 595 | – | Schwelle, Wettkampftempo, Koppeltraining, Tests |
| 2027-03-15 | zielspezifisch | – | 6250 m / 3× | 295 min / 3× | 180 min / 3× | 600 | – | Schwelle, Wettkampftempo, Koppeltraining, Tests |
| 2027-03-22 | zielspezifisch | – | 6000 m / 3× | 295 min / 3× | 180 min / 3× | 595 | – | Schwelle, Wettkampftempo, Koppeltraining, Tests |
| 2027-03-29 | zielspezifisch | ja | 4200 m / 3× | 205 min / 3× | 125 min / 3× | 414 | Laufen: 30-Minuten-Test, Schwimmen: 1000-m-Test | Schwelle, Wettkampftempo, Koppeltraining, Tests |
| 2027-04-05 | zielspezifisch | – | 6000 m / 3× | 290 min / 3× | 180 min / 3× | 590 | Radfahren: 30-Minuten-Test | Höhepunkt: lange Ausfahrt, Koppelläufe, Renntempo |
| 2027-04-12 | zielspezifisch | – | 6000 m / 3× | 295 min / 3× | 180 min / 3× | 595 | – | Höhepunkt: lange Ausfahrt, Koppelläufe, Renntempo |
| 2027-04-19 | zielspezifisch | – | 6000 m / 3× | 295 min / 3× | 180 min / 3× | 595 | – | Höhepunkt: lange Ausfahrt, Koppelläufe, Renntempo |
| 2027-04-26 | Zuspitzen | – | 4500 m / 3× | 220 min / 3× | 135 min / 3× | 445 | – | Zuspitzen: weniger Umfang, Intensität halten |
| 2027-05-03 | Zuspitzen | – | 3300 m / 3× | 160 min / 3× | 95 min / 3× | 321 | – | Zuspitzen: weniger Umfang, Intensität halten |
| 2027-05-10 | Zielwoche | – | 2500 m / 2× | 100 min / 2× | 60 min / 2× | 210 | – | Zielwoche: kurz, frisch, kurze Tempoimpulse |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 23 % (Schwerpunkt 25 %), Radfahren 48 % (Schwerpunkt 45 %), Laufen 30 % (Schwerpunkt 30 %)
- [x] Höhepunkt vor dem Zuspitzen: höchste Woche ab 2027-03-15 (600 min), Zuspitzen ab 2027-04-26
- [x] Einstiegstests in den ersten zwei Wochen: Laufen
- [x] Leistungstests im Plan: Laufen ab 2026-09-28; Schwimmen ab 2026-09-28; Radfahren ab 2026-10-19; Laufen ab 2026-11-23; Schwimmen ab 2026-11-23; Radfahren ab 2026-12-14; Laufen ab 2027-01-18; Schwimmen ab 2027-01-18; Radfahren ab 2027-02-08; Laufen ab 2027-03-29; Schwimmen ab 2027-03-29; Radfahren ab 2027-04-05
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 10782 Token ein, 7809 Token aus, 75.1 s, ca. $0.199

### Die nächsten sieben Tage

Die Erholung ist gut und die Belastung mit einem Verhältnis von 1,07 stabil, daher folgen nach dem harten Radtag vom Montag zwei Leistungstests: Am Donnerstag der 1000-m-Test im Wasser, am Samstag nach dem Ruhetag der 30-Minuten-Lauftest. Beide liegen an frischen Tagen und nie hintereinander. Sonst bleibt die Woche locker: Die lange Radausfahrt mit 150 min hält dein bisheriges Maximum, der lange Lauf bleibt mit 70 min unter deinen 75 min. Insgesamt sind rund 580 min geplant, verteilt nach deinen Schwerpunkten Rad 45 %, Lauf 30 % und Schwimmen 25 %.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Radfahren 60 min locker (Ausdauer) + Schwimmen 1500 m locker (Technik) | 90 | Lockere Grundlage Rad und Schwimmtechnik |
| Donnerstag 2026-10-01 | Schwimmen 1500 m hart (1000-m-Test) | 32 | Leistungstest Schwimmen |
| Freitag 2026-10-02 | Ruhetag | 0 | Ruhetag |
| Samstag 2026-10-03 | Laufen 47 min hart (30-Minuten-Test) + Schwimmen 2000 m locker (Regeneration) | 87 | Leistungstest Laufen, lockeres Schwimmen |
| Sonntag 2026-10-04 | Radfahren 150 min locker (Ausdauer) | 150 | Lange Radausfahrt |
| Montag 2026-10-05 | Laufen 70 min locker (Ausdauer) + Schwimmen 2500 m locker (Ausdauer) | 120 | Langer Lauf und Schwimmausdauer |
| Dienstag 2026-10-06 | Radfahren 75 min locker (Ausdauer) + Laufen 30 min locker (Ausdauer) | 105 | Lockeres Koppeltraining |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 26 % (Schwerpunkt 25 %), Radfahren 49 % (Schwerpunkt 45 %), Laufen 25 % (Schwerpunkt 30 %)
- [x] Tests aus dem Gesamtplan eingeplant: Schwimmen am 2026-10-01, Laufen am 2026-10-03
- [ ] Begründung nennt das Ziel: kein Wort wie "Ziel" oder "Wettkampf" in der Begründung

Modell `claude-opus-5-5`, 9807 Token ein, 3224 Token aus, 32.3 s, ca. $0.104

### Heute

Deine Erholung ist gut und die Last liegt mit einem Verhältnis von 1,07 (555 zu 518) im stabilen Bereich. Nach dem harten Rad am 28.09. bleibt heute alles locker, wie es der Wochenplan vorsieht. Die 60 min Rad halten den Radumfang im Rahmen deiner 300 min der letzten 7 Tage. Die 1500 m Technikschwimmen passen zur Aufbauphase, 32 Wochen vor der Mitteldistanz ist dein Ziel mit dieser Grundlage realistisch.

**Radfahren: Ausdauer**, locker, 60 min, ca. 60 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einfahren | 10 min | power 140 | 0 s | Locker einrollen | Locker einrollen und die Leistung langsam auf etwa 140 W steigern. |
| Hauptteil | 35 min | power 165 | 0 s | 165 W gleichmäßig | Gleichmäßig um 165 W fahren, ein Gespräch muss jederzeit möglich sein. Regelmäßig trinken. |
| Trittfrequenz | 5 × 1 min | cadence 100 | 60 s | Rund treten 100 | Eine Minute bei leichtem Gang mit 100 Umdrehungen pro Minute rund treten, ohne auf dem Sattel zu hüpfen. Danach eine Minute locker in normaler Trittfrequenz weiterfahren. |
| Ausfahren | 5 min | power 130 | 0 s | Locker ausrollen | Sehr locker ausrollen und die Beine lockern. |

**Schwimmen: Technik**, locker, 1500 m, ca. 34 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einschwimmen | 300 m | perceived_effort 3 | 30 s | Locker kraulen | Locker kraulen, ruhig ausatmen und ins Wasser finden. |
| Technik Abschlag | 4 × 50 m | perceived_effort 3 | 20 s | Arm vorne warten | Abschlagschwimmen: Ein Arm bleibt vorne gestreckt liegen, bis der andere Arm nach dem Zug wieder vorne ankommt. Das schult eine lange Gleitphase. |
| Technik Faust | 2 × 50 m | perceived_effort 3 | 20 s | Unterarm spüren | Faustschwimmen: Kraulen mit geschlossenen Fäusten, damit du lernst, das Wasser mit dem ganzen Unterarm zu greifen. Die letzten 10 m Hände wieder öffnen. |
| Hauptteil | 4 × 150 m | pace_per_100m 108 | 20 s | 1:48 gleichmäßig | Gleichmäßig um 1:48 pro 100 m kraulen und die lange Gleitphase aus den Übungen mitnehmen. |
| Pull | 200 m | perceived_effort 4 | 20 s | Lange Züge | Mit dem Pull Buoy zwischen den Oberschenkeln nur mit den Armen kraulen und auf einen langen, sauberen Zug achten. |
| Ausschwimmen | 100 m | perceived_effort 2 | 0 s | Locker ausschwimmen | Ganz locker ausschwimmen, gern in Rückenlage oder gemischt. |

Die Sicherheitsschicht hat nichts geändert.

> Beide Einheiten bleiben locker: Lieber unter 165 W bleiben als darüber.
> Zwischen Rad und Schwimmen etwas essen und trinken.
> Beim Schwimmen Qualität vor Tempo: Technik sauber halten, auch wenn die Pace etwas langsamer wird.

Prüfungen:

- [x] Vorgabe des Wochenplans: geplant Radfahren + Schwimmen, Vorgabe Radfahren + Schwimmen
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 10954 Token ein, 2769 Token aus, 26.0 s, ca. $0.099

## 04-nur-laufen

Nur Laufen: 10 km in 50 Minuten Mitte Dezember. Läuft dreimal pro Woche, schwimmt und fährt nicht.

Heute 2026-09-30, Ziel am 2026-12-13: Laufen 10000 m; Schwerpunkte Laufen 100 %; 4 Tage, 4 h pro Woche.

### Gesamtplan

Bis zum 10-km-Lauf am 13.12. bleiben 11 Wochen. Der Laufumfang steigt von jetzt 120 min (Schnitt 115 min) um weniger als 10 % pro Woche auf den Höhepunkt von 190 min in der Woche ab 23.11., mit Entlastungswochen bei 100 und 115 min. Die längste Einheit steigt dabei von 55 min nur schrittweise, rund 80 % bleiben locker, und es gibt höchstens eine harte Laufeinheit pro Woche. Die beiden 30-Minuten-Tests (Woche 1 und in der Entlastungswoche ab 09.11.) ersetzen je eine harte Einheit und legen die Zonen fest. 50 min entsprechen 5:00 pro km und damit dem geschätzten Schwellentempo; das ist ehrgeizig, aber machbar, wenn der erste Test diesen Wert bestätigt. Hinweis: Zur Sicherheit an 3 Stellen angepasst, die Wochen zeigen die geprüften Umfänge.

| Woche ab | Phase | Entlastung | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 125 min / 4× | 125 | Laufen: 30-Minuten-Test | Grundlage, Schwellentest, erste Tempoläufe |
| 2026-10-05 | zielspezifisch | – | 135 min / 4× | 135 | – | Grundlage, Schwellentest, erste Tempoläufe |
| 2026-10-12 | zielspezifisch | – | 145 min / 4× | 145 | – | Grundlage, Schwellentest, erste Tempoläufe |
| 2026-10-19 | zielspezifisch | ja | 100 min / 4× | 100 | – | Grundlage, Schwellentest, erste Tempoläufe |
| 2026-10-26 | zielspezifisch | – | 155 min / 4× | 155 | – | Schwellenintervalle, langer Lauf, Test in Entlastung |
| 2026-11-02 | zielspezifisch | – | 170 min / 4× | 170 | – | Schwellenintervalle, langer Lauf, Test in Entlastung |
| 2026-11-09 | zielspezifisch | ja | 115 min / 4× | 115 | Laufen: 30-Minuten-Test | Schwellenintervalle, langer Lauf, Test in Entlastung |
| 2026-11-16 | zielspezifisch | – | 180 min / 4× | 180 | – | Wettkampftempo 5:00/km, Höhepunkt des Umfangs |
| 2026-11-23 | zielspezifisch | – | 190 min / 4× | 190 | – | Wettkampftempo 5:00/km, Höhepunkt des Umfangs |
| 2026-11-30 | Zuspitzen | – | 110 min / 4× | 110 | – | Zuspitzen: weniger Umfang, kurze Tempoabschnitte |
| 2026-12-07 | Zielwoche | – | 70 min / 3× | 70 | – | Zielwoche: locker, kurze Steigerungen, frisch |

Korrekturen der Sicherheitsschicht:

- Woche ab 05.10.: Laufen von 140 min auf 135 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 12.10.: Laufen von 150 min auf 145 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)
- Woche ab 26.10.: Laufen von 160 min auf 155 min begrenzt (höchstens 10 % mehr als die letzte Woche ohne Entlastung)

Prüfungen:

- [x] Schwerpunkte verteilt: Laufen 100 % (Schwerpunkt 100 %)
- [x] Höhepunkt vor dem Zuspitzen: höchste Woche ab 2026-11-23 (190 min), Zuspitzen ab 2026-11-30
- [x] Einstiegstests in den ersten zwei Wochen: Laufen
- [x] Leistungstests im Plan: Laufen ab 2026-09-28; Laufen ab 2026-11-09
- [ ] Begründung nennt das Ziel: kein Wort wie "Ziel" oder "Wettkampf" in der Begründung

Modell `claude-opus-5-5`, 8787 Token ein, 2354 Token aus, 25.1 s, ca. $0.082

### Die nächsten sieben Tage

Mit guter Erholung, einer Belastungsquote von 1,04 und 120 min Laufen in den letzten 7 Tagen steht der 30-Minuten-Schwellentest (47 min) am Donnerstag nach einem Ruhetag auf frischen Beinen. Danach folgt nur lockere Grundlage: 38 min am Samstag bringen die Woche auf etwa 125 min, der Dienstag eröffnet mit 50 min locker die neue Woche, insgesamt 135 von erlaubten 145 min. Das Ziel 10 km in 50 min verlangt etwa 5:00 pro km, also genau dein geschätztes Schwellentempo. Es ist ehrgeizig, und erst der Test zeigt, ob es realistisch ist.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Ruhetag | 0 | Ruhetag |
| Donnerstag 2026-10-01 | Laufen 47 min hart (30-Minuten-Test) | 47 | Schwellentest Laufen |
| Freitag 2026-10-02 | Ruhetag | 0 | Ruhetag |
| Samstag 2026-10-03 | Laufen 40 min locker (Ausdauer) | 40 | Lockere Grundlage |
| Sonntag 2026-10-04 | Ruhetag | 0 | Ruhetag |
| Montag 2026-10-05 | Ruhetag | 0 | Ruhetag |
| Dienstag 2026-10-06 | Laufen 50 min locker (Ausdauer) | 50 | Grundlagenlauf |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [x] Schwerpunkte verteilt: Laufen 100 % (Schwerpunkt 100 %)
- [x] Tests aus dem Gesamtplan eingeplant: Laufen am 2026-10-01
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 8107 Token ein, 2843 Token aus, 29.5 s, ca. $0.089

### Heute

Der Wochenplan sieht heute einen Ruhetag vor, und den halten wir ein: Mit 3 Laufeinheiten und 120 Minuten in den letzten 7 Tagen liegst du bereits knapp über deinem Wochenschnitt von 115 Minuten (Verhältnis 1,04). Gestern bist du 40 Minuten gelaufen, am Sonntag hart, deshalb tut ein freier Tag deiner Grundlage gut. In der Aufbauphase mit noch 74 Tagen bis zu den 10 km in 50 Minuten zählt beständiges, verletzungsfreies Training mehr als zusätzliche Minuten.

Ruhetag.

Die Sicherheitsschicht hat nichts geändert.

> Heute komplett frei. Lockeres Gehen oder leichtes Dehnen ist in Ordnung, aber kein Training.
> Achte auf ausreichend Schlaf; deine 7,5 Stunden im Schnitt sind eine gute Basis.
> Dein Schwellentempo von 5:00 pro km ist nur geschätzt. Ein Test in den kommenden Wochen würde die Steuerung genauer machen.

Prüfungen:

- [x] Vorgabe des Wochenplans: geplant Ruhetag, Vorgabe Ruhetag

Modell `claude-opus-5-5`, 9298 Token ein, 406 Token aus, 6.4 s, ca. $0.045

## 05-nur-schwimmen

Nur Schwimmen wie bisher: 1500 m in 30 Minuten im März. CSS getestet. Prüft, dass Plan v2 für reine Schwimmer so plant wie v1.

Heute 2026-09-30, Ziel am 2027-03-14: Schwimmen 1500 m; Schwerpunkte Schwimmen 100 %; 3 Tage, 3 h pro Woche.

Wunsch für heute: "Heute gern etwas mit Technik."

### Gesamtplan

Bis zur Zielwoche bleiben 23 Wochen. Mit einer getesteten CSS-Pace von 1:52 pro 100 m sind 1500 m in 30 min (2:00 pro 100 m) gut erreichbar. Der Umfang steigt von zuletzt 5400 m auf 5600 m in der ersten Woche und bis zum Höhepunkt von 8200 m pro Woche, verteilt auf 3 Einheiten. So bleibst du mit Pausen sicher unter 180 min pro Woche. Nach jeweils 3 Belastungswochen folgt eine Entlastungswoche mit etwa 30 % weniger Umfang; ab Januar kommen CSS-Serien und wettkampfnahe 1500-m-Abschnitte dazu. Danach senkst du beim Zuspitzen auf 4800 m und in der Zielwoche auf 3600 m inklusive Wettkampf, damit du frisch an den Start gehst.

| Woche ab | Phase | Entlastung | Schwimmen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 5600 m / 3× | 112 | – | Grundlage, Kraultechnik, gleichmäßiges Tempo |
| 2026-10-05 | Aufbau | – | 6100 m / 3× | 122 | – | Grundlage, Kraultechnik, gleichmäßiges Tempo |
| 2026-10-12 | Aufbau | – | 6600 m / 3× | 132 | – | Grundlage, Kraultechnik, gleichmäßiges Tempo |
| 2026-10-19 | Aufbau | ja | 4600 m / 3× | 92 | Schwimmen: CSS-Test 400/200 m | Grundlage, Kraultechnik, gleichmäßiges Tempo |
| 2026-10-26 | Aufbau | – | 6900 m / 3× | 138 | – | Ausdauer verlängern, lange lockere Serien |
| 2026-11-02 | Aufbau | – | 7200 m / 3× | 144 | – | Ausdauer verlängern, lange lockere Serien |
| 2026-11-09 | Aufbau | – | 7500 m / 3× | 150 | – | Ausdauer verlängern, lange lockere Serien |
| 2026-11-16 | Aufbau | ja | 5200 m / 3× | 104 | – | Ausdauer verlängern, lange lockere Serien |
| 2026-11-23 | Aufbau | – | 7600 m / 3× | 152 | – | Grundlage festigen, erste kurze CSS-Serien |
| 2026-11-30 | Aufbau | – | 7800 m / 3× | 156 | – | Grundlage festigen, erste kurze CSS-Serien |
| 2026-12-07 | Aufbau | – | 8000 m / 3× | 160 | – | Grundlage festigen, erste kurze CSS-Serien |
| 2026-12-14 | Aufbau | ja | 5500 m / 3× | 110 | Schwimmen: CSS-Test 400/200 m | Grundlage festigen, erste kurze CSS-Serien |
| 2026-12-21 | Aufbau | – | 7800 m / 3× | 156 | – | Übergang: CSS-Serien und Tempohärte |
| 2026-12-28 | Aufbau | – | 8000 m / 3× | 160 | – | Übergang: CSS-Serien und Tempohärte |
| 2027-01-04 | zielspezifisch | – | 8200 m / 3× | 164 | – | Übergang: CSS-Serien und Tempohärte |
| 2027-01-11 | zielspezifisch | ja | 5700 m / 3× | 114 | – | Übergang: CSS-Serien und Tempohärte |
| 2027-01-18 | zielspezifisch | – | 7800 m / 3× | 156 | – | Wettkampftempo 2:00/100 m über längere Serien |
| 2027-01-25 | zielspezifisch | – | 8000 m / 3× | 160 | – | Wettkampftempo 2:00/100 m über längere Serien |
| 2027-02-01 | zielspezifisch | – | 8200 m / 3× | 164 | – | Wettkampftempo 2:00/100 m über längere Serien |
| 2027-02-08 | zielspezifisch | ja | 5700 m / 3× | 114 | Schwimmen: CSS-Test 400/200 m | Wettkampftempo 2:00/100 m über längere Serien |
| 2027-02-15 | zielspezifisch | – | 8000 m / 3× | 160 | – | Höhepunkt: 1500 m wettkampfnah schwimmen |
| 2027-02-22 | zielspezifisch | – | 8200 m / 3× | 164 | – | Höhepunkt: 1500 m wettkampfnah schwimmen |
| 2027-03-01 | Zuspitzen | – | 4800 m / 3× | 96 | – | Zuspitzen: weniger Umfang, kurze Tempoabschnitte |
| 2027-03-08 | Zielwoche | – | 3600 m / 3× | 72 | – | Zielwoche: kurz, frisch, Wettkampf 1500 m |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 100 % (Schwerpunkt 100 %)
- [x] Höhepunkt vor dem Zuspitzen: höchste Woche ab 2027-01-04 (164 min), Zuspitzen ab 2027-03-01
- [x] Leistungstests im Plan: Schwimmen ab 2026-10-19; Schwimmen ab 2026-12-14; Schwimmen ab 2027-02-08
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9009 Token ein, 2742 Token aus, 26.4 s, ca. $0.091

### Die nächsten sieben Tage

Nach der Einheit gestern (1800 m) ist heute Ruhetag, und mit höchstens 3 Trainingstagen verteilen sich die Einheiten auf Donnerstag, Samstag und Dienstag. Die Woche ab 28.09. landet so bei 5800 m statt der vorgegebenen 5600 m, eine leichte Steigerung bei guter Erholung und einer Last-Ratio von 1,1. Der Samstag geht mit 2200 m nicht über die bisher längste Einheit hinaus, und der Dienstag übt gleichmäßiges Tempo nahe der CSS-Pace von 1:52/100 m. Das Ziel von 1500 m in 30 min (2:00/100 m) ist mit dieser CSS-Pace gut erreichbar.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Ruhetag | 0 | Ruhetag |
| Donnerstag 2026-10-01 | Schwimmen 1800 m locker (Technik) | 36 | Kraultechnik und lockere Grundlage |
| Freitag 2026-10-02 | Ruhetag | 0 | Ruhetag |
| Samstag 2026-10-03 | Schwimmen 2200 m locker (Ausdauer) | 44 | Lange lockere Grundlage |
| Sonntag 2026-10-04 | Ruhetag | 0 | Ruhetag |
| Montag 2026-10-05 | Ruhetag | 0 | Ruhetag |
| Dienstag 2026-10-06 | Schwimmen 2000 m moderat (Ausdauer) | 40 | Gleichmäßiges Tempo nahe CSS |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 100 % (Schwerpunkt 100 %)
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 8054 Token ein, 1751 Token aus, 17.1 s, ca. $0.067

### Heute

Der Wochenplan sieht heute Ruhe vor. Dein Technikwunsch geht aber vor, deshalb gibt es eine kurze, lockere Technikeinheit über 1000 m, deutlich unter deiner längsten Einheit von 2200 m. Mit 5400 m in den letzten 7 Tagen (Schnitt 5000 m, Verhältnis 1,1) und guter Erholung ist das vertretbar, solange es locker bleibt. In der Aufbauphase, 23 Wochen vor deinem 1500-m-Ziel in 30 min, bringt saubere Technik mehr als zusätzliche Meter.

**Schwimmen: Technik**, locker, 1000 m, ca. 24 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einschwimmen | 200 m | perceived_effort 3 | 30 s | Locker einschwimmen | Schwimm locker im Kraul ein und atme ruhig, gern im Wechsel links und rechts. |
| Technik Seitlage | 4 × 50 m | – | 20 s | Seitlage, 6 Kicks | Lieg auf der Seite, den unteren Arm nach vorn gestreckt, und mach ruhigen Beinschlag; nach 6 Beinschlägen machst du einen Kraulzug und drehst auf die andere Seite. Die Flossen helfen dir, dabei flach im Wasser zu liegen. |
| Technik Abschlag | 4 × 50 m | perceived_effort 3 | 20 s | Vorne abklatschen | Beim Abschlagschwimmen bleibt eine Hand vorne gestreckt, bis die andere nach dem Zug wieder vorne ankommt und sie abklatscht. So übst du einen langen, ruhigen Zug mit guter Gleitphase. |
| Hauptteil | 3 × 100 m | pace_per_100m 125 | 20 s | Lang ziehen, 2:05 | Schwimm ganz normal Kraul im lockeren Grundlagentempo und übertrage das Gefühl aus den Übungen: lang strecken und ruhig gleiten. Zähle auf einer Bahn die Züge und versuche, die Zahl stabil zu halten. |
| Ausschwimmen | 100 m | perceived_effort 2 | 0 s | Locker ausschwimmen | Schwimm ganz locker aus, gern in einer Lage deiner Wahl. |

Die Sicherheitsschicht hat nichts geändert.

> Halte alles locker, heute zählt die Qualität der Bewegung, nicht das Tempo.
> Plane in dieser Woche noch mindestens einen kompletten Ruhetag ein, du hast bereits drei Einheiten absolviert.

Prüfungen:

- [ ] Vorgabe des Wochenplans: geplant Schwimmen, Vorgabe Ruhetag
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9360 Token ein, 1790 Token aus, 19.0 s, ca. $0.073

## 06-laufen-nach-verletzung

Halbmarathon im März nach sechs Wochen Laufpause (Knie). Hält sich mit Rad fit, Schwerpunkt Laufen 60 %, Rad 40 % als Ausgleich. Wünscht flache Strecken, danach Feedback: mehr Rad am Anfang.

Heute 2026-09-30, Ziel am 2027-03-21: Laufen 21097 m; Schwerpunkte Laufen 60 %, Radfahren 40 %; 5 Tage, 5 h pro Woche.

Wunsch für die Woche: "Mein Knie ist noch empfindlich: beim Laufen nur flach und locker, keine Intervalle."

### Gesamtplan

**Kein Gesamtplan:** sanity_blocked

Prüfungen:

Keine automatischen Prüfungen.

Modell `claude-opus-5-5`, 9491 Token ein, 3035 Token aus, 32.6 s, ca. $0.099

### Die nächsten sieben Tage

Nach 45 Tagen Laufpause und mit empfindlichem Knie steigst du mit drei flachen, lockeren Läufen von 15 bis 20 min (50 min gesamt) wieder ein, ganz ohne Intervalle, wie gewünscht. Das Rad trägt mit 138 min die Ausdauer, darunter der 30-Minuten-Test am frischen Samstag, damit wir künftig Pulszonen fürs Rad haben. Mit deinem Schwellentempo von 5:15 pro km sind 2 h im Halbmarathon in 24 Wochen gut erreichbar, wenn der Laufumfang behutsam um etwa 10 % pro Woche wächst. Hat das Knie beim Laufen anhaltend Beschwerden, brich die Einheit ab und lass es ärztlich abklären.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Laufen 15 min locker (Ausdauer) + Radfahren 20 min locker (Regeneration) | 35 | Lauf-Wiedereinstieg und lockeres Rad |
| Donnerstag 2026-10-01 | Ruhetag | 0 | Ruhetag |
| Freitag 2026-10-02 | Laufen 15 min locker (Ausdauer) | 15 | Lockerer Lauf |
| Samstag 2026-10-03 | Radfahren 58 min hart (30-Minuten-Test) | 58 | Leistungstest Rad |
| Sonntag 2026-10-04 | Radfahren 60 min locker (Ausdauer) | 60 | Lockere Grundlage auf dem Rad |
| Montag 2026-10-05 | Ruhetag | 0 | Ruhetag |
| Dienstag 2026-10-06 | Laufen 20 min locker (Ausdauer) | 20 | Lockerer Lauf |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [ ] Schwerpunkte verteilt: Radfahren 73 % (Schwerpunkt 40 %), Laufen 27 % (Schwerpunkt 60 %)
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 8253 Token ein, 2114 Token aus, 21.8 s, ca. $0.075

### Heute

Dein letzter Lauf liegt 45 Tage zurück und die längste Laufeinheit der letzten 4 Wochen beträgt 0 min, daher steigst du heute mit 17 min lockerem Laufen und Gehpausen nach Gefühl wieder ein. Auf dem Rad bist du mit 120 min in 7 Tagen gut im Schnitt (110 min) und die Belastungsquote liegt bei 1,09, daher folgen 20 min lockeres Kurbeln zur Erholung. In der Aufbauphase ist das genau richtig: 172 Tage bis zum Halbmarathon in 2 h 00 min reichen, wenn der Laufumfang behutsam um etwa 10 % pro Woche wächst.

**Laufen: Ausdauer**, locker, 17 min, ca. 17 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einlaufen | 3 min | perceived_effort 2 | 0 s | Zügig gehen | Geh 3 Minuten zügig auf flacher Strecke, um Gelenke und Muskeln aufzuwärmen. |
| Hauptteil | 4 × 2 min | perceived_effort 3 | 60 s | Locker laufen | Lauf jeweils 2 Minuten ganz locker, sodass du dich problemlos unterhalten kannst, und geh danach 1 Minute. Achte auf kurze, leichte Schritte statt auf ein bestimmtes Tempo. |
| Auslaufen | 2 min | perceived_effort 2 | 0 s | Ausgehen | Geh 2 Minuten locker aus und lass den Atem ruhig werden. |

**Radfahren: Regeneration**, locker, 20 min, ca. 20 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einrollen | 5 min | perceived_effort 2 | 0 s | Leicht einrollen | Roll 5 Minuten mit leichtem Gang ein, ohne Druck auf den Pedalen. |
| Hauptteil | 12 min | cadence 90 | 0 s | Rund kurbeln | Fahr 12 Minuten in einem leichten Gang mit runder Trittfrequenz um 90 Umdrehungen pro Minute; die Knie bleiben locker und zeigen gerade nach vorn. |
| Ausrollen | 3 min | perceived_effort 2 | 0 s | Ausrollen | Roll 3 Minuten ganz locker aus. |

Die Sicherheitsschicht hat nichts geändert.

> Beim Laufen zählt heute nur das Gefühl, nicht das Tempo: Du solltest jederzeit sprechen können.
> Spürst du Schmerzen im Knie oder Schienbein, brich den Lauf ab und fahr stattdessen Rad; bei anhaltenden Beschwerden hol ärztlichen Rat ein.
> Morgen ist locker oder Ruhe sinnvoll, damit sich der Körper an das Laufen gewöhnt.

Prüfungen:

- [x] Vorgabe des Wochenplans: geplant Radfahren + Laufen, Vorgabe Radfahren + Laufen
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9665 Token ein, 2212 Token aus, 20.7 s, ca. $0.083

## 07-einsteiger-ohne-profil

Einsteiger ohne Leistungsprofil: erster Sprint-Triathlon im Juni, drei Tage und drei Stunden pro Woche. In jeder Sportart erst eine kurze Einheit. Die Einstiegstests sollen in den ersten zwei Wochen kommen.

Heute 2026-09-30, Ziel am 2027-06-13: Schwimmen 750 m, Radfahren 20000 m, Laufen 5000 m; Schwerpunkte Schwimmen 34 %, Radfahren 33 %, Laufen 33 %; 3 Tage, 3 h pro Woche.

### Gesamtplan

Bis zur Zielwoche sind es 36 Wochen. Weil die letzte Woche mit 65 min fast doppelt so viel war wie dein Schnitt von 33 min (Verhältnis 1,97), beginnt der Plan vorsichtig mit etwa 123 min: 1000 m Schwimmen, 60 min Rad und 30 min Laufen. Der Umfang steigt ab Woche 13 auf einen Höhepunkt von etwa 178 min mit 1600 m Schwimmen, 70 min Rad und 55 min Laufen. Bei 3 Trainingstagen mit je 2 Einheiten liegt die Wochengrenze von 180 min damit knapp darunter, ab Ende März kommen Schwelle, CSS-Serien und Koppeltraining dazu. Der Sprint über 750 m, 20 km und 5 km ist mit diesem Aufbau gut erreichbar, nach 1 Woche Zuspitzen gehst du frisch in die Zielwoche. Hinweis: Zur Sicherheit an 12 Stellen angepasst, die Wochen zeigen die geprüften Umfänge.

| Woche ab | Phase | Entlastung | Schwimmen | Radfahren | Laufen | Minuten | Tests | Schwerpunkt |
|---|---|---|---|---|---|---|---|---|
| 2026-09-28 | Aufbau | – | 1000 m / 2× | 60 min / 2× | 30 min / 2× | 123 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Locker einsteigen, Schwimmtechnik, Tests |
| 2026-10-05 | Aufbau | – | 1100 m / 2× | 65 min / 2× | 35 min / 2× | 137 | Laufen: Einstiegstest locker | Locker einsteigen, Schwimmtechnik, Tests |
| 2026-10-12 | Aufbau | – | 1200 m / 2× | 65 min / 2× | 35 min / 2× | 140 | – | Locker einsteigen, Schwimmtechnik, Tests |
| 2026-10-19 | Aufbau | ja | 800 m / 2× | 45 min / 2× | 20 min / 1× | 92 | – | Locker einsteigen, Schwimmtechnik, Tests |
| 2026-10-26 | Aufbau | – | 1250 m / 2× | 65 min / 2× | 40 min / 2× | 147 | – | Grundlage aufbauen, Technik, Tests |
| 2026-11-02 | Aufbau | – | 1350 m / 2× | 70 min / 2× | 40 min / 2× | 155 | – | Grundlage aufbauen, Technik, Tests |
| 2026-11-09 | Aufbau | – | 1400 m / 2× | 70 min / 2× | 45 min / 2× | 162 | – | Grundlage aufbauen, Technik, Tests |
| 2026-11-16 | Aufbau | ja | 950 m / 2× | 45 min / 2× | 30 min / 2× | 107 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Grundlage aufbauen, Technik, Tests |
| 2026-11-23 | Aufbau | – | 1450 m / 2× | 70 min / 2× | 45 min / 2× | 163 | Laufen: 30-Minuten-Test | Grundlage verlängern, Schwimmtechnik |
| 2026-11-30 | Aufbau | – | 1500 m / 2× | 70 min / 2× | 45 min / 2× | 165 | – | Grundlage verlängern, Schwimmtechnik |
| 2026-12-07 | Aufbau | – | 1550 m / 2× | 70 min / 2× | 50 min / 2× | 172 | – | Grundlage verlängern, Schwimmtechnik |
| 2026-12-14 | Aufbau | ja | 1050 m / 2× | 45 min / 2× | 35 min / 2× | 115 | – | Grundlage verlängern, Schwimmtechnik |
| 2026-12-21 | Aufbau | – | 1500 m / 2× | 70 min / 2× | 45 min / 2× | 165 | – | Grundlage halten, Tests über die Feiertage |
| 2026-12-28 | Aufbau | – | 1550 m / 2× | 70 min / 2× | 50 min / 2× | 172 | – | Grundlage halten, Tests über die Feiertage |
| 2027-01-04 | Aufbau | – | 1600 m / 2× | 70 min / 2× | 50 min / 2× | 173 | Laufen: 30-Minuten-Test | Grundlage halten, Tests über die Feiertage |
| 2027-01-11 | Aufbau | ja | 1100 m / 2× | 45 min / 2× | 35 min / 2× | 117 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Grundlage halten, Tests über die Feiertage |
| 2027-01-18 | Aufbau | – | 1500 m / 2× | 70 min / 2× | 50 min / 2× | 170 | – | Grundlage, erste Tempoabschnitte auf dem Rad |
| 2027-01-25 | Aufbau | – | 1550 m / 2× | 70 min / 2× | 50 min / 2× | 172 | – | Grundlage, erste Tempoabschnitte auf dem Rad |
| 2027-02-01 | Aufbau | – | 1600 m / 2× | 70 min / 2× | 55 min / 2× | 178 | – | Grundlage, erste Tempoabschnitte auf dem Rad |
| 2027-02-08 | Aufbau | ja | 1100 m / 2× | 45 min / 2× | 35 min / 2× | 117 | – | Grundlage, erste Tempoabschnitte auf dem Rad |
| 2027-02-15 | Aufbau | – | 1500 m / 2× | 70 min / 2× | 50 min / 2× | 170 | Laufen: 30-Minuten-Test | Grundlage und kurze Tempoabschnitte |
| 2027-02-22 | Aufbau | – | 1550 m / 2× | 70 min / 2× | 55 min / 2× | 177 | – | Grundlage und kurze Tempoabschnitte |
| 2027-03-01 | Aufbau | – | 1600 m / 2× | 70 min / 2× | 55 min / 2× | 178 | – | Grundlage und kurze Tempoabschnitte |
| 2027-03-08 | Aufbau | ja | 1100 m / 2× | 45 min / 2× | 35 min / 2× | 117 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Grundlage und kurze Tempoabschnitte |
| 2027-03-15 | Aufbau | – | 1500 m / 2× | 70 min / 2× | 50 min / 2× | 170 | – | Grundlage festigen, Übergang zur Wettkampfphase |
| 2027-03-22 | Aufbau | – | 1550 m / 2× | 70 min / 2× | 55 min / 2× | 177 | – | Grundlage festigen, Übergang zur Wettkampfphase |
| 2027-03-29 | Aufbau | – | 1600 m / 2× | 70 min / 2× | 55 min / 2× | 178 | – | Grundlage festigen, Übergang zur Wettkampfphase |
| 2027-04-05 | zielspezifisch | ja | 1100 m / 2× | 45 min / 2× | 35 min / 2× | 117 | Laufen: 30-Minuten-Test | Grundlage festigen, Übergang zur Wettkampfphase |
| 2027-04-12 | zielspezifisch | – | 1500 m / 2× | 70 min / 2× | 50 min / 2× | 170 | – | Schwelle, CSS-Serien und Koppeltraining |
| 2027-04-19 | zielspezifisch | – | 1550 m / 2× | 70 min / 2× | 55 min / 2× | 177 | – | Schwelle, CSS-Serien und Koppeltraining |
| 2027-04-26 | zielspezifisch | – | 1600 m / 2× | 70 min / 2× | 55 min / 2× | 178 | – | Schwelle, CSS-Serien und Koppeltraining |
| 2027-05-03 | zielspezifisch | ja | 1100 m / 2× | 45 min / 2× | 35 min / 2× | 117 | Schwimmen: CSS-Test 400/200 m, Radfahren: 30-Minuten-Test | Schwelle, CSS-Serien und Koppeltraining |
| 2027-05-10 | zielspezifisch | – | 1550 m / 2× | 70 min / 2× | 50 min / 2× | 172 | – | Wettkampfnahe Intervalle und Koppeltraining |
| 2027-05-17 | zielspezifisch | – | 1600 m / 2× | 70 min / 2× | 55 min / 2× | 178 | Laufen: 30-Minuten-Test | Wettkampfnahe Intervalle und Koppeltraining |
| 2027-05-24 | zielspezifisch | – | 1600 m / 2× | 70 min / 2× | 55 min / 2× | 178 | – | Wettkampfnahe Intervalle und Koppeltraining |
| 2027-05-31 | Zuspitzen | – | 950 m / 2× | 40 min / 2× | 30 min / 2× | 102 | – | Weniger Umfang, kurze schnelle Abschnitte |
| 2027-06-07 | Zielwoche | – | 500 m / 1× | 25 min / 1× | 15 min / 1× | 57 | – | Frisch und locker zum Wettkampf |

Korrekturen der Sicherheitsschicht:

- Woche ab 19.10.: Laufen von 25 min auf 20 min begrenzt (Entlastungswoche)
- Woche ab 16.11.: Radfahren von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 14.12.: Radfahren von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 11.01.: Radfahren von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 08.02.: Radfahren von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 08.03.: Radfahren von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 08.03.: Laufen von 40 min auf 35 min begrenzt (Entlastungswoche)
- Woche ab 05.04.: Radfahren von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 05.04.: Laufen von 40 min auf 35 min begrenzt (Entlastungswoche)
- Woche ab 03.05.: Radfahren von 50 min auf 45 min begrenzt (Entlastungswoche)
- Woche ab 03.05.: Laufen von 40 min auf 35 min begrenzt (Entlastungswoche)
- Woche ab 31.05.: Laufen von 35 min auf 30 min begrenzt (Zuspitzen)

Prüfungen:

- [x] Schwerpunkte verteilt: Schwimmen 30 % (Schwerpunkt 34 %), Radfahren 41 % (Schwerpunkt 33 %), Laufen 29 % (Schwerpunkt 33 %)
- [x] Höhepunkt vor dem Zuspitzen: höchste Woche ab 2027-02-01 (178 min), Zuspitzen ab 2027-05-31
- [x] Einstiegstests in den ersten zwei Wochen: Schwimmen, Radfahren, Laufen
- [x] Leistungstests im Plan: Schwimmen ab 2026-09-28; Radfahren ab 2026-09-28; Laufen ab 2026-10-05; Schwimmen ab 2026-11-16; Radfahren ab 2026-11-16; Laufen ab 2026-11-23; Laufen ab 2027-01-04; Schwimmen ab 2027-01-11; Radfahren ab 2027-01-11; Laufen ab 2027-02-15; Schwimmen ab 2027-03-08; Radfahren ab 2027-03-08; Laufen ab 2027-04-05; Schwimmen ab 2027-05-03; Radfahren ab 2027-05-03; Laufen ab 2027-05-17
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 10157 Token ein, 8688 Token aus, 83.6 s, ca. $0.214

### Die nächsten sieben Tage

Bei guter Erholung, aber einer Akut-chronisch-Quote von 1,97 nutze ich nur 3 Trainingstage mit rund 150 Minuten und lege die beiden harten Tests auf den Freitag und den Sonntag, jeweils nach einem Ruhetag. Der CSS-Test über etwa 1000 m und der 30-Minuten-Test auf dem Rad liefern erstmals Leistungswerte, damit du künftig nach Tempo- und Pulszonen trainieren kannst. Weil deine längste Laufeinheit der letzten 4 Wochen 15 Minuten beträgt, bleibt der Lauf bei 15 Minuten locker. Den lockeren Lauftest mit etwa 30 Minuten verschiebe ich, bis die Laufgrundlage länger ist. Dein Sprintziel im Juni 2027 ist mit 36 Wochen Aufbau gut erreichbar.

| Tag | Einheiten | Minuten | Schwerpunkt |
|---|---|---|---|
| Mittwoch 2026-09-30 | Schwimmen 500 m locker (Technik) + Laufen 15 min locker (Ausdauer) | 32 | Schwimmtechnik und lockerer Lauf |
| Donnerstag 2026-10-01 | Ruhetag | 0 | Ruhetag |
| Freitag 2026-10-02 | Schwimmen 1000 m hart (CSS-Test 400/200 m) + Radfahren 25 min locker (Regeneration) | 70 | CSS-Test Schwimmen und lockeres Rad |
| Samstag 2026-10-03 | Ruhetag | 0 | Ruhetag |
| Sonntag 2026-10-04 | Radfahren 58 min hart (30-Minuten-Test) | 58 | Radtest 30 Minuten |
| Montag 2026-10-05 | Ruhetag | 0 | Ruhetag |
| Dienstag 2026-10-06 | Ruhetag | 0 | Ruhetag |

Die Sicherheitsschicht hat nichts geändert.

Prüfungen:

- [ ] Schwerpunkte verteilt: Schwimmen 39 % (Schwerpunkt 34 %), Radfahren 52 % (Schwerpunkt 33 %), Laufen 9 % (Schwerpunkt 33 %)
- [x] Tests aus dem Gesamtplan eingeplant: Schwimmen am 2026-10-02, Radfahren am 2026-10-04
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 8932 Token ein, 2645 Token aus, 26.9 s, ca. $0.089

### Heute

Du bist in der Aufbauphase, 36 Wochen vor deinem Sprint-Triathlon mit 750 m Schwimmen, deshalb heute nur Technik und lockere Ausdauer. Die Belastung der letzten 7 Tage liegt beim 1,97-Fachen deines Wochenschnitts. Das liegt aber an der noch kleinen Basis von 33 Minuten pro Woche, und deine Erholung ist gut. Deshalb bleibt alles locker: Schwimmen mit 550 m knapp unter deinen bisher längsten 600 m, Laufen mit 15 min genau auf Höhe deiner längsten Einheit, mit Gehpausen.

**Schwimmen: Technik**, locker, 550 m, ca. 22 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Einschwimmen | 100 m | perceived_effort 2 | 30 s | Locker einschwimmen | Schwimm ganz locker Kraul oder Brust, wie es sich angenehm anfühlt. Komm in Ruhe im Wasser an. |
| Technik Seitlage | 4 × 50 m | – | 30 s | Seitlage, lang machen | Lieg auf der Seite, ein Arm ist nach vorn gestreckt, der andere liegt am Körper, und mach ruhigen Beinschlag mit Flossen. Zum Atmen drehst du den Kopf nur leicht aus dem Wasser und wechselst nach jeder Bahn die Seite. |
| Hauptteil | 2 × 100 m | perceived_effort 3 | 45 s | Ruhig atmen | Schwimm ruhig Kraul und atme nach jedem dritten Zug abwechselnd links und rechts ein. Unter Wasser atmest du gleichmäßig durch Nase und Mund aus. |
| Ausschwimmen | 50 m | perceived_effort 2 | 0 s | Locker ausschwimmen | Schwimm ganz locker in einer Lage deiner Wahl aus. |

**Laufen: Ausdauer**, locker, 15 min, ca. 15 min

| Schritt | Umfang | Ziel | Pause | Uhr | Hinweis |
|---|---|---|---|---|---|
| Gehen | 2 min | perceived_effort 2 | 0 s | Zügig gehen | Geh zügig los und lockere dabei Schultern und Arme. |
| Hauptteil | 3 × 3 min | perceived_effort 3 | 60 s | Gesprächstempo | Lauf so locker, dass du dich noch in ganzen Sätzen unterhalten kannst. In der Pause nach jedem Block gehst du eine Minute. |
| Auslaufen | 1 min | perceived_effort 1 | 0 s | Locker ausgehen | Geh langsam aus und lass den Puls ruhig sinken. |

Die Sicherheitsschicht hat nichts geändert.

> Wenn möglich, schwimm und lauf mit ein paar Stunden Abstand. Wenn du beides direkt hintereinander machst, lauf nach dem Schwimmen.
> Wenn du beim Laufen außer Atem kommst, geh einfach länger. Locker bleiben ist heute wichtiger als durchzulaufen.
> Morgen ist Ruhe oder nur lockere Bewegung dran.

Prüfungen:

- [x] Vorgabe des Wochenplans: geplant Laufen + Schwimmen, Vorgabe Laufen + Schwimmen
- [x] Begründung nennt das Ziel: ja

Modell `claude-opus-5-5`, 9927 Token ein, 2927 Token aus, 28.8 s, ca. $0.098

