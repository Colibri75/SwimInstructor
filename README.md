# TriCoach

> Das Repo, die Targets und die Bundle-IDs heißen weiter **SwimInstructor**, damit TestFlight, die Health-Freigaben und
> die gespeicherten Daten bleiben. Nur der Name unter dem Symbol ist TriCoach (`APP_DISPLAY_NAME` in `project.yml`).

iOS- und watchOS-App für das Training im Triathlon: Sie liest Einheiten und Vitaldaten aus Apple Health, Claude plant
daraus über einen eigenen Server Gesamtplan, die nächsten sieben Tage und den Tag, und die Watch führt durch die Einheit.
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
| Belastung | `loadFactor` für die Trainingslast (TRIMP, sonst Minuten) | `loadFactor` |
| Leistungsprofil | Werte, Tests mit Eingabe und Auswertung, Zonen, Schätzung ohne Test | Werte und Tests |
| Planung | | Grenzen (`limits`), Schrittraster, erlaubte Zielbereiche, Testeinheiten, Regeln für Claude (`promptRules`) |
| Watch | Orte, Live-Werte, Glättung des Tempos (`recording`) | |
| Statistik | Kennzahlen der Kacheln (`statistics`, sonst aus Health abgeleitet) | |

### Was der Kern für alle Sportarten macht

- **Ziel** mit Disziplinen, Zieltag, Stunden pro Woche und Schwerpunkten je Sportart (`TrainingGoal`, Vorlagen in
  `GoalTemplates`).
- **Zustand** aus Health: Snapshot v2 mit Werten je Sportart, Gesamtlast und Leistungsprofil
  ([`docs/AthleteStateSnapshot.md`](docs/AthleteStateSnapshot.md)).
- **Planung** auf dem Server: Gesamtplan bis zum Ziel, sieben Tage, Tagesplan, Überarbeitung nach Feedback; die
  Sicherheitsschicht hält die Grenzen der Module und die übergreifenden Regeln ein
  ([`docs/multisport-planning.md`](docs/multisport-planning.md)).
- **iPhone:** Heute (Einheiten des Tages, Wunsch, Testergebnis bestätigen), Plan (sieben Tage anpassen, Sportart
  tauschen, Gesamtplan mit Feedback), Dashboard (Kacheln, Woche gegen Plan, Erholung, Ziel), Verlauf, Leistungsprofil.
- **Watch:** Einheiten vom iPhone oder freies Training, Stand im Plan mit Ansagen, Leistungstests mit Auswertung auf der
  Uhr, Aufzeichnung in Health.
- **Verträge** zwischen App und Server ([`contracts/`](contracts/README.md)): Swift- und Jest-Tests lesen dieselben
  Dateien.
- **Lint:** Außerhalb der Module verzweigt niemand nach einer Sportart (`SportLintTests`, `test/sports/lint.test.ts`).

## Architektur

- **iOS-App** (`App/`): Oberfläche, Health-Abfrage, Plan vom Server, Übertragung an die Watch
- **watchOS-App** (`WatchApp/`): Companion-App im selben Build. Sie fragt Health selbst an und zeichnet ohne iPhone in
  Reichweite auf (beim Schwimmen bleibt es an Land); den Plan bekommt sie vom iPhone.
- **SwimInstructorCore** (`Packages/SwimInstructorCore/`): die gemeinsame Logik von iPhone und Watch, plattformunabhängig
  mit eigener Test-Suite. Darin `Sports/` mit den Modulen und der Registry.
- **Backend** (`backend/`): Node/TypeScript-Server zwischen App und Claude, mit Token, Budget und Sicherheitsschicht.
  Einrichtung: [`docs/backend-deploy.md`](docs/backend-deploy.md).

## Betatest

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

### Tests

- **Package** (`swift test` im CI über `bundle exec fastlane test`): alle Logik von iPhone und Watch, dazu Verträge,
  Konformität jedes Moduls und Lint. Dateien unter `Sports/` brauchen 90 % Zeilen-Coverage.
