# Verträge zwischen App und Server

Dieser Ordner enthält die Formate, auf die sich iPhone-App, Watch und Backend verlassen. **Beide Test-Suiten
lesen dieselben Dateien:** die Swift-Tests im Package (`ContractTests`) und die Jest-Tests im Backend
(`test/contracts.test.ts`). Ändert eine Seite ihr Format, wird die andere in der CI rot, ohne dass App und Server
gleichzeitig auf einem Gerät laufen müssen.

| Datei | Inhalt | Wer prüft |
|---|---|---|
| `sports.json` | Sportarten, Maße und Ziele der Schritte | Swift (`SportRegistry.standard`) und Backend (`SPORTS`) müssen genau das melden |
| `wire/snapshot-v1.json` | Zustands-Snapshot, wie die App ihn schickt | App dekodiert und kodiert ihn ohne Verlust, Server nimmt ihn an |
| `wire/plan-*-response.json` | Antworten von `/v1/plan/today`, `/week`, `/macro` | Server-Schemas lassen sie zu, App dekodiert sie |
| `app-storage/*.json` | Dateien, die die App heute auf dem Gerät speichert (auch ältere Formen) | Jede neue App-Version muss sie weiter lesen |

Regeln:

- Eine Datei hier ändert man nur zusammen mit beiden Seiten. Alte Formen bleiben als eigene Datei liegen, solange
  eine App oder ein Gerät sie noch schicken oder gespeichert haben kann.
- Neue Sportarten kommen zuerst in `sports.json`, dann als Modul in App (`Sports/Modules/`) und Backend
  (`src/sports/modules/`).
