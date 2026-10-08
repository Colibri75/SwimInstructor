# Peaksmith

**Namen:** Die App heißt **Peaksmith** (Anzeigename unter dem Symbol auf iPhone und Watch, in den Health-Hinweisen und im
Onboarding; `APP_DISPLAY_NAME` in `project.yml`). Alles Technische heißt weiter **SwimInstructor**, weil sonst
TestFlight, die Health-Freigaben und die gespeicherten Daten verloren gingen:

| Peaksmith | SwimInstructor (bleibt) |
|---|---|
| Name der App und in allen Texten | Repo, Xcode-Targets und Scheme, Bundle-IDs (`com.kellner.SwimInstructor`), Swift-Package `SwimInstructorCore`, Ordner auf dem Gerät (`Application Support/SwimInstructor/`), Server (Hostname, Container, `/etc/swiminstructor/`) |

iOS- und watchOS-App für das Training im Triathlon: Sie liest Einheiten und Vitaldaten aus Apple Health, Claude plant
daraus über einen eigenen Server Gesamtplan, die nächsten 14 Tage und den Tag, und die Watch führt durch die Einheit.
Jede Sportart ist ein **Modul**; was nicht zu einer Sportart gehört, macht der Kern für alle gleich.

Der Code wird auf einem beliebigen Rechner (z. B. Windows) bearbeitet. Bauen, Signieren und Verteilen läuft über GitHub
Actions, Fastlane und TestFlight, ein eigener Mac ist nicht nötig ([CI/CD-Setup](#cicd-setup--testflight)).

## Sportarten

| Sportart | Kennung | Umfang im Plan | Ziele der Schritte | Leistungstests | Watch | Modul App / Server |
|---|---|---|---|---|---|---|
| Schwimmen | `swim` | Meter | Pace pro 100 m, Pulszone, gefühlte Anstrengung | CSS-Test 400/200 m, 1000-m-Test | Becken (mit Bahnlänge), Freiwasser | [`SwimModule.swift`](Packages/SwimInstructorCore/Sources/SwimInstructorCore/Sports/Modules/SwimModule.swift) / [`swim.ts`](backend/src/sports/modules/swim.ts) |
| Radfahren | `bike` | Minuten | Watt, Pulszone, Tempo, Trittfrequenz, gefühlte Anstrengung | 30-Minuten-Test | draußen (GPS), drinnen | [`BikeModule.swift`](Packages/SwimInstructorCore/Sources/SwimInstructorCore/Sports/Modules/BikeModule.swift) / [`bike.ts`](backend/src/sports/modules/bike.ts) |
| Laufen | `run` | Minuten | Pace pro km, Pulszone, Schrittfrequenz, gefühlte Anstrengung | 30-Minuten-Test, Einstiegstest locker | draußen (GPS), drinnen | [`RunModule.swift`](Packages/SwimInstructorCore/Sources/SwimInstructorCore/Sports/Modules/RunModule.swift) / [`run.ts`](backend/src/sports/modules/run.ts) |

Eine weitere Sportart: [Neue Sportart hinzufügen](docs/neue-sportart.md) (acht Dateien, nichts sonst).

### Was ein Modul festlegt

| Bereich | App (`SportModule`) | Server (`SportDefinition`) |
|---|---|---|
| Vertrag | Kennung, Name, Maße, Ziele, Zieltempo, Lastfaktor, Plan-Einheit, Trainingstempo, Leistungswerte und Tests, wie in [`contracts/sports.json`](contracts/sports.json) | dasselbe |
| Health | Workout-Arten, Strecke, weitere Messwerte (`health`) | |
| Belastung | `loadFactor` für die Trainingslast (Session-RPE: Minuten × Anstrengung aus Health oder Puls) | `loadFactor` |
| Leistungsprofil | Werte, Tests mit Eingabe und Auswertung, Zonen, Schätzung ohne Test | Werte und Tests |
| Planung | | Grenzen (`limits`), Schrittraster, erlaubte Zielbereiche, Testeinheiten, Regeln für Claude (`promptRules`) |
| Watch | Orte, Live-Werte, Glättung des Tempos (`recording`) | |
| Statistik | Kennzahlen der Kacheln (`statistics`, sonst aus Health abgeleitet) | |

### Was der Kern für alle Sportarten macht

- **Ziel** mit Disziplinen, Zieltag, Stunden pro Woche und Schwerpunkten je Sportart (`TrainingGoal`, Vorlagen in
  `GoalTemplates`).
- **Zustand** aus Health: Snapshot v2 mit Werten je Sportart, Gesamtlast und Leistungsprofil
  ([`docs/AthleteStateSnapshot.md`](docs/AthleteStateSnapshot.md)).
- **Planung** auf dem Server: Gesamtplan bis zum Ziel, die nächsten 14 Tage, Tagesplan, Überarbeitung nach Feedback; die
  Sicherheitsschicht hält die Grenzen der Module und die übergreifenden Regeln ein
  ([`docs/multisport-planning.md`](docs/multisport-planning.md)).
- **Plan reagiert auf echtes Training:** Nach jeder Einheit fragt Heute "Wie war's?" (Anstrengung, Beschwerden mit
  Stelle). Bei deutlichen oder starken Beschwerden, einer sehr harten Einheit (ab 8 von 10) oder einer ausgefallenen
  Einheit plant die App die 14 Tage außer der Reihe neu; der Server bremst die betroffene Sportart.
- **Triathlon:** Koppeltraining (Laufen nach Rad), drinnen auf Rolle oder Laufband, Freiwasser (Ziel im Freiwasser:
  in den 8 Wochen davor jede Woche eine Einheit im See, ohne Zugang Freiwasser-Elemente im Becken), Wetter (bei Gewitter, Sturm,
  Starkregen oder Glätte nach drinnen), Kalender (volle Tage werden kürzer oder "keine Zeit"), Kraft- und
  Mobilitätsblöcke mit Übungen und ein Plan für den Wettkampftag (Ablauf, Pacing, Wechsel, Verpflegung, Packliste).
- **iPhone:** Heute (Einheiten des Tages, Wunsch, Rückmeldung, Testergebnis bestätigen), Plan (14 Tage anpassen,
  Sportart tauschen, Gesamtplan mit Feedback, Wettkampftag), Dashboard (Kacheln, Woche gegen Plan, Erholung, Ziel),
  Verlauf, Leistungsprofil. Einstellungen "Planung": Kraft und Mobilität pro Woche, Wetter (ungefährer Ort), Kalender
  (Trainingsfenster), unter Equipment Rolle, Laufband und Zugang zu Freiwasser.
- **Watch:** Einheiten vom iPhone oder freies Training, Stand im Plan mit Ansagen, Hinweise zu Koppeltraining und drinnen
  (Ort vorgewählt), Leistungstests mit Auswertung auf der Uhr, Aufzeichnung in Health.
- **Verträge** zwischen App und Server ([`contracts/`](contracts/README.md)): Swift- und Jest-Tests lesen dieselben
  Dateien.
- **Lint:** Außerhalb der Module verzweigt niemand nach einer Sportart (`SportLintTests`, `test/sports/lint.test.ts`).

## Architektur

- **iOS-App** (`App/`): Oberfläche, Health-Abfrage, Plan vom Server, Übertragung an die Watch
- **watchOS-App** (`WatchApp/`): Companion-App im selben Build. Sie fragt Health selbst an und zeichnet ohne iPhone in
  Reichweite auf (beim Schwimmen bleibt es an Land); den Plan bekommt sie vom iPhone.
- **SwimInstructorCore** (`Packages/SwimInstructorCore/`): die gemeinsame Logik von iPhone und Watch, plattformunabhängig
  mit eigener Test-Suite. Darin `Sports/` mit den Modulen und der Registry.
- **Backend** (`backend/`): Node/TypeScript-Server zwischen App und Claude, mit Token je Nutzer (Daten getrennt), Budget,
  Sicherheitsschicht, Kosten- und Fehlerprotokoll und Alarmen. Einrichtung, Nutzer, Monitoring und automatisches Deploy:
  [`docs/backend-deploy.md`](docs/backend-deploy.md).

## Betatest

Was auf dem Gerät zu prüfen ist, steht der Reihe nach in der [Betatest-Checkliste](docs/betatest.md).

Mehrere Wochen echtes Training mit der App. Danach justieren wir vor allem diese Stellen, alle Startwerte aus dem
Trainingswissen:

| Was | Startwert | Wo |
|---|---|---|
| Grenzen je Sportart, besonders Laufen | Laufeinheit höchstens 10 % länger als die längste der letzten 4 Wochen, Woche hart bei +30 %, geplant etwa +10 % | `limits` im Server-Modul, z. B. [`run.ts`](backend/src/sports/modules/run.ts); Übersicht in [`multisport-planning.md`](docs/multisport-planning.md#grenzen-je-sportart) |
| Abstand der Leistungstests | alle 6 Wochen (einstellbar 4 bis 12); nach einer Pause oder ohne genug lange Läufe ist der erste Lauftest der lockere Einstiegstest | `MULTI_RULES.defaultTestIntervalWeeks` in [`limits.ts`](backend/src/plan/multi/limits.ts), `TestSettings.standard` in der App |
| Selbst angegebenes Startniveau | nach 2 bis 8 Wochen Pause gelten 70 % der Angabe (Laufen 50 %), nach längerer Pause 50 % (Laufen: zählt nicht); bis zum alten Niveau +20 % pro Woche (Laufen +10 %); die Angabe gilt 28 Tage | `startingLevel` im Server-Modul, `MULTI_RULES.startingLevelValidDays`; Übersicht in [`multisport-planning.md`](docs/multisport-planning.md#selbst-angegebenes-startniveau) |
| Sprunggrenze für neue Testwerte | weicht ein Wert um mehr als 10 % ab, warnt die App vor dem Übernehmen (eher Tipp- oder Messfehler) | `PerformanceProfileLoader.reviewThresholdPercent` |

Hilfreich zum Justieren: Tage, an denen der Plan zu viel oder zu wenig war, Schmerzen oder Pausen, und Testergebnisse,
die nicht zum Gefühl passten. Das Feedback zum Gesamtplan im Tab Plan geht direkt an Claude.

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
   Name z. B. "Peaksmith" (der Name der App im Store, unabhängig von der Bundle-ID), SKU frei wählbar. Kein Store-Release nötig, nur
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

### Tests

- **Package** (`swift test` im CI über `bundle exec fastlane test`): alle Logik von iPhone und Watch, dazu Verträge,
  Konformität jedes Moduls und Lint. Dateien unter `Sports/` brauchen 90 % Zeilen-Coverage.
- **Backend** (`cd backend && npm run typecheck && npm test`): Jest mit Coverage-Schwelle (90 % für `src/sports/`),
  Zufallstests der Sicherheitsschicht. Bewertung echter Pläne: [`docs/multisport-planning.md`](docs/multisport-planning.md#bewertung).
- **Builds** von App und Watch laufen in derselben CI.

## Projektstruktur

```
App/                                 # iOS-App (SwiftUI): Tabs Heute, Plan, Dashboard, Verlauf, dazu Einstellungen,
                                     # Ziel-Assistent, Leistungsprofil, Testergebnis, Onboarding; SwimInstructorApp.swift
                                     # verdrahtet Health, Einstellungen und die Loader
WatchApp/                            # watchOS-App: Einheiten des Tages, Aufzeichnung (WorkoutManager, RouteRecorder),
                                     # Ansagen, Plan vom iPhone (WatchPlanStore)
Shared/                              # Code für iPhone und Watch, der nicht ins Package gehört (Ladeanimation)
Packages/SwimInstructorCore/         # Die gemeinsame Logik von iPhone und Watch, plattformunabhängig, mit eigener Test-Suite
  Sources/SwimInstructorCore/
    Sports/                          #   Registry, Module (SwimModule, BikeModule, RunModule), Health-Zuordnung,
                                     #   Leistungswerte, Zonen, Tests, Aufzeichnung, Kennzahlen, Brücke zu alten Plänen
    PlanV2/                          #   Plan für alle Sportarten: Modelle, Client, Speicher, Anzeige-Texte, Loader für
                                     #   Heute, sieben Tage und Gesamtplan mit Feedback, Plan gegen Ist
    Statistics/                      #   Kennzahlen, Zeiträume, Rechnung und gespeicherte Kacheln des Dashboards
    (Dateien im Hauptordner)         #   Health lesen (Repositories, Deduplizierung), Zustand und Snapshot (Calculator,
                                     #   Builder), Ziel und Zielspeicher, Backend-Einstellungen, Fortschritt in der
                                     #   Einheit (SessionProgress), Texte (PlanFormatting), Übertragung iPhone <-> Watch
  Tests/SwimInstructorCoreTests/     #   Unit-Tests, dazu ContractTests und Lint (SportLintTests)
backend/                             # Node/TypeScript-Server zwischen App und Claude: Token, Budget, Sicherheitsschicht
  src/                               #   app.ts, auth.ts, config.ts, logger.ts, server.ts
  src/plan/                          #   Gemeinsames der Planung: Claude-Aufruf (generator), Budget, Fehler, Snapshot-Schema,
                                     #   Kalender (calendar), Wortschatz (vocabulary), Kosten (report)
  src/plan/multi/                    #   Gesamtplan, sieben Tage, Tag: Routen, Service, Prompts, Grenzen, Sicherheitsschichten
  src/sports/                        #   Registry (SPORTS), Wortschatz, Leistungswerte; modules/: ein Modul je Sportart
  scenarios/multisport/              #   9 Szenarien zur Bewertung, recorded/: aufgezeichnete Antworten
  scripts/eval-multisport.ts         #   Bewertung der Pläne: Claude, mit Aufzeichnung oder Wiedergabe
  scripts/eval-in-docker.sh          #   dasselbe auf dem Server ohne Node
  test/                              #   Jest + supertest
  Dockerfile, compose.yaml           #   Container-Image und Start auf dem Server
  deploy/                            #   Caddyfile-Vorlage, deploy.sh
contracts/                           # Verträge App <-> Server, von Swift- und Jest-Tests gelesen
docs/
  AthleteStateSnapshot.md            # JSON-Schema des Snapshots, Definitionen, Schwellenwerte
  backend-deploy.md                  # Server-Einrichtung Schritt für Schritt
  plan-generation.md                 # Ablauf der Plan-Erzeugung, Ausfallgründe, Kosten, Konfiguration
  multisport-planning.md             # Endpunkte, Einheiten, Grenzen, Leistungstests, Bewertung
  neue-sportart.md                   # Anleitung: neue Sportart hinzufügen
  meilensteine.md                    # M1 bis M8, T0 bis T7 mit Definition of Done, Roadmap
  eval-runs/                         # Rohausgaben der Bewertungsläufe
  logo/                              # SVG-Quellen des Symbols
project.yml                          # XcodeGen-Konfiguration (beide Targets + Package, Anzeigename APP_DISPLAY_NAME)
fastlane/                            # Appfile, Matchfile, Fastfile (Lanes test und beta: TestFlight inkl. Watch-App)
Gemfile                              # Ruby-Abhängigkeit: fastlane
.github/workflows/
  ios-ci.yml                         # Test- und TestFlight-Deploy-Pipeline
  backend-ci.yml                     # Backend: Typecheck, Build, Tests, npm audit, Docker-Smoke-Test
```

## Entstehung

Wie die App Schritt für Schritt gebaut wurde (M1 bis M8 als Schwimm-App, T0 bis T7 als Umbau zum Triathlon), jeweils mit
Definition of Done: [`docs/meilensteine.md`](docs/meilensteine.md).