- **Backend** (`cd backend && npm run typecheck && npm test`): Jest mit Coverage-Schwelle (90 % für `src/sports/`),
  Zufallstests der Sicherheitsschicht. Bewertung echter Pläne: [`docs/multisport-planning.md`](docs/multisport-planning.md#bewertung).
- **Builds** von App und Watch laufen in derselben CI.

## Projektstruktur

```
App/                                # iOS-App
  SwimInstructorApp.swift            # App-Einstiegspunkt, verdrahtet Health, Einstellungen, Loader für Plan v2 und Profil
  PhonePlanSync.swift                # Schickt den Tagesplan an die Watch, empfängt Testergebnisse (M7, T5)
  RootView.swift                     # Tabs: Heute, Plan, Dashboard, Verlauf
  TodayView.swift                    # Heute: Testergebnis der Watch, Eintrag aus dem Plan, Karte je Einheit, Wunsch
  SessionCardView.swift              # Tagesplan v2: Kopf, Karte je Einheit mit Schritten, Test-Knopf
  TestResultSheet.swift              # Testergebnis eintragen, Vergleich, Übernehmen oder Verwerfen (T4)
  WeekView.swift                     # Plan: Woche je Sportart, Tage mit bis zu zwei Einheiten, Planen
  DayEditSheet.swift                 # Tag anpassen: Umfang, Sportart tauschen, Einheit dazu oder weg, Tage tauschen
  MacroPlanSections.swift            # Gesamtplan je Sportart, Testtermine, Feedback mit Änderungen und Runden
  ProfileView.swift                  # Leistungsprofil: Werte, Herkunft, Verlauf, Eingabe von Hand, Testeinstellungen
  StatsViews.swift                   # Woche je Sportart und Erholung (Dashboard), Einheiten-Zeile aller Sportarten (Verlauf)
  DashboardView.swift                # Kacheln der Statistik, Woche gegen den Plan, Ziel (M8, T6)
  StatisticTilesView.swift           # Kachel, Verlauf (Swift Charts), Auswahl per langem Drücken, Ziehen, Hinzufügen (T6)
  HistoryView.swift                  # Verlauf geplant gegen tatsächlich je Sportart
  GoalAssistantView.swift            # Ziel mit Disziplinen, Zieltag, Stunden und Schwerpunkten (T2)
  SettingsView.swift                 # Server-Adresse, Token, Verbindung testen
  Info.plist                         # Anzeigename und Health-Hinweise aus APP_DISPLAY_NAME
  SwimInstructor.entitlements        # HealthKit-Capability
WatchApp/                           # watchOS Companion-App
  SwimInstructorWatchApp.swift       # App-Einstiegspunkt, wechselt zwischen Plan, Einheit, Zusammenfassung
  WatchTodayView.swift               # Einheiten des Tages, freies Training, Start mit Sportart, Ort, Bahnlänge (T5)
  WatchWorkoutView.swift             # Laufende Einheit und Zusammenfassung mit Testergebnis (T5)
  WatchPlanStore.swift               # Plan vom iPhone, Testergebnisse ans iPhone (M7, T5)
  WorkoutManager.swift               # HKWorkoutSession für jede Sportart, Stand im Plan, Testauswertung (T5)
  RouteRecorder.swift                # GPS-Strecke und Höhenmeter draußen (T5)
  Announcer.swift                    # Ansagen der Schritte (T5)
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
    TrainingStatistics.swift         # Wochenumfang und Pace je Einheit beim Schwimmen (M8, seit T6 nicht mehr angezeigt)
    PlanHistory.swift                # Gespeicherte Tagespläne der letzten Wochen (M8)
    PlanAdherence.swift              # Geplant gegen geschwommen, Zusammenfassung (M8)
    WeekPlan.swift                   # Wochenplan: Tage, Vorgabe für den Tagesplan
    MacroPlan.swift                  # Gesamtplan bis zum Zieltag (Wochen, Phasen), Speicher
    MacroPlanLoader.swift            # Gesamtplan holen/erneuern (einmal am Tag je Ziel)
    WeekCalendar.swift               # Wochen von Montag bis Sonntag, Kalendertage
    WeekPlanEditor.swift             # Änderungen des Athleten, Zusammenführen nach dem Neuplanen
    WeekProgress.swift               # Status je Tag aus Health gegen den Plan
    WeekPlanStore.swift              # Wochenpläne auf dem Gerät
    WeekPlanLoader.swift             # Ablauf des Wochen-Tabs (Plan v1, von der App seit T4 nicht mehr genutzt)
    PerformanceProfileLoader.swift   # Leistungsprofil: Werte, Eingabe von Hand, Testergebnis nach Bestätigung (T4)
    SessionProgress.swift            # Stand in der Einheit nach Strecke, Zeit oder von Hand (T5)
    ProgressFormatting.swift         # Texte und Ansagen zum Stand in der Einheit (T5)
    LiveWorkoutMetrics.swift         # Live-Werte jeder Sportart, aktuelle Geschwindigkeit, Höhenmeter (T5)
    WorkoutRecording.swift           # Messreihen der Watch für die Testauswertung (T5)
    TestResultSync.swift             # Testergebnis Watch -> iPhone, Eingang bis zur Bestätigung (T5)
    PlanV2/                          # Plan v2 für alle Sportarten (T4): Modelle, Client, Speicher, Anzeige-Texte,
                                     # Loader für Heute, sieben Tage und Gesamtplan mit Feedback, Plan gegen Ist
    Statistics/                      # Kennzahlen, Zeiträume, Rechnung, Texte und gespeicherte Kacheln (T6)
    Sports/                          # Registry, Health-Zuordnung, Leistungswerte, Zonen, Tests, Aufzeichnung, Kennzahlen
    Sports/Modules/                  # Ein Modul je Sportart: SwimModule, BikeModule, RunModule
  Tests/SwimInstructorCoreTests/
    HealthKitManagerTests.swift
    SwimWorkoutRepositoryTests.swift
    SwimWorkoutDeduplicatorTests.swift
    AthleteStateCalculatorTests.swift  # 5 Szenarien + Randfaelle + Schema
backend/                            # Node/TypeScript-Server (Proxy fuer Claude, ab M5)
  src/                               # app.ts, auth.ts, config.ts, logger.ts, server.ts
  src/plan/                          # Plan-Erzeugung (M5): Claude-Aufruf, Sicherheitsschicht, Fallback
  src/plan/multi/                    # Plan v2 für mehrere Sportarten (T3): Grenzen, Sicherheitsschicht, Tests, Prompts
  src/sports/                        # Registry (SPORTS), Wortschatz, Leistungswerte; modules/: ein Modul je Sportart
  scenarios/                         # die 5 Snapshots aus M3 (Eingabe für npm run eval:scenarios)
  scenarios/multisport/              # 8 Szenarien für Plan v2, recorded/: aufgezeichnete Antworten
  scripts/eval-scenarios.ts          # echter Lauf gegen die Claude-API zur manuellen Bewertung
  scripts/eval-multisport.ts         # Bewertung Plan v2: Claude, mit Aufzeichnung oder Wiedergabe
  test/                              # Jest + supertest
  Dockerfile, compose.yaml           # Container-Image und Start auf dem Server
  deploy/                            # Caddyfile-Vorlage, deploy.sh
contracts/                           # Verträge App <-> Server, von Swift- und Jest-Tests gelesen
docs/
  AthleteStateSnapshot.md            # JSON-Schema, Definitionen, Schwellenwerte
  backend-deploy.md                  # Server-Einrichtung Schritt fuer Schritt
  plan-generation.md                 # /v1/plan/today: Ablauf, Regeln, Kosten, Konfiguration
  multisport-planning.md             # Plan v2: Endpunkte, Einheiten, Grenzen, Leistungstests, Bewertung
  plan-eval.md                       # Bewertung der Pläne von Plan v1
  neue-sportart.md                   # Anleitung: neue Sportart hinzufügen
  meilensteine.md                    # M1 bis M8 und T0 bis T7 mit Definition of Done
  Package.swift
project.yml                          # XcodeGen-Konfiguration (beide Targets + Package, Anzeigename APP_DISPLAY_NAME)
fastlane/
  Appfile                             # Bundle-ID, Apple-ID, Team-ID
  Matchfile                           # Zertifikats-Repo-Konfiguration (iOS + Watch Bundle-IDs)
  Fastfile                            # Lanes: test, beta (TestFlight-Upload, inkl. Watch-App)
Gemfile                               # Ruby-Abhängigkeit: fastlane
.github/workflows/
  ios-ci.yml                          # Test- und TestFlight-Deploy-Pipeline
  backend-ci.yml                      # Backend: Typecheck, Build, Tests, npm audit, Docker-Smoke-Test
```

## Entstehung

Wie die App Schritt für Schritt gebaut wurde (M1 bis M8 als Schwimm-App, T0 bis T7 als Umbau zum Triathlon), jeweils mit
Definition of Done: [`docs/meilensteine.md`](docs/meilensteine.md).
