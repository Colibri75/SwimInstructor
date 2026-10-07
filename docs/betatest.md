# Betatest: Checkliste

Was nur auf dem Gerät und am Körper prüfbar ist, kurz und in einer sinnvollen Reihenfolge. Die CI prüft Logik, Verträge
und Builds; hier geht es um Uhr, Health, Wasser, GPS und echte Pläne. Die Punkte stammen aus den offenen Prüfungen in den
[Meilensteinen](meilensteine.md) und den neuen Funktionen (Rückmeldung, Koppeltraining, drinnen, Wetter, Kalender,
Kraft und Mobilität, Wettkampftag).

Einen Fehler notierst du am besten mit Datum, Uhrzeit, Gerät und was du erwartet hast. Bei Plänen hilft ein Screenshot
und die Zeile aus `GET /v1/admin/usage` (Ergebnis, Grund, Dauer).

## 0. Vorbereitung (einmal, 15 Minuten)

- [ ] Server aktualisiert: `cd /opt/stack/swiminstructor && backend/deploy/deploy.sh` endet mit "Deploy erfolgreich"
- [ ] Alarme an: `ALERT_WEBHOOK_URL` (z. B. ntfy) in `/etc/swiminstructor/backend.env`, Container neu erstellt, ntfy-App
      auf dem iPhone abonniert ([backend-deploy.md](backend-deploy.md#alarme))
- [ ] Cron für `deploy/healthcheck.sh` eingetragen; einmal den Container stoppen (`docker stop swiminstructor-backend`):
      nach zwei Läufen (bei 5 Minuten Takt etwa 10 Minuten) kommt "Server antwortet nicht", nach dem Start
      "Server wieder erreichbar"
- [ ] Neueste Version aus TestFlight auf iPhone und Watch
- [ ] iPhone, Einstellungen: "Verbindung testen" meldet "Verbindung ok, Token gültig"; ein falsches Token ergibt eine verständliche
      Meldung, kein Absturz

## 1. Erster Start und Plan (Tag 1)

- [ ] Health-Dialog erscheint; nach Erlauben stehen echte Einheiten im Verlauf, Distanz und Dauer von drei Einheiten
      stimmen mit der Fitness-App
- [ ] Heute zeigt "Dein Coach passt deinen Plan für die nächsten Tage an …", danach den Tagesplan; das zweite Öffnen
      am selben Tag wartet nicht und plant nicht neu
- [ ] Gesamtplan (Plan-Tab, Gesamtplan) plausibel: Umfang steigt langsam, etwa jede vierte Woche Entlastung,
      Zuspitzen vor dem Ziel
- [ ] Synchronisierung: Während Heute noch lädt, im Plan-Tab heute von Schwimmen auf Laufen ändern: Am Ende zeigen
      Heute, Plan-Tab und Watch Laufen. Den Umfang mehrmals schnell ändern: eine Anpassung mit dem letzten Wert
- [ ] Einen kommenden Tag von Hand ändern, "Nächste 7 Tage neu planen": Der Tag bleibt (Stecknadel "von dir festgelegt"),
      "Wieder deinem Coach überlassen" plant ihn neu. Heute bleibt beim Neu-Planen, sobald es einen Plan gibt
- [ ] Vorschau für morgen holen, am nächsten Tag öffnen: Aktuell zeigt genau die Vorschau (keine Schmiede-Animation)
- [ ] Training von heute erledigt (alle geplanten Sportarten): Der Tab Aktuell zeigt "Heute | Morgen" und den Plan für
      morgen mit allen Schritten (holt ihn selbst); "Heute" zeigt wieder den Plan von heute. Am nächsten Morgen ist
      dieser Plan der Tagesplan
- [ ] Plan-Tab, auf einen Tag tippen: heute und vergangene Tage zeigen den Trainingsplan mit allen Schritten; bei einem
      kommenden Tag "Trainingsplan anzeigen" tippen, nach der Schmiede-Animation stehen Einheiten, Schritte und Equipment da
      und bleiben beim nächsten Öffnen; nach einer Änderung an dem Tag lässt sich die Vorschau neu holen
- [ ] Plan-Tab: Umfang ändern, "Keine Zeit" an einem Tag, zwei Tage tauschen, Sportart tauschen; danach "Nächste 7 Tage
      neu planen"
- [ ] Flugmodus: Heute zeigt den letzten Plan mit Hinweis, Dashboard und Verlauf zeigen ihre Daten
- [ ] Watch: Nach dem Öffnen der iPhone-App erscheint derselbe Plan; "Vom iPhone holen" liefert ihn, bei ausgeschaltetem
      iPhone kommt eine verständliche Meldung

## 2. Einstellungen der Planung (Tag 1)

- [ ] Planung: Kraft 2× und Mobilität 3× pro Woche; nach dem nächsten Planen stehen Kraft- und Mobilitätsblöcke in der
      Woche, am Tag mit Übungen unter den Einheiten. Kraft nie am Tag vor einer harten Einheit
- [ ] Equipment: Rolle an, Laufband aus. "Wetter berücksichtigen" an: Ortsdialog erscheint ("ungefähr" reicht)
- [ ] "Kalender berücksichtigen" an: Kalenderdialog erscheint; einen Tag mit vielen Terminen anlegen (z. B. 8 bis 20 Uhr
      belegt): Dieser Tag wird "Keine Zeit" oder kürzer, mit Hinweis in den Korrekturen
- [ ] Trainingsfenster (Beginn und Ende unter "Kalender berücksichtigen") verstellen: Ein Termin außerhalb des Fensters ändert nichts

## 3. Training mit der Uhr (Woche 1)

Je eine Einheit, danach in der Fitness-App Strecke, Karte und Herzfrequenz prüfen.

- [ ] **Becken:** Beckenlänge wählen, Wassersperre ist an; Bahnen, Strecke und Züge stimmen; Satz wechselt von selbst,
      wenn seine Strecke geschwommen ist; Pause zeigt "Pause 0:30" und zählt herunter; Crown plus Seitentaste pausiert;
      Workout steht in Health als Beckenschwimmen mit Bahnen
- [ ] **Trocken (zu Hause):** "Nächster Satz" auf der Steuerseite; Crown lange nach oben: Balken füllt sich, wechselt
- [ ] **Laufen draußen, Intervalle:** GPS-Strecke und Karte, Pace stimmt mit der Fitness-App, Ansagen zu den Wechseln
- [ ] **Rad draußen** mit und ohne Sensor (Watt, Trittfrequenz nur mit Sensor)
- [ ] **Drinnen:** Eine Einheit, die der Plan "drinnen (Rolle)" vorsieht: Auf der Watch ist "Drinnen" vorgewählt, kein GPS
- [ ] **Freiwasser:** Ziel (Einstellungen, Ziel) mit "Im Freiwasser" beim Schwimmen, unter Equipment "Zugang zu Freiwasser"
      an. In den 8 Wochen vor dem Ziel steht jede Woche eine Schwimmeinheit mit Wellen-Symbol im Plan; auf der Watch ist
      "Freiwasser" vorgewählt (GPS-Strecke, Wassersperre), der Hinweis "nie allein, mit Boje" steht dabei. Ohne Zugang
      enthalten die Beckeneinheiten Orientierungsschwimmen
- [ ] **Koppeltraining:** Rad, gleich danach den Koppellauf über "Starten" in der zweiten Einheit; beide stehen getrennt
      in Health
- [ ] Watch-Startseite: Zeit und Puls groß, Countdown 30 s mit Impulsen

## 4. Plan reagiert auf echtes Training (Woche 1 bis 2)

- [ ] Nach einer Einheit erscheint auf Heute "Wie war's?"; Anstrengung und "keine Beschwerden" sichern: nichts ändert sich
- [ ] Einmal "Beschwerden: deutlich, Knie" nach einem Lauf: Heute zeigt "Dein Plan wurde angepasst …", in den nächsten
      zwei Tagen ist Laufen nur locker und kürzer, andere Sportarten gehen weiter
- [ ] Einmal "stark": drei Tage kein Laufen
- [ ] Eine Einheit mit Anstrengung 9: Am nächsten Tag ist nichts Hartes geplant
- [ ] Eine geplante Einheit auslassen: Am nächsten Tag plant die App beim ersten Öffnen mit Anlass "ausgefallen" neu,
      ohne die Einheit nachzuholen oder zu stapeln
- [ ] Dieselbe Rückmeldung erneut öffnen und sichern: kein zweites Neuplanen

## 5. Wetter (wenn es passt)

- [ ] An einem Tag mit Gewitter- oder Sturmwarnung: Rad steht "drinnen (Rolle)" im Plan, Laufen ohne Laufband bleibt
      draußen mit Hinweis im Text
- [ ] An einem heißen Tag (ab 30 °C): Die Begründung geht auf die Hitze ein (z. B. früh trainieren, mehr trinken)

## 6. Leistungstests (Woche 2 bis 4)

- [ ] CSS-Test im Becken, 30-Minuten-Test Laufen und Rad: Die Watch wertet aus, das iPhone zeigt das Ergebnis zur
      Bestätigung; erst nach Bestätigung ändern sich Zonen und Tempo im Plan
- [ ] Ein Test im Wochenplan (z. B. CSS-Test) nach ein paar Schwimmtagen: Die Vorschau des Tages zeigt den Test und
      nicht "passt heute nicht". Passt er nicht in die 7 Tage, steht im Wochenplan schon "verlegt" oder "locker statt
      Leistungstest"
- [ ] Leistungsprofil: einen Wert von Hand ändern und sehen, dass der nächste Plan ihn nutzt

## 7. Gesamtplan, Ziel, Statistik (Woche 2 bis 4)

- [ ] Feedback zum Gesamtplan ("weniger Laufen im Winter"): Änderungen werden aufgelistet
- [ ] Ziel ändern (Feinjustierung sofort, neues Ziel höchstens alle 7 Tage): neuer Gesamtplan
- [ ] Pause melden (krank, 7 Tage): Fortschreibung, danach behutsamer Wiedereinstieg
- [ ] Dashboard: "Kachel hinzufügen" unter den Kacheln, eine Kachel nach links wischen und löschen, mit "Bearbeiten"
      umsortieren, im Detail einer Kachel "Kachel entfernen"; nach einem Neustart ist alles noch so
- [ ] Dashboard-Kachel auf "Laufen, Pace pro km" stellen, App neu starten: Einstellung bleibt, Zahl stimmt mit der
      Fitness-App
- [ ] Verlauf: Plan gegen Ist ist nach ein paar Tagen sinnvoll

## 8. Wettkampftag (sobald das Ziel näher rückt)

- [ ] Plan-Tab, Gesamtplan, "Plan für den Wettkampftag": Startzeit eingeben, erstellen. Ablauf mit Uhrzeiten, Pacing je
      Disziplin in deinen Zonen, Wechsel, Verpflegung (beim Schwimmen keine), Packliste
- [ ] Höchstens 14 Tage vor dem Ziel mit Wetter: Die Vorhersage steht in der Strategie, bei Hitze mehr Flüssigkeit

## 9. Mehrere Nutzer (optional)

- [ ] Auf dem Server `docker exec swiminstructor-backend node dist/cli/users.js add <name>`, Token auf einem zweiten
      iPhone eintragen: Beide bekommen ihre eigenen Pläne; `GET /v1/admin/usage` zeigt beide getrennt
- [ ] `users.js disable <name>`: Das zweite iPhone meldet "Der Server hat das Token abgelehnt"

## Danach

Nach zwei bis vier Wochen gemeinsam auswerten: Grenzen (vor allem Laufen), Testabstände, Häufigkeit der Anpassungen
außer der Reihe und die Kosten aus `GET /v1/admin/usage?days=30`.
