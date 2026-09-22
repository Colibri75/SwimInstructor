# SwimApp

iOS- und watchOS-App, die Schwimm-Trainingsdaten aus Apple Health liest und
darauf basierend einen tagesaktuellen, von Claude generierten Trainingsplan
erstellt. Ziel: 3.800 m unter 60 Minuten bis zum 04.07.2027.

Der Code wird auf einem beliebigen Rechner (z.B. Windows) bearbeitet. Bauen,
Signieren und Verteilen läuft vollautomatisch über GitHub Actions + Fastlane +
TestFlight (Apple Developer Program vorausgesetzt) – ein eigener Mac ist dafür
nicht nötig. Details siehe [CI/CD-Setup](#cicd-setup--testflight) unten.

## Architektur: iOS + watchOS

Die Watch-App ist eine **Companion-App**, die zusammen mit der iPhone-App im
selben Build/derselben TestFlight-Installation ausgeliefert wird (kein
separater Store-Eintrag, keine separate Pipeline nötig). Gemeinsame Logik
(HealthKit-Zugriff, später Zustandsberechnung und Backend-API-Client) liegt in
einem lokalen Swift Package `Packages/SwimAppCore`, das von beiden Targets
genutzt wird – so entsteht kein doppelt gepflegter Code.

- **iOS-App** (`App/`): vollständige UI, Dashboard, Verlauf
- **watchOS-App** (`WatchApp/`): kompakte "Heute"-Ansicht, später Live-Workout-Tracking direkt am Handgelenk
- **SwimAppCore** (`Packages/SwimAppCore/`): HealthKit-Zugriff, Zustandsmodell, API-Client – plattformunabhängig, eigene Test-Suite

Die Watch-App fragt HealthKit **eigenständig** an und kann später auch ohne
gekoppeltes iPhone in Reichweite mit dem Backend sprechen (watchOS-Apps können
seit watchOS 9 direkt übers eigene WLAN/Mobilfunk ins Netz) – wichtig, weil man
beim Schwimmen das iPhone nicht dabei hat.

## CI/CD-Setup & TestFlight

Pipeline: `git push` auf `main` → GitHub Actions baut auf einem macOS-Runner,
lässt die Unit-Tests laufen, signiert per [fastlane match](https://docs.fastlane.tools/actions/match/)
und lädt den Build zu TestFlight hoch. Installation aufs iPhone dann über die
TestFlight-App – kein manuelles Signieren, kein eigener Mac im Alltag.

### Einmaliges Setup (Account-Seite, nicht Code)

1. **Apple Developer Program** unter developer.apple.com abschließen (99$/Jahr,
   Freischaltung kann bis zu 48h dauern).
2. **App Store Connect:** neuen App-Eintrag anlegen – Bundle-ID
   `com.steffenkellner.SwimApp` (muss exakt zu `project.yml` passen), Name z.B.
   "SwimApp", SKU frei wählbar. Kein Store-Release nötig, nur für TestFlight.
   Die Watch-App (`com.steffenkellner.SwimApp.watchkitapp`) braucht **keinen**
   eigenen App-Store-Connect-Eintrag – sie hängt am iOS-Eintrag und wird als
   Teil desselben Builds mit hochgeladen.
3. **App Store Connect API Key** erzeugen (Nutzer und Zugriff → Schlüssel →
   Rolle "App Manager"): Key-ID, Issuer-ID notieren, `.p8`-Datei herunterladen
   (nur einmal möglich!).
4. **Separates privates Repo nur für Zertifikate** anlegen, z.B.
   `Colibri75/SwimApp-certificates` – niemals in diesem Repo, auch nicht wenn
   `SwimApp` public ist.
5. **Einmaliger Mac-Zugriff** (z.B. 1h MacinCloud) für die Ersteinrichtung von
   `fastlane match`:
   ```bash
   bundle install
   bundle exec fastlane match appstore
   ```
   Legt Verteilungszertifikat + Provisioning Profile verschlüsselt im
   Certificates-Repo ab. Danach wird dieser Schritt nie wieder manuell
   gebraucht – CI nutzt dieselben Zertifikate schreibgeschützt (`readonly`).
6. **GitHub Secrets** im `SwimApp`-Repo hinterlegen (Settings → Secrets and
   variables → Actions):

   | Secret | Wert |
   |---|---|
   | `APPLE_ID` | deine Apple-ID-E-Mail |
   | `APPLE_TEAM_ID` | aus developer.apple.com/account → Membership Details |
   | `MATCH_GIT_URL` | HTTPS-URL des Certificates-Repos |
   | `MATCH_PASSWORD` | selbst gewähltes Passwort zum Verschlüsseln der Zertifikate |
   | `MATCH_GIT_BASIC_AUTHORIZATION` | `base64("github-username:PAT")` mit Lesezugriff aufs Certificates-Repo |
   | `APP_STORE_CONNECT_KEY_ID` | aus Schritt 3 |
   | `APP_STORE_CONNECT_ISSUER_ID` | aus Schritt 3 |
   | `APP_STORE_CONNECT_KEY_CONTENT` | Inhalt der `.p8`-Datei, `base64 -i AuthKey_XXXX.p8` |

7. **TestFlight-App** aus dem App Store auf dein iPhone laden, damit du
   hochgeladene Builds direkt installieren kannst.
8. Optional: Repo auf **public** stellen → macOS-CI-Minuten dauerhaft
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
cd SwimApp
xcodegen generate
open SwimApp.xcodeproj
```

In Xcode:
1. Target `SwimApp` auswählen → Tab **Signing & Capabilities**
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

```bash
xcodebuild test -scheme SwimApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

Läuft über die `SwimApp`-Scheme auch die Tests von `SwimAppCore` (siehe
unten) mit. `HealthKitManagerTests` prüft, dass alle für M2/M3 benötigten
HealthKit-Typen (Workouts, Herzfrequenz, Ruhepuls, HRV, Schwimmdistanz,
Schlaf) im Autorisierungs-Request enthalten sind. Alternativ, nur das Package
ohne Simulator testen:

```bash
cd Packages/SwimAppCore && swift test
```

## M2 – HealthKit Data Layer

`SwimWorkoutRepository` (in `Packages/SwimAppCore`) liest reale
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

### Unit-Tests (Package)

```bash
cd Packages/SwimAppCore && swift test
```

`SwimWorkoutRepositoryTests` deckt ab: Pace-Berechnung, Verhalten ohne
Distanz (kein Pace/SWOLF), Bahnenzählung aus `HKWorkoutEvent`s (nur `.lap`,
nicht `.pause`), `nil` bei fehlenden Lap-Events, SWOLF-Näherung.

## Projektstruktur

```
App/                          # iOS-App
  SwimAppApp.swift             # App-Einstiegspunkt
  ContentView.swift            # Platzhalter-UI mit Health-Berechtigungs-Button
  Info.plist
  SwimApp.entitlements         # HealthKit-Capability
WatchApp/                     # watchOS Companion-App
  SwimAppWatchApp.swift        # App-Einstiegspunkt
  WatchTodayView.swift         # Platzhalter "Heute"-Ansicht
  Info.plist                   # inkl. WKCompanionAppBundleIdentifier
  SwimAppWatch.entitlements    # HealthKit-Capability
Packages/SwimAppCore/         # Von iOS + Watch geteilte Logik
  Sources/SwimAppCore/
    HealthKitManager.swift     # Autorisierung
    SwimWorkout.swift          # Domain-Modell (Pace, SWOLF-Näherung)
    SwimWorkoutRepository.swift # Liest Workouts aus HealthKit + Mapping
  Tests/SwimAppCoreTests/
    HealthKitManagerTests.swift
    SwimWorkoutRepositoryTests.swift
  Package.swift
project.yml                    # XcodeGen-Konfiguration (beide Targets + Package)
fastlane/
  Appfile                       # Bundle-ID, Apple-ID, Team-ID
  Matchfile                     # Zertifikats-Repo-Konfiguration (iOS + Watch Bundle-IDs)
  Fastfile                      # Lanes: test, beta (TestFlight-Upload, inkl. Watch-App)
Gemfile                         # Ruby-Abhängigkeit: fastlane
.github/workflows/
  ios-ci.yml                    # Test- und TestFlight-Deploy-Pipeline
```

## Roadmap

Siehe Task-Liste der Session (M1–M11 + CI/CD) für den vollständigen
Meilensteinplan inkl. Definition of Done pro Meilenstein.
