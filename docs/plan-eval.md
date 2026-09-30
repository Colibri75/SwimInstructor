# Plan-Bewertung der fünf Szenarien (M5)

Die Szenarien aus M3 liegen als Snapshots in `backend/scenarios/`. Der Lauf gegen die echte Claude-API
kommt aus `backend/scripts/eval-in-docker.sh` (Server) oder `npm run eval:scenarios` (Rechner mit Node),
siehe [plan-generation.md](plan-generation.md).

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

## Lauf 2: nach den Korrekturen

*Steht aus.* Er kostet wieder rund $0,20 und zeigt, ob die Pläne jetzt von Anfang an in die Grenzen
passen (die Zeile "Grenzen für heute" steht im Bericht über jedem Plan). Danach trägst du hier deine
Bewertung ein.

## Deine Bewertung (Definition of Done)

Bitte nach Lauf 2 ausfüllen. Orientierung, was ein sinnvoller Plan ist, steht in
[plan-generation.md](plan-generation.md).

| Szenario | sinnvoll | Begründung |
|---|---|---|
| 01 Anfänger | [ ] | |
| 02 Fortschritt | [ ] | |
| 03 Trainingspause | [ ] | |
| 04 Zieldatum nah | [ ] | |
| 05 Übertraining | [ ] | |
