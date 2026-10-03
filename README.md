# SwimInstructor

> Hinweis: Das GitHub-Repo heißt jetzt `Colibri75/SwimInstructor` (umbenannt).
> Alte Links/Clones auf `Colibri75/SwimApp` werden von GitHub automatisch
> weitergeleitet, sollten aber aktualisiert werden.

iOS- und watchOS-App, die Schwimm-Trainingsdaten aus Apple Health liest und
darauf basierend einen tagesaktuellen, von Claude generierten Trainingsplan
erstellt. Ziel (Standard, in den Einstellungen änderbar): 3.800 m unter 60 Minuten bis zum 04.07.2027.

Der Code wird auf einem beliebigen Rechner (z.B. Windows) bearbeitet. Bauen,
Signieren und Verteilen läuft vollautomatisch über GitHub Actions + Fastlane +
TestFlight (Apple Developer Program vorausgesetzt) – ein eigener Mac ist dafür
nicht nötig. Details siehe [CI/CD-Setup](#cicd-setup--testflight) unten.

## Architektur: iOS + watchOS

Die Watch-App ist eine **Companion-App**, die zusammen mit der iPhone-App im
selben Build/derselben TestFlight-Installation ausgeliefert wird (kein
separater Store-Eintrag, keine separate Pipeline nötig). Gemeinsame Logik
(HealthKit-Zugriff, später Zustandsberechnung und Backend-API-Client) liegt in
einem lokalen Swift Package `Packages/SwimInstructorCore`, das von beiden
Targets genutzt wird – so entsteht kein doppelt gepflegter Code.

- **iOS-App** (`App/`): vollständige UI, Dashboard, Verlauf
- **watchOS-App** (`WatchApp/`): Tagesplan vom iPhone und Live-Aufzeichnung im Becken (ab M7)
- **SwimInstructorCore** (`Packages/SwimInstructorCore/`): HealthKit-Zugriff, Zustandsmodell, API-Client – plattformunabhängig, eigene Test-Suite

Die Watch-App fragt HealthKit **eigenständig** an und zeichnet Einheiten ohne
iPhone in Reichweite auf – wichtig, weil man beim Schwimmen das iPhone nicht
dabei hat. Den Plan spricht sie nicht selbst beim Server ab: Sie bekommt ihn vom
iPhone und hält ihn lokal vor (siehe M7).

## CI/CD-Setup & TestFlight

Pipeline: `git push` auf `main` → GitHub Actions baut auf einem macOS-Runner,
lässt die Unit-Tests laufen, signiert per [fastlane match](https://docs.fastlane.tools/actions/match/)
und lädt den Build zu TestFlight hoch. Installation aufs iPhone dann über die
TestFlight-App – kein manuelles Signieren, kein eigener Mac im Alltag.

### Einmaliges Setup (Account-Seite, nicht Code)

1. **Apple Developer Program** unter developer.apple.com abschließen (99$/Jahr,
   Freischaltung kann bis zu 48h dauern).
2. **App-IDs registrieren** (developer.apple.com/account → Certificates,
   Identifiers & Profiles → Identifiers → +), explizit (keine Wildcards), mit
   aktivierter HealthKit-Capability:
   - `com.kellner.SwimInstructor`
   - `com.kellner.SwimInstructor.watchkitapp`
3. **App Store Connect:** neuen App-Eintrag anlegen – Bundle-ID
   `com.kellner.SwimInstructor` (muss exakt zu `project.yml` passen),
   Name z.B. "SwimInstructor", SKU frei wählbar. Kein Store-Release nötig, nur
   für TestFlight. Die Watch-App braucht **keinen** eigenen
   App-Store-Connect-Eintrag – sie hängt am iOS-Eintrag und wird als Teil
   desselben Builds mit hochgeladen.
4. **App Store Connect API Key** erzeugen (Users and Access → Tab
   Integrations → App Store Connect API → Team Keys → Generate API Key,
   Rolle "App Manager"): Key-ID, Issuer-ID notieren, `.p8`-Datei herunterladen
   (nur einmal möglich!).
5. **Separates privates Repo nur für Zertifikate** anlegen, z.B.
   `Colibri75/SwimInstructor-certificates` – niemals in diesem App-Repo, auch
   nicht wenn das public ist.
6. **Einmaliger Mac-Zugriff** (z.B. 1h MacinCloud) für die Ersteinrichtung von
   `fastlane match`:
   ```bash
   bundle install
   bundle exec fastlane match appstore
   ```
   Legt Verteilungszertifikat + Provisioning Profile verschlüsselt im
   Certificates-Repo ab. Danach wird dieser Schritt nie wieder manuell
   gebraucht – CI nutzt dieselben Zertifikate schreibgeschützt (`readonly`).
7. **GitHub Secrets** im `SwimInstructor`-Repo hinterlegen (Settings → Secrets and
   variables → Actions):

   | Secret | Wert |
   |---|---|
   | `APPLE_ID` | deine Apple-ID-E-Mail |
   | `APPLE_TEAM_ID` | aus developer.apple.com/account → Membership Details |
   | `MATCH_GIT_URL` | HTTPS-URL des Certificates-Repos |
   | `MATCH_PASSWORD` | selbst gewähltes Passwort zum Verschlüsseln der Zertifikate |
   | `MATCH_GIT_BASIC_AUTHORIZATION` | `base64("github-username:PAT")` mit Lesezugriff aufs Certificates-Repo |
   | `APP_STORE_CONNECT_KEY_ID` | aus Schritt 4 |
   | `APP_STORE_CONNECT_ISSUER_ID` | aus Schritt 4 |
   | `APP_STORE_CONNECT_KEY_CONTENT` | kompletter **roher** Inhalt der `.p8`-Datei (in einem Texteditor öffnen, alles inkl. `-----BEGIN PRIVATE KEY-----`/`-----END PRIVATE KEY-----` 1:1 reinkopieren – **kein** base64) |

8. **TestFlight-App** aus dem App Store auf dein iPhone laden, damit du
   hochgeladene Builds direkt installieren kannst.
9. Optional: Repo auf **public** stellen → macOS-CI-Minuten dauerhaft
   kostenlos (siehe unten).

Sobald die Secrets gesetzt sind, läuft alles Weitere automatisch bei jedem
Push auf `main`: Tests → Build → Sign → TestFlight-Upload.

### Kosten-Hinweis

- Öffentliches Repo: GitHub Actions inkl. macOS-Runner kostenlos.
- Privates Repo: 2.000 Freiminuten/Monat, macOS zählt mit Faktor 10 (~200
  echte macOS-Minuten gratis), danach 0,062$/Minute (Stand 01/2026).

## M1 – Projekt-Setup & HealthKit-Berechtigung

Dieses Repo enthält kein eingechecktes `.xcodeproj` (siehe `.gitignore`) –
stattdessen [XcodeGen](https://github.com/yonaskolb/XcodeGen) mit `project.yml`
als Quelle der Wahrheit. Das vermeidet Merge-Konflikte in der binären
Xcode-Projektdatei und lässt sich reproduzierbar neu erzeugen.

### Setup auf dem Mac (optional, nur für interaktives Debugging)

Für den Alltag brauchst du das dank CI/CD + TestFlight nicht. Nur falls du
mal interaktiv debuggen willst (Breakpoints, UI-Vorschau live testen):

```bash
brew install xcodegen
cd SwimInstructor
xcodegen generate
open SwimInstructor.xcodeproj
```

In Xcode:
1. Target `SwimInstructor` auswählen → Tab **Signing & Capabilities**
2. Bei **Team** dein Apple-Developer-Team auswählen
3. Dein iPhone per Kabel/WLAN als Build-Ziel wählen, ⌘R

### M1 – Definition of Done (manuell zu verifizieren)

- [ ] `xcodegen generate` läuft ohne Fehler
- [ ] Projekt baut fehlerfrei (Debug, per lokalem Build oder via CI-Test-Lane)
- [ ] App installiert sich auf dem iPhone – primär über **TestFlight**
      (Ergebnis der `beta`-Lane), alternativ lokal per Xcode
- [ ] Beim Tippen auf "Health-Zugriff anfragen" erscheint der HealthKit-Dialog
- [ ] **Testfall A:** Zugriff erlauben → Status wechselt zu "Health-Zugriff
      angefragt ✓", kein Crash
- [ ] **Testfall B:** App löschen, neu installieren, Zugriff ablehnen → App
      bleibt stabil, kein Crash, keine Endlosschleife
- [ ] Watch-App installiert sich automatisch mit auf eine gekoppelte Apple
      Watch, zeigt den Platzhalter-Screen, HealthKit-Dialog erscheint dort
      unabhängig vom iPhone-Dialog

### Unit-Tests

Alle aktuellen Tests leben im `SwimInstructorCore`-Package und laufen direkt
per `swift test` – ganz ohne Simulator, genau so auch in der CI (`fastlane
test`-Lane):

```bash
cd Packages/SwimInstructorCore && swift test
```

`HealthKitManagerTests` prüft, dass alle für M2/M3 benötigten HealthKit-Typen
(Workouts, Herzfrequenz, Ruhepuls, HRV, Schwimmdistanz, Schlaf) im
Autorisierungs-Request enthalten sind.

## M2 – HealthKit Data Layer

`SwimWorkoutRepository` (in `Packages/SwimInstructorCore`) liest reale
`.swimming`-Workouts inkl. Distanz, Dauer, Bahnenzahl, Zügen und
Durchschnitts-Herzfrequenz. Fetching (I/O gegen HealthKit) und Mapping (reine
Transformation `HKWorkout` → `SwimWorkout`) sind bewusst getrennt, damit das
Mapping ganz ohne Gerät/Simulator testbar ist – die Tests konstruieren echte,
aber nicht gespeicherte `HKWorkout`-Objekte (Apples empfohlener Weg, um
HealthKit-Code ohne echten Health Store zu testen).

`SwimWorkout.approximateAverageSwolf` ist eine Näherung (Zeit + Züge pro
Bahn, gemittelt) – ein offizieller SWOLF-Wert existiert in HealthKit nur für
Workouts, die Apples eigene Schwimm-App mit Lap-Metadaten aufgezeichnet hat.

Die iOS-`ContentView` zeigt nach dem Health-Zugriff eine einfache Liste
"Meine letzten Schwimmeinheiten" zur Verifikation, dass echte Daten ankommen.

### M2 – Definition of Done (manuell zu verifizieren)

- [ ] Nach Health-Zugriff erscheint mind. 1 reales Workout aus der Health-App
      korrekt in der Liste (Datum, Distanz, Dauer, Pace)
- [ ] **Abgleich:** Distanz/Dauer von 3 realen Workouts stimmen mit den
      Werten in der Health-App überein (Abweichung 0)
- [ ] Kein Crash, wenn keine Schwimm-Workouts vorhanden sind (Liste zeigt
      "Noch keine Schwimm-Workouts gefunden")
- [ ] Kein Crash bei einem Workout ohne Streckenangabe (Distanz/Pace zeigen
      einfach nichts an, statt abzustürzen)

## M3 – Athleten-Zustand-Berechnung

`AthleteStateCalculator` (in `Packages/SwimInstructorCore`) rechnet aus Workouts,
Tageswerten (Ruhepuls, HRV, Schlaf) und dem Ziel den `AthleteStateSnapshot`:
Wochenvolumen, Pace-Trend, Abstand zum Zielpace, Tage bis zum Zieldatum, Tage
seit der letzten (harten) Einheit, Erholungsstatus und Warn-Flags. Die Berechnung
ist eine reine Funktion ohne HealthKit-Zugriff und komplett per Unit-Test prüfbar.
Doppelte Einträge derselben Einheit (mehrere Quellen in Health) bereinigt
`SwimWorkoutDeduplicator`.

Schema, Definitionen und Schwellenwerte: [`docs/AthleteStateSnapshot.md`](docs/AthleteStateSnapshot.md).

### M3 – Definition of Done

- [x] Berechnungsfunktionen für Wochenvolumen, Pace-Trend, Tage bis Zieldatum,
      Tage seit letzter harter Einheit und Erholungsindikatoren
- [x] JSON-Schema des Snapshots dokumentiert und per Test gegen Änderungen abgesichert
- [x] 5 Testszenarien (Anfänger, guter Fortschritt, Trainingspause, kurz vor
      Zieldatum, Übertraining-Warnsignal) mit von Hand nachgerechneten Werten
- [x] Coverage der Kernlogik > 80 % (Zeilen-Coverage laut CI-Report:
      `AthleteStateCalculator` 99,6 %, `AthleteStateSnapshot` 100 %,
      `SwimWorkoutDeduplicator` 100 %, `DailyVitals` 100 %, `AthleteGoal` 88 %).
      Den Report schreibt der CI-Job `test` pro Datei ins Log. Nicht abgedeckt
      ist der HealthKit-I/O (`HealthKitManager`, Fetch-Teil von
      `SwimWorkoutRepository`), der sich nur auf dem Gerät prüfen lässt; darum
      liegt die Gesamtzahl bei 66,6 %.

## M4 – Backend-Grundgerüst

`backend/` enthält den Server (Node 22, TypeScript, Express 5). Er läuft als Docker-Container,
veröffentlicht seinen Port nur auf `127.0.0.1` des Servers, und der Reverse-Proxy (Caddy) übernimmt
HTTPS.

| Route | Auth | Zweck |
|---|---|---|
| `GET /health` | keine | Lebenszeichen für Monitoring/Deploy-Check, keine Daten |
| `GET /v1/status` | Bearer-Token | Prüfroute für die Token-Auth, Basis für M5 (`/v1/plan/today`) |

- **Auth:** `Authorization: Bearer <API_TOKEN>`, Vergleich zeitkonstant über SHA-256.
  Ohne oder mit falschem Token antwortet der Server mit `401`. Die Prüfung läuft vor dem
  Body-Parsing.
- **Konfiguration:** über Umgebungsvariablen (`backend/.env.example`). Ohne `API_TOKEN` startet
  der Server nicht; in Produktion muss er mindestens 32 Zeichen haben.
- **Logging:** strukturiertes JSON (pino) für Requests und Fehler. Der Authorization-Header wird
  geschwärzt, `/health` nicht protokolliert.
- **Fehler:** interne Fehler liefern `500` ohne Details nach außen, der Stacktrace steht nur im Log.

```bash
cd backend
npm ci
npm test          # Jest + supertest, inkl. Coverage-Schwelle
npm run dev       # lokal starten (API_TOKEN vorher setzen)
```

Einrichtung auf dem Server (Docker + Caddy): [`docs/backend-deploy.md`](docs/backend-deploy.md).
CI: `.github/workflows/backend-ci.yml` (Typecheck, Build, Tests, `npm audit`) plus ein Job, der das
Deployment nachstellt: Image bauen, Container per `compose.yaml` starten, Smoke-Test.

### M4 – Definition of Done

- [x] Server auf dem VPS deployt, per HTTPS mit gültigem Zertifikat erreichbar
      (30.09.2026 verifiziert: `https://swiminstructor.kellner.v6.rocks/health` liefert 200;
      Zertifikat von ZeroSSL, weil das Let's-Encrypt-Limit für `v6.rocks` erreicht war)
- [x] `/health` liefert 200
- [x] Token-Auth aktiv, unautorisierte Requests liefern 401
- [x] Minimal-Logging für Requests und Fehler
- [x] Integrationstests (Jest + supertest): Auth erfolgreich/fehlgeschlagen, Health, Fehlerfälle,
      Logging, Konfiguration

## M5 – Claude-Integration & Sanity-Layer

`POST /v1/plan/today` nimmt den Zustands-Snapshot aus M3 entgegen, lässt Claude daraus einen
Tagesplan schreiben und prüft ihn, bevor er die App erreicht. Das Backend ist damit der einzige
Ort, an dem der Anthropic-API-Key liegt.

- **Claude-Aufruf:** fester deutscher System-Prompt, strukturierte JSON-Ausgabe (`output_config.format`),
  Standardmodell `claude-opus-5-5`, per `PLAN_MODEL` wechselbar.
- **Sicherheitsschicht:** reiner Code, der gefährliche Vorschläge korrigiert oder blockt (zu große
  Umfangssprünge, fehlende Ruhetage, zwei harte Einheiten hintereinander, schlechte Erholung,
  unrealistische Zeiten).
- **Fallback:** Fällt Claude aus, liefert der Server den letzten gültigen Plan, vorher erneut gegen
  den heutigen Zustand geprüft. Ein Aufrufbudget begrenzt die Kosten.
- **Eingabe:** Der Snapshot wird streng validiert, unbekannte Felder erreichen Claude nie.

Details zu Ablauf, Antwortformat, Regeln, Kosten und Konfiguration:
[`docs/plan-generation.md`](docs/plan-generation.md). Einrichtung des API-Keys auf dem Server:
[`docs/backend-deploy.md`](docs/backend-deploy.md).

```bash
cd backend
npm test                   # Sicherheitsschicht, Fehlerfälle, Route, Szenarien (ohne echte API)
ANTHROPIC_API_KEY=... npm run eval:scenarios > ../docs/eval-runs/plan-eval-$(date +%F).md   # echter Lauf, kostet Geld
backend/scripts/eval-in-docker.sh   # dasselbe auf dem Server ohne Node (nur Docker nötig)
```

### M5 – Definition of Done

- [x] `/v1/plan/today` ruft Claude mit festem System-Prompt und striktem JSON-Schema auf
      (30.09.2026 auf dem Server verifiziert: fünf echte Aufrufe, 6 bis 19 s, rund 4 Cent pro Plan)
- [x] Für alle 5 Testszenarien aus M3 liefert Claude plausible Pläne, manuell bewertet und
      dokumentiert. Lauf 2 (30.09.) mit allen fünf Plänen als "sinnvoll" bewertet. Offener Wunsch aus der
      Bewertung (Übungen erklären) ist per Prompt umgesetzt, siehe [`docs/plan-eval.md`](docs/plan-eval.md)
- [x] Sanity-Layer korrigiert oder blockt gefährliche Vorschläge
- [x] Fallback bei Claude-Ausfall: letzter gültiger Plan statt Absturz oder leerer Antwort
- [x] Kostenkalkulation dokumentiert und gemessen (rund $0,038 pro Plan, siehe `docs/plan-generation.md`)
- [x] Unit-Tests der Sicherheitsschicht mit absichtlich gefährlichen Claude-Antworten
- [x] Fehlerfall-Tests: API nicht erreichbar, ungültiges JSON, Zeitlimit (und Rate-Limit,
      Serverfehler, Ablehnung, abgeschnittene Antwort)

## M6 – App ↔ Backend & Heute-Bildschirm

Die iPhone-App liest beim Öffnen Workouts und Erholungswerte aus Health, rechnet daraus den
Snapshot (M3) und holt sich damit den Tagesplan vom Server (M5). Der Platzhalter ist durch einen
echten **Heute-Bildschirm** ersetzt.

> Eine eigene M6-Beschreibung gab es im Repo nicht (die Roadmap lag in einer früheren Session).
> Umgesetzt ist, was die Doku bisher für M6 ankündigt: Snapshot-Builder mit Erholungswerten aus
> Health, API-Client im Package und die Plananzeige auf dem iPhone. Die Watch-App folgt später.

- **Snapshot-Builder** (`SnapshotBuilder`): Workouts der letzten 56 Tage, Ruhepuls, HRV und Schlaf
  der letzten 31 Tage (`HealthKitDailyVitalsRepository`). Schlaf zählt zum Aufwachtag, überlappende
  Abschnitte aus mehreren Quellen werden zusammengeführt (`DailyVitalsAggregator`). Fehlen die
  Erholungswerte, gibt es trotzdem einen Plan (Erholung `unknown`).
- **API-Client** (`PlanAPIClient`): `POST /v1/plan/today` mit `{"snapshot": …}` und
  `GET /v1/status` für "Verbindung testen". Zeitlimit 95 s, damit die App nicht vor dem Server
  (75 s) aufgibt. Fehler kommen als `PlanAPIError` mit deutschem Text.
- **Wann wird gefragt?** Beim Öffnen liest die App Health immer neu, den Plan holt sie nur, wenn noch
  keiner von heute da ist (oder der letzte ein Fallback war). Ziehen zum Aktualisieren holt immer
  einen **neuen** Plan (`regenerate` im Request, der Server überspringt dann seinen Cache). Das kostet
  einen Claude-Aufruf und zählt gegen das Budget des Servers.
- **Wunsch für heute:** Auf dem Heute-Bildschirm steht unter dem Plan das Feld "Dein Wunsch für heute"
  (Freitext, höchstens 300 Zeichen, zum Beispiel "Heute lieber Technik, die Schulter zwickt"). Der Knopf
  "Plan mit Wunsch neu erstellen" speichert ihn und holt sofort einen neuen Plan. Der Wunsch gilt nur
  für diesen Kalendertag und geht bei jeder Plananfrage des Tages mit (auch beim Ziehen). Er ist Teil
  des Server-Cache-Schlüssels. Claude berücksichtigt ihn, **soweit er in die Sicherheitsgrenzen passt**:
  Mehr Umfang als erlaubt oder eine harte Einheit an einem Ruhetag bekommst du nicht, die Begründung
  sagt dann in einem Satz, warum. Der Wunsch steht im Prompt als JSON-String und ist als Daten
  gekennzeichnet, die Sicherheitsschicht prüft den Plan unabhängig davon. Der Wunsch wird beim Tippen
  gespeichert (Ziehen nutzt ihn auch ohne Knopf). **Der Server meldet ihn mit dem Plan zurück, die Karte
  zeigt ihn als "Dein Wunsch: …" über der Begründung.** Fehlt die Zeile trotz eingegebenem Wunsch, ist er
  nicht angekommen (alter Server ohne `deploy.sh`). Im Server-Log steht bei `plan generated` die Länge
  als `wishChars`.
- **Offline:** Der letzte Plan liegt in `Application Support/SwimInstructor/last-plan.json` und
  bleibt sichtbar, wenn der Server nicht erreichbar ist.
- **Zugang:** Server-Adresse (Standard `https://swiminstructor.kellner.v6.rocks`) und Token werden
  einmal in den Einstellungen (Zahnrad) eingetragen. Das Token ist der Wert von `API_TOKEN` auf dem
  Server und liegt nur im Schlüsselbund des iPhones, nie im Code oder im Build.
- **CI:** Die `test`-Lane kompiliert jetzt zusätzlich die App samt Watch-App (ohne Signatur), damit
  Fehler im App-Code schon im Pull Request auffallen und nicht erst beim TestFlight-Build.

### M6 – Definition of Done

- [x] Snapshot wird aus echten Health-Daten gebaut, inkl. Ruhepuls, HRV und Schlaf
- [x] API-Client im Package, Antwortformat und Fehlerfälle per Unit-Test abgesichert
      (`PlanAPIClientTests`, `TrainingPlanTests`, `SnapshotBuilderTests`, `TodayPlanLoaderTests`)
- [x] Heute-Bildschirm zeigt Plan (Art, Umfang, Dauer, Begründung, Abschnitte mit Zielpace und Pause,
      Hinweise, Korrekturen der Sicherheitsschicht), den Stand und die bisherigen Einheiten
- [x] Fallback-Plan wird als solcher gekennzeichnet, der letzte Plan bleibt offline sichtbar
- [ ] **Auf dem iPhone (TestFlight):** Token eintragen, "Verbindung testen" meldet "Verbindung ok"
- [ ] **Auf dem iPhone:** Beim ersten Öffnen am Tag erscheint ein Plan für heute; erneutes Öffnen holt
      keinen neuen (kein Aufruf im Server-Log), **Ziehen zum Aktualisieren** holt einen neuen Plan
      (neuer Claude-Aufruf im Server-Log, `plan generated`)
- [ ] **Auf dem iPhone:** Flugmodus an, App öffnen: der letzte Plan bleibt stehen, Hinweis auf den
      Verbindungsfehler statt Absturz
- [ ] **Auf dem iPhone:** Falsches Token eintragen: verständliche Meldung, kein Absturz

## M7 – Watch-App: Tagesplan & Live-Aufzeichnung im Becken

Die Watch zeigt den Plan von heute und zeichnet die Einheit im Becken auf: Bahnen, Strecke, Züge,
Puls, Pace. Während des Schwimmens sieht man, in welchem Abschnitt des Plans man steckt und wie viel
von der laufenden Wiederholung noch fehlt. Das Workout landet in Health, das iPhone liest es beim
nächsten Öffnen und der nächste Plan berücksichtigt es.

> Auch für M7 gab es keine Beschreibung im Repo; umgesetzt ist Option 1 aus dem Projekt-Chat
> ("Watch-App ausbauen: Tagesplan zeigen, Bahnen und Züge live aufzeichnen").

- **Plan aufs Handgelenk** (`PhonePlanSync` auf dem iPhone, `WatchPlanStore` auf der Watch,
  Format `PlanSyncCodec` im Package): Jeder neue Plan geht per WatchConnectivity als Application
  Context an die Watch; die Watch speichert ihn (`FilePlanCache`) und zeigt ihn auch ohne iPhone in
  der Nähe. "Vom iPhone holen" fragt aktiv nach, das iPhone antwortet sofort mit seinem Plan und
  schickt einen neueren nach. Die Watch bekommt **kein** Token und spricht nie selbst mit dem
  Server; ist der Plan nicht von heute, sagt sie das.
- **Aufzeichnung** (`SwimWorkoutManager`): `HKWorkoutSession` als Beckenschwimmen mit der gewählten
  Bahnlänge (25 m, 50 m oder 10–100 m per Digital Crown, wird gemerkt), Live-Werte über den
  `HKLiveWorkoutBuilder`, Wassersperre beim Start wie in Apples Schwimm-App. Pause, Fortsetzen,
  Beenden; beim Beenden wird das Workout mit Bahnlänge in Health gespeichert.
- **Anzeige beim Schwimmen** (seitlich wischen): Steuerung · Zeit, Strecke, Bahnen, Pace (Schnitt
  inkl. Pausen), Züge pro Bahn, Puls · Stand im Plan ("Hauptsatz, 3 von 6 × 200 m, noch 150 m").
  Die Zuordnung zum Plan läuft nur über die Meter (`PlanProgress`), nicht über Pausen.
  Unter dem Namen des Abschnitts steht die Anweisung aus dem Plan ("Locker kraulen", Technikübung mit
  Erklärung), bis zu sechs Zeilen, verkleinert bei langen Texten. In der Plan-Liste vor dem Start steht sie
  in voller Länge.
- **Satz- und Abschnittswechsel** (`SwimWorkoutManager.progress`): Der Manager hält den Stand im Plan und alle
  Ansichten lesen ihn. Ein **Satz** ist eine Wiederholung ("6 × 200 m" hat sechs Sätze); von Hand wechselt man
  **von Satz zu Satz**, erst nach dem letzten Satz beginnt der nächste Abschnitt. Drei Wege führen zum nächsten
  Satz, jeder mit einem Haptik-Impuls:
  1. **Automatisch:** Der Satz endet, wenn seine Strecke geschwommen ist. Als Strecke gilt das
     Größere aus der Distanz von Health und Bahnen mal Beckenlänge (`progressMeters`), damit der Plan nicht
     stehen bleibt, falls Health die Strecke verspätet meldet.
  2. **Crown drehen, auch bei Wassersperre:** Am Stück weit genug in eine Richtung drehen
     (`CrownRotationTracker`): **nach oben = nächster Satz, nach unten = vorheriger**. Die Schwelle
     liegt entsperrt bei 8 und bei Wassersperre bei 14 Einheiten, die Crown ist auf mittlere Empfindlichkeit
     gestellt (`.medium`). Bei Wassersperre ist sie höher, damit die Drehung, die das System zum Entsperren
     braucht, nicht schon wechselt ("weiterdrehen, bis der Balken voll ist", wie bei MySwimPro). Ein Balken
     zeigt den Fortschritt (gelb = weiter, orange = zurück). Eine Drehpause von über 1,5 s oder ein
     Richtungswechsel zählt von vorn. **Nach einem Wechsel zählt die Crown erst wieder, wenn sie 0,8 s
     stillstand:** Wer einfach weiterdreht, löst nicht gleich den nächsten Wechsel aus (`settleTime`). Ist "oben" bei deiner Uhr verkehrt herum, steht `upIsPositive` im
     `CrownRotationTracker` auf `false`; zu empfindlich oder zu träge: `unlockedThreshold`,
     `lockedThreshold` anpassen.
  3. **Taste "Nächster Satz":** auf der Steuerseite (links von den Werten) und auf der Plan-Seite,
     funktioniert auch bei pausierter Einheit und ohne Streckenangabe.
  Der laufende Satz gilt dann an der aktuellen Strecke als beendet, der nächste beginnt dort
  (`PlanProgress` mit `SectionMove`). Zurück (nur per Crown) beginnt der vorherige Satz (nach dem ersten
  Satz eines Abschnitts: der letzte Satz des Abschnitts davor) an der aktuellen Strecke von vorn; im allerersten
  Satz geschieht nichts. Die Wassersperre ist an, solange die Einheit läuft, und geht nach
  "Weiter", nach einem Wechsel und nach 20 Sekunden ohne Eingabe wieder an (`WaterLockControl`).
- **Tastenkombination:** *Crown und Seitentaste gleichzeitig zweimal kurz hintereinander* (Pause und
  gleich Weiter, höchstens 3 Sekunden) schaltet ebenfalls weiter (`SectionGesture`). Die Seitentaste
  allein sehen Apps einer Series oder SE nie (Apple sperrt sie), nur "pausiert" und "läuft". Ein Tippen
  auf "Pause" zählt nie als Geste.
- **Die Startseite zeigt, was zu tun ist:** Unter der Zeit (und dem Puls) stehen Nummer und Name des
  Abschnitts ("2/4 Hauptsatz"), das **Equipment** (z. B. "Pull Buoy, Paddles"), Wiederholung und Reste
  ("3 von 6 × 200 m · noch 150 m") und die **Kurzbeschreibung** (`cue`, zwei bis vier Wörter wie "Locker
  kraulen", eine Zeile; bei älteren Plänen die ersten Wörter der Anweisung). Zeit (40 pt), Puls und die
  **aktuelle Pace** (aus den letzten Bahnen, `CurrentPaceTracker`; "--" in der Pause am Beckenrand) stehen groß
  oben. Die Plan-Seite (rechts) zeigt die ganze Übung ausführlich, mit kleinem Knopf "Nächster Satz". Ganz unten steht eine Kontrollzeile: Schloss (gesperrt/entsperrt), die letzte Eingabe ("Krone:
  weiter bei 300 m", "Pause von der Uhr (Tasten)") und beim Drehen ein Balken. Sie ist bewusst da, um
  zu sehen, ob eine Eingabe die App erreicht.
- **Countdown und Pause:** Nach "Schwimmen" läuft **30 Sekunden Countdown** (große Zahl, die letzten drei Sekunden
  mit Impuls, am Ende startet die Aufzeichnung von selbst; "Abbrechen" und "Jetzt starten" gehen jederzeit).
  Bei jedem Wechsel zum **nächsten Satz** (automatisch nach der Strecke, per Crown oder Taste) läuft eine
  **Pause von 30 Sekunden**: Auf der Startseite steht grün "Pause 0:24", die letzten drei Sekunden und das Ende
  geben Impulse. Zurückgehen und das Planende starten keine Pause. Die Dauer steht in `TrainingTimers`
  (`CountdownTimer`).
- **Equipment:** Claude nennt je Abschnitt die Hilfsmittel (`pull_buoy`, `paddles`, `fins`, `snorkel`,
  `kickboard`, `ankle_band`, höchstens drei, siehe [plan-generation.md](docs/plan-generation.md)).
  Die Karte auf dem iPhone und die Watch zeigen "Mitnehmen: …" über dem Plan und das Equipment je
  Abschnitt. Pläne aus der Zeit davor haben keines (leere Liste).
- **Mein Ziel (Einstellungen):** Im Zahnrad stellst du Distanz (100 m bis 10 km), Zielzeit (Minuten) und Zieltag
  ein, Standard 3,8 km in 60 Minuten bis 04.07.2027. Das Ziel wird sofort gespeichert und bleibt, bis du es änderst
  (`UserDefaultsGoalStore`); "zurücksetzen" stellt den Standard wieder her. Eine Kombination mit unsinniger Zielpace
  (unter 0:40 oder über 10:00 pro 100 m) wird abgelehnt und nicht gespeichert. Das Ziel geht im Snapshot mit jeder
  Plananfrage mit und steht im Prompt (Abschnitt "Gesamtziel" mit Phase, Wochen bis zum Ziel und Realismus-Hinweis,
  siehe [plan-generation.md](docs/plan-generation.md)); Dashboard und Heute-Bildschirm zeigen das eingestellte Ziel.
  Nach einer Änderung entsteht beim nächsten Öffnen ein neuer Gesamtplan und die sieben Tage werden neu geplant; auf Heute nach unten ziehen holt einen neuen Tagesplan.
- **Mein Equipment (Einstellungen):** Im Zahnrad (iPhone) legst du fest, welche Hilfsmittel du hast (Pull Buoy,
  Paddles, Flossen, Schnorchel, Kickboard, Beinband). Ohne Auswahl gelten alle, mit der Auswahl plant Claude
  nur damit; was nicht an ist, entfernt die Sicherheitsschicht aus dem Plan und vermerkt es unter den
  Korrekturen. Die Auswahl geht bei Tages- und Wochenplan mit (`equipment`) und gehört zum Cache-Schlüssel:
  Ändert sie sich, gibt es beim nächsten Holen einen neuen Plan. Gespeichert wird sofort beim Umschalten.
- **Health-Rechte:** Die Watch fragt jetzt auch Schreibrechte an (Workout, Strecke, Züge, Puls,
  Energie), einmal beim Öffnen, damit der Dialog nicht erst am Beckenrand kommt.

### M7 – Definition of Done

- [x] Plan-Übertragung, Stand im Plan, Live-Werte und neue Texte per Unit-Test abgesichert
      (`PlanSyncCodecTests`, `PlanProgressTests`, `LiveSwimMetricsTests`, `PlanFormattingTests`)
- [x] iPhone- und Watch-Code kompilieren in der CI (`test`-Lane)
- [ ] **Auf der Watch (TestFlight):** Nach dem Öffnen der iPhone-App erscheint derselbe Plan auf der
      Watch; iPhone in Flugmodus, Watch-App neu öffnen: der Plan ist noch da
- [ ] **Auf der Watch:** "Vom iPhone holen" liefert den Plan, bei ausgeschaltetem iPhone kommt eine
      verständliche Meldung
- [ ] **Im Becken:** Beckenlänge wählen, starten, Wassersperre ist an; Bahnen, Strecke und Züge
      zählen mit; der Plan-Bildschirm springt nach dem Einschwimmen in den Hauptsatz
- [ ] **Im Becken:** Pause und Fortsetzen funktionieren, nach "Weiter" ist die Wassersperre wieder an,
      Beenden zeigt die Zusammenfassung
- [ ] **Trocken (zu Hause), Einheit starten:** Auf der Steuerseite "Nächster Satz" tippen: Auf der
      Startseite springt der Stand ("1 von 6 × 200 m" wird "2 von 6 …", nach dem letzten Satz "3/4 …"), die
      Kontrollzeile zeigt "Taste: nächster Satz bei 0 m"
- [ ] **Trocken:** Crown am Stück **nach oben** drehen: Der Balken füllt sich (gelb), nach 8 Einheiten
      (entsperrt) springt der Satz weiter. **Nach unten** drehen (Balken orange): zurück zum
      vorherigen Satz. Bei Wassersperre ist deutlich mehr Drehen nötig (14 Einheiten). Ein kurzes Anstoßen
      löst nichts aus. **Weiterdrehen springt nicht mehrfach:** Der nächste Wechsel geht erst, wenn die Crown
      kurz stillstand
- [ ] **Im Becken:** Der Satz wechselt von selbst, wenn seine Strecke geschwommen ist (Haptik)
- [ ] **Im Becken, gesperrt:** Crown + Seitentaste gleichzeitig drücken (Pause), gleich noch einmal
      (Weiter): Haptik, der Satz springt, die Wassersperre ist an. Länger als 3 Sekunden pausieren
      bleibt eine normale Pause
- [ ] **Im Becken:** Wassersperre ist beim Schwimmen an. Crown drehen entsperrt, eine weitere lange Drehung
      **nach oben** springt zum nächsten, **nach unten** zum vorherigen Satz (Haptik, der
      Plan-Bildschirm zeigt ihn), danach ist die Wassersperre wieder an. Falls die Richtung verkehrt
      ist, melde dich (`CrownRotationTracker.upIsPositive`)
- [ ] **Ziel (iPhone):** Einstellungen, "Mein Ziel": Distanz auf 1.500 m, Zeit auf 28 min stellen, App neu starten:
      Die Werte sind noch da, im Dashboard und auf Heute steht das neue Ziel, der neue Plan nennt 1.500 m. Ein
      unmögliches Ziel (z. B. 10 km in 10 min) zeigt eine rote Meldung
- [ ] **Watch, Startseite:** Zeit und Puls sind groß, darunter der Plan und die Strecke
- [ ] **Watch, Countdown:** "Schwimmen" tippen: 30 Sekunden Countdown, Impulse bei 3, 2, 1 und zum Start, dann läuft
      die Aufzeichnung (Wassersperre an). "Abbrechen" bringt zurück zum Plan
- [ ] **Watch, Pause:** Beim Wechsel zum nächsten Satz erscheint "Pause 0:30" und zählt herunter, am Ende ein Impuls
- [ ] **iPhone, Tab Plan:** Reihenfolge: Woche, Tage, Planen, ganz unten der Gesamtplan
- [ ] **Equipment (iPhone):** Einstellungen, "Mein Equipment": Nur Pull Buoy und Kickboard an, auf Heute nach
      unten ziehen: Der neue Plan nennt nur diese beiden (oder gar keins). Alles aus: Plan ohne Hilfsmittel
      (Server aktualisiert, `deploy.sh`)
- [ ] **Danach:** Das Workout steht in der Fitness-App als Beckenschwimmen mit Bahnen; die
      iPhone-App zeigt es unter "Bisherige Einheiten"

### Unit-Tests (Package)

```bash
cd Packages/SwimInstructorCore && swift test
```

`SwimWorkoutRepositoryTests` deckt ab: Pace-Berechnung, Verhalten ohne
Distanz (kein Pace/SWOLF), Bahnenzählung aus `HKWorkoutEvent`s (nur `.lap`,
nicht `.pause`), `nil` bei fehlenden Lap-Events, SWOLF-Näherung.

## M8 – Dashboard & Verlauf (nur iPhone)

Die iPhone-App hat jetzt drei Tabs: **Heute** (Plan, wie bisher), **Dashboard** und **Verlauf**. Die Watch
bleibt bewusst bei Tagesplan und Live-Aufzeichnung, ein verkleinertes Dashboard dort bringt im Becken nichts.

- **Dashboard** (Swift Charts): Weg zum Ziel (Tage, längste Einheit gegen 3.800 m, Pace gegen Zielpace und
  Trend), **Wochenumfang** der letzten 8 Kalenderwochen (Montag bis Sonntag, die laufende Woche blasser) und
  **Pace pro Einheit** mit der Zielpace als gestrichelter grüner Linie (schon ab einer Einheit). Einheiten unter 200 m und ohne Strecke
  fehlen im Pace-Diagramm, weil sie nichts über das Tempo sagen. Die Pace enthält wie überall die Pausen
  (Health meldet die gesamte Dauer).
- **Verlauf: geplant gegen tatsächlich.** Die App speichert ab jetzt jeden Tagesplan auf dem Gerät
  (`Application Support/SwimInstructor/plan-history.json`, höchstens 120 Tage) und legt ihn neben die
  Einheiten aus Health. Pro Tag zählt der **erste** Plan des Tages: Ein späterer Plan entsteht oft erst nach
  dem Training und wäre ein schiefer Maßstab. Fallback-Pläne werden nicht gespeichert.
  Rückwirkend gibt es keinen Verlauf: Der Server kennt nur den jeweils letzten Plan, ältere Tage haben
  keinen Plan zum Vergleichen.
- **Bewertung eines Tages:** *umgesetzt* (75 bis 125 % des geplanten Umfangs), *kürzer* (unter 75 %),
  *länger* (über 125 %), *nicht geschwommen* (Training geplant, nichts geschwommen), *Ruhetag eingehalten*,
  *trotz Ruhetag geschwommen* und *offen* (heute, der Tag ist noch nicht vorbei). Eine Einheit ohne
  Streckenangabe zählt als geschwommen, ihr Umfang lässt sich aber nicht vergleichen.
- Oben im Verlauf steht die Zusammenfassung der letzten 4 Wochen ("5 von 6 geplanten Einheiten
  geschwommen", "2 von 3 Ruhetagen eingehalten"). Dazu ein Balkendiagramm geplant gegen geschwommen für die
  letzten 14 Tage.
- Die Tabs Dashboard und Verlauf lesen beim Öffnen nur Health neu. Einen neuen Plan holt nur der Tab
  "Heute" (das kann einen Claude-Aufruf kosten).

**Keine UI-Tests.** Die Rechenlogik (Wochenumfang, Pace, Plan-Vergleich, Verlauf speichern) liegt komplett im
Package und ist per Unit-Test abgesichert (`TrainingStatisticsTests`, `PlanAdherenceTests`,
`PlanHistoryTests`, `TodayPlanLoaderTests`). Die Bildschirme selbst sind dünn und werden in der CI
mitkompiliert. Ein XCUITest-Target bräuchte einen Simulator-Lauf in der CI und stabile Testdaten aus Health,
das lohnt sich erst, wenn die Oberfläche sich beruhigt hat (M11).

### M8 – Definition of Done

- [x] Wochenumfang, Pace je Einheit, Plan-Vergleich und Verlaufsspeicher per Unit-Test abgesichert
- [x] iPhone-Code kompiliert in der CI (`test`-Lane)
- [ ] **Auf dem iPhone:** Tab "Dashboard" zeigt Ziel, Wochenumfang (8 Wochen) und Pace-Verlauf. Die Zahlen
      stimmen mit der Fitness-App überein (Wochensumme einer Woche nachrechnen)
- [ ] **Auf dem iPhone:** Tab "Verlauf" ist am ersten Tag leer mit Erklärung, nach dem ersten Plan steht
      der heutige Tag als "offen", nach dem Schwimmen als "umgesetzt" (oder "kürzer"/"länger")
- [ ] **Auf dem iPhone:** Nach ein paar Tagen sind Zusammenfassung und Balkendiagramm sinnvoll, ein
      Ruhetag mit Schwimmen erscheint als "trotz Ruhetag geschwommen"
- [ ] **Auf dem iPhone:** Flugmodus: Dashboard und Verlauf zeigen weiter ihre Daten (Health ist lokal)

## Gesamtplan und Plan der nächsten sieben Tage (Tab "Plan")

Die iPhone-App hat vier Tabs: **Heute**, **Plan**, **Dashboard**, **Verlauf**. Geplant wird in drei Stufen:

1. **Gesamtplan bis zum Ziel** (`POST /v1/plan/macro`): Claude plant **jede Woche von heute bis zum Zieltag** (bei
   dir 04.07.2027, einstellbar unter "Mein Ziel") als Gerüst: Wochenumfang, Zahl der Einheiten, Entlastungswochen
   und ein Schwerpunkt. Die **Phase** (Aufbau, zielspezifisch, Zuspitzen, Zielwoche, danach Erhalten) rechnet der
   Code aus dem Abstand zum Zieltag. Die Sicherheitsschicht hält ihn ein: erste Woche in den Grenzen von heute,
   danach höchstens etwa 10 % mehr als die Woche davor, Entlastungswochen deutlich darunter, beim Zuspitzen und in
   der Zielwoche sinkt der Umfang. Jede Einheit hat mindestens 400 m, jeder Satz ist ein Vielfaches von 50 m (passt für ein 25-m- und ein 50-m-Becken). Er entsteht beim ersten Start, bei einer Zieländerung und wenn er abläuft
   (höchstens ein Versuch pro Tag), und lässt sich im Tab Plan jederzeit neu berechnen.
2. **Die nächsten 7 Tage** (`POST /v1/plan/week` ohne `week_start`): **Jeden Tag beim ersten Öffnen der App** plant
   Claude die sieben Tage ab heute neu und stimmt sie ab auf deinen **Zustand** (Erholung), deinen
   **Trainingsstand** (Snapshot, Pace, längste Einheit), das **Training der Vorwoche** (die letzten sieben Tage
   davor) und die **Vorgabe des Gesamtplans** für diese Wochen. Er schreibt die Vorgabe nicht stur ab, sondern
   justiert fein: War die Vorwoche leichter oder härter, geht er mit dem Umfang nach unten oder oben (in den
   Grenzen). Schlägt das fehl (kein Netz, Budget), versucht es das nächste Öffnen wieder.
3. **Heute** zeigt den **Tagesplan**: die Einheit für heute mit Abschnitten, Equipment und Kurzbeschreibung für die
   Uhr (`POST /v1/plan/today`), passend zur Vorgabe der sieben Tage (`day_plan`) und zum Zustand des Tages.

Ablauf beim ersten Öffnen am Tag: Health lesen, Gesamtplan sicherstellen, die sieben Tage anpassen (Heute zeigt
"Claude passt deinen Plan für die nächsten Tage an …"), dann der Tagesplan. Das dauert zusammen etwa 30 bis 60
Sekunden, danach ist alles gespeichert und das Öffnen geht sofort. Ziehen auf Heute holt nur einen **neuen
Tagesplan**, "Nächste 7 Tage neu planen" im Tab Plan holt die Tage neu.

- **Anpassen** (Tippen auf einen Tag, ab heute): Umfang ändern (0 m macht den Tag zum Ruhetag), **"Keine Zeit an
  diesem Tag"** (wird Ruhetag und bleibt bei jeder neuen Planung einer; mit "Doch wieder Zeit" geht das Training
  zurück), "Als Ruhetag setzen" und **mit einem anderen Tag tauschen**. Eine **verpasste** oder zu kurze Einheit
  lässt sich auf einen freien Ruhetag verschieben. Andere Änderungen von Hand gelten bis zur nächsten Anpassung der
  sieben Tage (die Planung kennt "Keine Zeit", die Vorwoche und den Gesamtplan, nicht jeden Handgriff).
- **Sicherheitsschicht auch für die Tage:** Umfang der sieben Tage, Einheitenlänge, höchstens zwei harte Tage und
  nie an zwei Tagen hintereinander, höchstens fünf Einheiten, mindestens ein Ruhetag, die Grenzen für heute. Die
  Vorwoche schmälert das Budget der nächsten sieben Tage nicht, sie steht nur im Prompt. Korrekturen stehen unter
  "Zur Sicherheit angepasst".
- **Status je Tag** aus Health: umgesetzt (75 bis 125 % des Umfangs), kürzer, länger, nicht geschwommen,
  Ruhetag eingehalten, trotz Ruhetag geschwommen, keine Zeit. Die Pfeile oben wechseln zwischen den Kalenderwochen
  (die sieben Tage können über zwei Wochen laufen); geplant wird immer ab heute.
- **Dashboard und Verlauf:** Die Statistik (Woche gegen Plan, letzte 7 Tage, Pace, Erholung, Tage bis zum Ziel) steht
  im Dashboard, die Liste der letzten Einheiten im Verlauf. Heute zeigt nur den Tag.
- **Speicherung:** Der Server speichert weder Gesamtplan noch Tage. Die App hält sie samt deinen Änderungen auf dem
  Gerät (`Application Support/SwimInstructor/macro-plan.json` und `week-plans.json`, die letzten 8 Kalenderwochen).
  Scheitert Claude, bleibt der bisherige Plan, die Meldung nennt den Grund.
- **Kosten:** Ein normaler Tag mit erstem Öffnen kostet zwei Claude-Aufrufe (sieben Tage und Tagesplan, zusammen
  rund 10 Cent), der Gesamtplan zusätzlich einen (größer, er gilt dafür für Wochen). Alles zählt gegen dasselbe
  Budget (5 pro Stunde, 20 pro Tag).

Logik im Package, per Unit-Test abgesichert: `MacroPlan`/`MacroPlanLoader` (Gesamtplan), `WeekPlan`,
`WeekCalendar`, `WeekPlanEditor` (Änderungen, Zusammenführen), `WeekProgressCalculator` (Status je Tag),
`WeekPlanLoader` (Ablauf, einmal am Tag), `TodayPlanLoader` (Vorbereitung vor dem Tagesplan), `PlanAPIClient`.
Die Bildschirme (`WeekView`, `TodayView`) werden in der CI mitkompiliert.

### Plan – Prüfpunkte (manuell)

- [ ] **Server aktualisiert** (`deploy.sh`), sonst gibt es `/v1/plan/macro` und den rollenden Plan nicht
- [ ] **Erster Start danach:** Heute zeigt "Claude passt deinen Plan für die nächsten Tage an …", dann der
      Tagesplan. Im Tab Plan steht oben der **Gesamtplan** (Ziel, Wochen bis dahin, diese Woche, "Alle Wochen" bis
      zum 04.07.2027 mit Phasen) und darunter sieben Tage ab heute
- [ ] **Gesamtplan plausibel:** Der Umfang steigt langsam (etwa 10 % pro Woche), etwa jede vierte Woche ist
      Entlastung, die letzten zwei Wochen sinken, die Zielwoche ist kurz
- [ ] **Zweites Öffnen am selben Tag:** kein Warten, kein neuer Wochenplan. **Am nächsten Tag:** Beim ersten Öffnen
      werden die sieben Tage neu angepasst (die Begründung nennt Zustand, Vorwoche und Gesamtplan)
- [ ] **Anpassen:** Umfang ändern, "Keine Zeit" an einem Tag, zwei Tage tauschen. "Nächste 7 Tage neu planen": Der
      Tag ohne Zeit bleibt Ruhetag
- [ ] **Ziel ändern** (Einstellungen, "Mein Ziel"): Beim nächsten Öffnen entsteht ein neuer Gesamtplan zum neuen Ziel
- [ ] **Dashboard** zeigt die Statistik, **Verlauf** die letzten Einheiten, **Heute** nur den Tag

## Triathlon-Umbau (Schwimmen, Rad, Laufen)

Die App wird schrittweise zur Triathlon-App umgebaut (Schritte T0 bis T7, Plan im Projekt-Chat). Nach jedem
Schritt bleibt sie fürs Schwimmen voll nutzbar.

### T0 – Fundament: Sport-Module und Verträge

- **Sport-Module:** Jede Sportart ist ein Modul, das sich in einer Registry anmeldet: `SportModule` und
  `SportRegistry` im Package (`Sources/SwimInstructorCore/Sports/`), `SportDefinition` und `SPORTS` im Backend
  (`backend/src/sports/`). Eine Sportart hat eine Kennung (`swim`, `bike`, `run`), einen deutschen Namen und die
  Maße (Strecke, Dauer, Wiederholungen) und Ziele (Pace, Pulszone, Leistung, …), nach denen ihre Schritte geplant
  werden. Eine neue Sportart ist ein neues Modul, keine Änderung quer durch den Code.
- **Verträge zwischen App und Server** (`contracts/`, siehe [`contracts/README.md`](contracts/README.md)): Sportarten,
  Snapshot, Plan-Antworten und die Dateien, die die App heute auf dem Gerät speichert. Swift-Tests
  (`ContractTests`) und Jest-Tests (`test/contracts.test.ts`) lesen dieselben Dateien; das Backend erzeugt die
  Antworten dabei über die echten Routen.
- **Konformitätstests:** Jedes Modul, dazu die erfundene Test-Sportart *Rudern* (plant nach Schlagzahl, was keine
  echte Sportart kann), läuft durch dieselben Prüfungen (`SportModuleConformanceTests`, `test/sports/conformance.test.ts`).
- **Lint:** Außerhalb der Module darf niemand nach einer bestimmten Sportart verzweigen (`SportLintTests`,
  `test/sports/lint.test.ts`).
- **Coverage-Schwelle 90 %** für die Sport-Module, in der CI erzwungen (Fastlane `check_sports_coverage`, Jest
  `coverageThreshold`).

### T0 – Definition of Done

- [x] Swift und Jest prüfen dieselben Vertragsdateien; eine absichtlich entfernte Antwort-Eigenschaft macht den
      Test rot (von Hand ausprobiert)
- [x] Die Test-Sportart Rudern besteht die Konformitätstests auf beiden Seiten
- [x] Alle bisherigen Tests laufen unverändert
- [x] Nichts für dich zu prüfen: An der App ändert sich sichtbar nichts

### T1 – Sportart im Datenmodell und Health

- **`Workout` mit Sportart:** Eine Einheit hat eine Sportart (`SportID`), Dauer, Strecke, Puls, Energie und offene
  Zusatzwerte (`WorkoutMetric`: Bahnen, Züge, Watt, Trittfrequenz, Höhenmeter). Was eine Sportart zusätzlich misst,
  bringt ihr Modul mit.
- **Health je Modul:** Jedes Modul nennt seine Workout-Arten und Messwerte (`SportHealthMapping`): Schwimmen mit
  Strecke und Zügen, Rad mit Strecke, Watt und Trittfrequenz (falls vorhanden), Laufen mit Strecke und Laufleistung.
  `HealthKitWorkoutRepository` liest damit alle Sportarten der Registry, ohne selbst eine zu kennen. Die App fragt
  die neuen Health-Typen beim nächsten Start einmal zusätzlich an.
- **Duplikate je Sportart:** `WorkoutDeduplicator` bereinigt doppelte Einheiten nur innerhalb einer Sportart; Rad
  und Lauf eines Koppeltrainings bleiben beide stehen.
- **Trainingslast je Einheit:** `TrainingLoadCalculator` rechnet Banisters TRIMP, wenn Ruhe- und Maximalpuls
  bekannt sind, sonst Minuten. Der Faktor des Moduls gleicht die Sportarten an (Rad 0,8, Schwimmen und Laufen 1,0).
  Der Plan nutzt die Last ab Snapshot v2 (T2).
- **Verlauf:** "Letzte Einheiten" zeigt alle Sportarten mit Symbol und Namen. Snapshot, Dashboard und Plan
  rechnen bis T2 weiter nur mit dem Schwimmen; Einheiten ohne Sportart gelten als Schwimmen.

### T1 – Definition of Done

- [x] Konformitätstests prüfen für jedes Modul (auch Rudern): Health-Typen existieren und passen zur Einheit, die
      Workout-Art findet das Modul, ein Health-Workout wird eine Einheit dieser Sportart, Last wächst mit der Dauer
- [x] Der Schwimm-Snapshot ist mit Rad- und Laufeinheiten im Health genau derselbe wie vorher (`SnapshotBuilderTests`)
- [ ] **Für dich auf dem iPhone:** Nach dem Update fragt Health nach den neuen Typen (Radstrecke, Lauf-/Gehstrecke,
      Leistung, Trittfrequenz, Energie); erlauben. Ein Lauf und eine Radfahrt aus der Fitness- oder Trainings-App
      erscheinen danach unter Verlauf → Letzte Einheiten mit richtigem Symbol, Strecke und Dauer. Die
      Schwimm-Zahlen im Dashboard bleiben gleich.

### T2 – Ziel, Schwerpunkte und Snapshot v2

- **Gesamtziel (`TrainingGoal`):** Disziplinen mit Strecke und optional Zielzeit, Zieltag, Trainingstage, Stunden pro
  Woche und Schwerpunkt je Sportart (zusammen 100 %). Vorlagen für Triathlon Sprint, Olympisch, 70.3 und
  Langdistanz, 3,8 km Schwimmen, 10 km, Halbmarathon, Marathon und 100 km Rad (`GoalTemplate`); danach ist alles frei
  einstellbar. Die Prüfung lehnt Unsinn ab: Schwerpunkte ungleich 100 %, Zieltag nicht in der Zukunft, Zieltempo
  außerhalb dessen, was das Sport-Modul für plausibel hält (z. B. 10 km Laufen in 10 Minuten).
- **Ziel-Assistent:** Einstellungen → Mein Ziel. Vorlage wählen, Disziplinen an- und ausschalten, Strecken und
  Zeiten eintragen, Schwerpunkte per Regler (die anderen passen sich an), Zieltag, Trainingstage und -zeit. Ein
  gültiges Ziel wird sofort gespeichert. Das bisherige Schwimmziel zieht beim ersten Start automatisch um.
- **Snapshot v2:** zusätzlich das Gesamtziel, Werte je Sportart und die Gesamtlast (siehe
  [`docs/AthleteStateSnapshot.md`](docs/AthleteStateSnapshot.md)). Der Server nimmt v1 und v2 an; mit v2 erfährt
  Claude, was in Rad und Laufen los ist, und plant das Schwimmen entsprechend. Rad- und Laufeinheiten plant er erst ab
  T3. Läuft auf dem Server noch die alte Version, schickt die App automatisch v1, der Plan kommt wie bisher.

### T2 – Definition of Done

- [x] Snapshot-Berechnung je Sportart und gemischt, Werte von Hand nachgerechnet (`MultiSportStateCalculatorTests`)
- [x] Schema v2 in `contracts/` dokumentiert und von App und Server geprüft
- [x] Ein v1-Snapshot liefert im Backend Zeichen für Zeichen denselben Prompt wie vorher (Golden-Test über alle
      v1-Szenarien, Tages-, Wochen- und Gesamtplan)
- [x] Die Zielprüfung lehnt Unsinn ab (Schwerpunkte ungleich 100 %, Zieltag nicht in der Zukunft, unplausibles Tempo)
- [ ] **Für dich:** Server mit `deploy.sh` aktualisieren (sonst bleibt es bei v1, siehe oben). Dann auf dem iPhone
      Einstellungen → Mein Ziel: z. B. "Triathlon Olympisch" wählen, Schwimmen auf 40 % ziehen, App ganz beenden
      und neu starten: Ziel und Schwerpunkte sind noch da. Auf Heute nach unten ziehen: Der Plan erwähnt Rad und
      Laufen als Belastung.

### T2b – Leistungsprofil und Zonen

- **Leistungsprofil (`PerformanceProfile`):** Maximal- und Ruhepuls für alle Sportarten, dazu je Sportart ihre
  Werte: CSS-Pace beim Schwimmen, Schwellenpuls und FTP beim Rad, Schwellenpuls und -tempo beim Laufen. Jeder Wert
  hat eine Herkunft (Test, eigene Eingabe, aus Health geschätzt, Faustformel) und ein Datum; bestätigte Werte
  behalten einen Verlauf. Bestätigtes geht vor Geschätztem, Geschätztes vor Faustformel. Ein höherer gemessener
  Maximalpuls löst den alten ab.
- **Startwerte ohne Test:** Maximalpuls aus dem höchsten Puls der letzten sechs Monate (sonst 208 − 0,7 × Alter),
  Ruhepuls aus den letzten Tagen, CSS aus der schnellsten Schwimmeinheit, Schwellenpuls als Anteil des Maximalpulses,
  Schwellentempo aus Puls und Tempo der Läufe (Details in [`docs/AthleteStateSnapshot.md`](docs/AthleteStateSnapshot.md)).
  Für die Faustformel liest die App einmalig das Geburtsdatum aus Health.
- **Zonen je Modul (`ZoneScheme`):** Puls nach Friel, Rad-Leistung nach Coggan, Pace als Anteil der
  Schwellengeschwindigkeit, Schwimm-Puls aus dem Maximalpuls. Die App rechnet sie und schickt sie mit Herkunft im
  Snapshot v2 mit (`performance`, optional); der Server prüft die Werte gegen dieselben Grenzen.
- **Leistungstests je Modul:** CSS-Test 400/200 m und 1000-m-Test (Schwimmen), 30-Minuten-Test (Rad und Laufen),
  lockerer Einstiegstest (Laufen). Hier steht erst, was ein Test ermittelt; eingeplant werden sie ab T3, auf der Watch
  laufen sie ab T5, das Ergebnis bestätigst du ab T4.
- Mit Ruhe- und Maximalpuls rechnet die Last jetzt nach TRIMP statt nach Minuten.

### T2b – Definition of Done

- [x] Zonen und Schätzungen von Hand nachgerechnet (`TrainingZonesTests`, `PerformanceEstimatorTests`)
- [x] Die Test-Sportart Rudern hat ein eigenes Profil mit eigenem Wert, eigenem Test und vier Zonen
- [x] Ein Snapshot ohne Profil bleibt gültig; App und Server prüfen `contracts/wire/snapshot-v2-profile.json`, und
      die App rechnet aus derselben Lage genau dieses Profil
- [ ] **Für dich:** nichts Neues zu prüfen. Beim nächsten Start fragt Health einmal nach dem Geburtsdatum.

## Projektstruktur

```
App/                                # iOS-App
  SwimInstructorApp.swift            # App-Einstiegspunkt, verdrahtet Health, Einstellungen, Plan-Loader
  PhonePlanSync.swift                # Schickt den Tagesplan an die Watch (M7)
  RootView.swift                     # Tabs: Heute, Dashboard, Verlauf (M8)
  TodayView.swift                    # Heute: Eintrag aus dem Plan, Einheit für heute, Wunsch
  WeekView.swift                     # Plan: Gesamtplan, nächste 7 Tage, Status, Anpassen, Planen
  StatsViews.swift                   # Statistik-Zeilen (Dashboard), Einheiten-Zeile aller Sportarten (Verlauf)
  DashboardView.swift                # Ziel, Wochenumfang, Pace-Verlauf (Swift Charts, M8)
  HistoryView.swift                  # Verlauf geplant gegen tatsächlich (M8)
  PlanCardView.swift                 # Darstellung des Tagesplans
  SettingsView.swift                 # Server-Adresse, Token, Verbindung testen
  Info.plist
  SwimInstructor.entitlements        # HealthKit-Capability
WatchApp/                           # watchOS Companion-App
  SwimInstructorWatchApp.swift       # App-Einstiegspunkt, wechselt zwischen Plan, Einheit, Zusammenfassung
  WatchTodayView.swift               # Start, Beckenlänge, Tagesplan (M7)
  WatchWorkoutView.swift             # Laufende Einheit und Zusammenfassung (M7)
  WatchPlanStore.swift               # Empfängt und speichert den Plan vom iPhone (M7)
  SwimWorkoutManager.swift           # HKWorkoutSession + Live-Werte, speichert in Health (M7)
  Info.plist                         # inkl. WKCompanionAppBundleIdentifier, Hintergrundmodus Workout
  SwimInstructorWatch.entitlements   # HealthKit-Capability
Packages/SwimInstructorCore/        # Von iOS + Watch geteilte Logik
  Sources/SwimInstructorCore/
    HealthKitManager.swift           # Autorisierung
    SwimWorkout.swift                # Domain-Modell (Pace, SWOLF-Näherung)
    SwimWorkoutRepository.swift      # Liest Workouts aus HealthKit + Mapping
    SwimWorkoutDeduplicator.swift    # Entfernt doppelte Einheiten aus mehreren Quellen
    AthleteGoal.swift                # Ziel (Standard 3,8 km < 60 min bis 04.07.2027), Prüfung der Eingabe
    GoalStore.swift                  # eingestelltes Ziel dauerhaft speichern (Einstellungen)
    DailyVitals.swift                # Tageswerte Ruhepuls/HRV/Schlaf
    AthleteStateSnapshot.swift       # Snapshot-Modell + JSON-Encoder (Schema v1)
    AthleteStateCalculator.swift     # Berechnung Workouts/Vitals -> Snapshot
    DailyVitalsRepository.swift      # Liest Ruhepuls, HRV, Schlaf aus HealthKit (M6)
    DailyVitalsAggregator.swift      # Schlaf pro Nacht, Tageswerte zusammenführen (M6)
    SnapshotBuilder.swift            # Health -> Snapshot (M6)
    TrainingPlan.swift               # Plan-Antwort des Servers (M6)
    PlanAPIClient.swift              # POST /v1/plan/today, GET /v1/status (M6)
    PlanCache.swift                  # Letzter Plan offline (M6)
    BackendSettings.swift            # Server-Adresse + Token im Schlüsselbund (M6)
    PlanFormatting.swift             # Texte für die Plananzeige (M6)
    TodayPlanLoader.swift            # Ablauf des Heute-Bildschirms (M6)
    PlanSync.swift                   # Format der Plan-Übertragung iPhone -> Watch (M7)
    PlanProgress.swift               # Stand im Plan nach geschwommenen Metern (M7)
    LiveSwimMetrics.swift            # Live-Werte und Beckenlänge der Watch (M7)
    TrainingStatistics.swift         # Wochenumfang und Pace je Einheit für das Dashboard (M8)
    PlanHistory.swift                # Gespeicherte Tagespläne der letzten Wochen (M8)
    PlanAdherence.swift              # Geplant gegen geschwommen, Zusammenfassung (M8)
    WeekPlan.swift                   # Wochenplan: Tage, Vorgabe für den Tagesplan
    MacroPlan.swift                  # Gesamtplan bis zum Zieltag (Wochen, Phasen), Speicher
    MacroPlanLoader.swift            # Gesamtplan holen/erneuern (einmal am Tag je Ziel)
    WeekCalendar.swift               # Wochen von Montag bis Sonntag, Kalendertage
    WeekPlanEditor.swift             # Änderungen des Athleten, Zusammenführen nach dem Neuplanen
    WeekProgress.swift               # Status je Tag aus Health gegen den Plan
    WeekPlanStore.swift              # Wochenpläne auf dem Gerät
    WeekPlanLoader.swift             # Ablauf des Wochen-Tabs
  Tests/SwimInstructorCoreTests/
    HealthKitManagerTests.swift
    SwimWorkoutRepositoryTests.swift
    SwimWorkoutDeduplicatorTests.swift
    AthleteStateCalculatorTests.swift  # 5 Szenarien + Randfaelle + Schema
backend/                            # Node/TypeScript-Server (Proxy fuer Claude, ab M5)
  src/                               # app.ts, auth.ts, config.ts, logger.ts, server.ts
  src/plan/                          # Plan-Erzeugung (M5): Claude-Aufruf, Sicherheitsschicht, Fallback
  scenarios/                         # die 5 Snapshots aus M3 (Eingabe für npm run eval:scenarios)
  scripts/eval-scenarios.ts          # echter Lauf gegen die Claude-API zur manuellen Bewertung
  test/                              # Jest + supertest
  Dockerfile, compose.yaml           # Container-Image und Start auf dem Server
  deploy/                            # Caddyfile-Vorlage, deploy.sh
contracts/                           # Verträge App <-> Server, von Swift- und Jest-Tests gelesen
docs/
  AthleteStateSnapshot.md            # JSON-Schema, Definitionen, Schwellenwerte
  backend-deploy.md                  # Server-Einrichtung Schritt fuer Schritt
  plan-generation.md                 # /v1/plan/today: Ablauf, Regeln, Kosten, Konfiguration
  Package.swift
project.yml                          # XcodeGen-Konfiguration (beide Targets + Package)
fastlane/
  Appfile                             # Bundle-ID, Apple-ID, Team-ID
  Matchfile                           # Zertifikats-Repo-Konfiguration (iOS + Watch Bundle-IDs)
  Fastfile                            # Lanes: test, beta (TestFlight-Upload, inkl. Watch-App)
Gemfile                               # Ruby-Abhängigkeit: fastlane
.github/workflows/
  ios-ci.yml                          # Test- und TestFlight-Deploy-Pipeline
  backend-ci.yml                      # Backend: Typecheck, Build, Tests, npm audit, Docker-Smoke-Test
```

## Roadmap

M1 bis M8 sind umgesetzt (die manuellen Prüfungen stehen jeweils in der Definition of Done des
Meilensteins). Offen:

- **M9 – Automatisierung: bewusst gestrichen.** Eine Erinnerung zur Uhrzeit und ein Plan im Hintergrund
  brächten wenig: Bei gesperrtem iPhone kann die App Health nicht lesen (Apple schützt die Daten), und
  wann iOS Hintergrundläufe erlaubt, lässt sich nicht erzwingen. Stattdessen entsteht der Plan, **wenn du
  die App morgens öffnest** (dauert rund 15 Sekunden, danach liegt er auch auf der Watch). Das geschieht
  nur beim ersten Öffnen des Tages. **Ziehen zum Aktualisieren** holt dagegen immer einen neuen Plan von
  Claude, auch bei unverändertem Zustand (rund 4 Cent, der Server begrenzt auf 5 Pläne pro Stunde und
  20 pro Tag).
  Der verworfene Entwurf steht in PR #25.
- **Gesamtplan und Plan der nächsten sieben Tage:** umgesetzt (Abschnitt "Gesamtplan und Plan der nächsten sieben Tage"), Prüfpunkte stehen dort.
- **M10 – Realer Betatest:** Mehrere Wochen im echten Training, Planqualität und Zahlen gegenprüfen.
- **M11 – Feinschliff:** Fehlermeldungen, Barrierefreiheit, UI-Tests, Übungslexikon statt wiederholter
  Erklärungen im Plan.
