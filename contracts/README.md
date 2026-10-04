# Verträge zwischen App und Server

Dieser Ordner enthält die Formate, auf die sich iPhone-App, Watch und Backend verlassen. **Beide Test-Suiten
lesen dieselben Dateien:** die Swift-Tests im Package (`ContractTests`) und die Jest-Tests im Backend
(`test/contracts.test.ts`). Ändert eine Seite ihr Format, wird die andere in der CI rot, ohne dass App und Server
gleichzeitig auf einem Gerät laufen müssen.

| Datei | Inhalt | Wer prüft |
|---|---|---|
| `sports.json` | Sportarten, Maße und Ziele der Schritte, plausibles Zieltempo (`goal_speed`), Lastfaktor, Einheit des Umfangs im Plan (`plan_unit`) und typisches Trainingstempo zum Umrechnen (`typical_speed_meters_per_second`), Leistungswerte mit plausiblem Bereich (`performance_metrics`, für alle Sportarten `athlete_metrics`) und Leistungstests (`performance_tests`) | Swift (`SportRegistry.standard`) und Backend (`SPORTS`) müssen genau das melden |
| `wire/snapshot-v1.json` | Zustands-Snapshot v1 (nur Schwimmen), wie ältere Apps ihn schicken | App dekodiert und kodiert ihn ohne Verlust, Server nimmt ihn an und baut daraus denselben Prompt wie vor v2 |
| `wire/snapshot-v2.json` | Zustands-Snapshot v2: v1 plus Gesamtziel aller Sportarten, Werte je Sportart, Gesamtlast | App erzeugt genau diese Felder, Server nimmt ihn an |
| `wire/snapshot-v2-profile.json` | Snapshot v2 mit Leistungsprofil (`performance`: Werte mit Herkunft und Zonen) | App rechnet aus derselben Lage genau dieses Profil, Server nimmt es an |
| `wire/plan-*-response.json` | Antworten von `/v1/plan/today`, `/week`, `/macro` | Server-Schemas lassen sie zu, App dekodiert sie |
| `wire/plan-v2-*-response.json` | Antworten von Plan v2 für mehrere Sportarten (`plan_version: 2`): Tag mit Leistungstest, Tag bei Claude-Ausfall, sieben Tage, Gesamtplan, Überarbeitung nach Feedback (`/v1/plan/macro/revise`), siehe [`docs/multisport-planning.md`](../docs/multisport-planning.md) | Server erzeugt über die echten Routen genau diese Felder, die App dekodiert sie |
| `app-storage/*.json` | Dateien und Einstellungen, die die App auf dem Gerät speichert, auch ältere Formen (`goal-swim-v1.json`: das Schwimmziel vor T2, `training-goal.json`: das Gesamtziel, `performance-profile.json`: bestätigte Leistungswerte mit Verlauf) | Jede neue App-Version muss sie weiter lesen |

Regeln:

- Eine Datei hier ändert man nur zusammen mit beiden Seiten. Alte Formen bleiben als eigene Datei liegen, solange
  eine App oder ein Gerät sie noch schicken oder gespeichert haben kann.
- Neue Sportarten kommen zuerst in `sports.json`, dann als Modul in App (`Sports/Modules/`) und Backend
  (`src/sports/modules/`), siehe [`docs/neue-sportart.md`](../docs/neue-sportart.md).
