# Verträge zwischen App und Server

Dieser Ordner enthält die Formate, auf die sich iPhone-App, Watch und Backend verlassen. **Beide Test-Suiten
lesen dieselben Dateien:** die Swift-Tests im Package (`ContractTests`) und die Jest-Tests im Backend
(`test/contracts.test.ts`). Ändert eine Seite ihr Format, wird die andere in der CI rot, ohne dass App und Server
gleichzeitig auf einem Gerät laufen müssen.

| Datei | Inhalt | Wer prüft |
|---|---|---|
| `sports.json` | Sportarten, Maße und Ziele der Schritte, plausibles Zieltempo (`goal_speed`), Lastfaktor, Einheit des Umfangs im Plan (`plan_unit`) und typisches Trainingstempo zum Umrechnen (`typical_speed_meters_per_second`), Leistungswerte mit plausiblem Bereich (`performance_metrics`, für alle Sportarten `athlete_metrics`) und Leistungstests (`performance_tests`) | Swift (`SportRegistry.standard`) und Backend (`SPORTS`) müssen genau das melden |
| `wire/snapshot-v2.json` | Zustands-Snapshot v2: Basisfelder (Ziel, Umfang, Pace, Last, Erholung) plus Gesamtziel aller Sportarten (seit P2 mit Zielart `kind` und Wochenraster `weekly_schedule`), Werte je Sportart, Gesamtlast | App erzeugt genau diese Felder, Server nimmt ihn an |
| `wire/snapshot-v2-profile.json` | Snapshot v2 mit Leistungsprofil (`performance`: Werte mit Herkunft und Zonen) | App rechnet aus derselben Lage genau dieses Profil, Server nimmt es an |
| `wire/snapshot-v2-starting-levels.json` | Snapshot v2 mit selbst angegebenem Startniveau (`starting_levels`: Wochenumfang, längste Einheit, Trainingsstand je Sportart) | App erzeugt aus den gespeicherten Angaben genau diese Felder, Server nimmt sie an |
| `wire/plan-v2-*-response.json` | Antworten der Planung (`plan_version: 2`): Tag mit Leistungstest, Tag bei Claude-Ausfall, sieben Tage, Gesamtplan, Überarbeitung nach Feedback (`/v1/plan/macro/revise`), Fortschreibung mit Bilanz (`/v1/plan/macro/review`), siehe [`docs/multisport-planning.md`](../docs/multisport-planning.md) | Server erzeugt über die echten Routen genau diese Felder, die App dekodiert sie |
| `app-storage/*.json` | Dateien und Einstellungen, die die App auf dem Gerät speichert, `training-goal.json`: das Gesamtziel, `performance-profile.json`: bestätigte Leistungswerte mit Verlauf, `weekly-schedule.json`: der Wochenraster) | Eine neue App-Version muss sie weiter lesen, solange Geräte mit der Form unterwegs sein können |

Regeln:

- Eine Datei hier ändert man nur zusammen mit beiden Seiten. Alte Formen bleiben als eigene Datei liegen, solange
  eine App oder ein Gerät sie noch schicken oder gespeichert haben kann.
- Neue Sportarten kommen zuerst in `sports.json`, dann als Modul in App (`Sports/Modules/`) und Backend
  (`src/sports/modules/`), siehe [`docs/neue-sportart.md`](../docs/neue-sportart.md).
