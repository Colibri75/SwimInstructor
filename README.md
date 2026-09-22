# SwimApp

iOS-App, die Schwimm-Trainingsdaten aus Apple Health liest und darauf basierend
einen tagesaktuellen, von Claude generierten Trainingsplan erstellt. Ziel:
3.800 m unter 60 Minuten bis zum 04.07.2027.

Der Code wird auf einem beliebigen Rechner (z.B. Windows) bearbeitet. Bauen,
Signieren und auf einem echten iPhone testen geht nur auf einem Mac mit Xcode.

## M1 – Projekt-Setup & HealthKit-Berechtigung

Dieses Repo enthält kein eingechecktes `.xcodeproj` (siehe `.gitignore`) –
stattdessen [XcodeGen](https://github.com/yonaskolb/XcodeGen) mit `project.yml`
als Quelle der Wahrheit. Das vermeidet Merge-Konflikte in der binären
Xcode-Projektdatei und lässt sich reproduzierbar neu erzeugen.

### Setup auf dem Mac

```bash
brew install xcodegen
cd SwimApp
xcodegen generate
open SwimApp.xcodeproj
```

In Xcode:
1. Target `SwimApp` auswählen → Tab **Signing & Capabilities**
2. Bei **Team** deine kostenlose Apple-ID auswählen (Signing ist bereits auf
   `Automatic` gestellt)
3. Dein iPhone per Kabel/WLAN als Build-Ziel wählen, ⌘R

### M1 – Definition of Done (manuell zu verifizieren)

- [ ] `xcodegen generate` läuft ohne Fehler
- [ ] Projekt baut fehlerfrei (Debug) für Simulator und echtes Gerät
- [ ] App installiert sich auf dem iPhone (Free Provisioning, 7-Tage-Zertifikat)
- [ ] Beim Tippen auf "Health-Zugriff anfragen" erscheint der HealthKit-Dialog
- [ ] **Testfall A:** Zugriff erlauben → Status wechselt zu "Health-Zugriff
      angefragt ✓", kein Crash
- [ ] **Testfall B:** App löschen, neu installieren, Zugriff ablehnen → App
      bleibt stabil, kein Crash, keine Endlosschleife

### Unit-Tests

```bash
xcodebuild test -scheme SwimApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

`HealthKitManagerTests` prüft, dass alle für M2/M3 benötigten HealthKit-Typen
(Workouts, Herzfrequenz, Ruhepuls, HRV, Schwimmdistanz, Schlaf) im
Autorisierungs-Request enthalten sind.

## Projektstruktur

```
App/
  SwimAppApp.swift          # App-Einstiegspunkt
  ContentView.swift          # Platzhalter-UI mit Health-Berechtigungs-Button
  HealthKit/
    HealthKitManager.swift   # Autorisierung (Datenzugriff folgt in M2)
  Info.plist
  SwimApp.entitlements       # HealthKit-Capability
Tests/
  SwimAppTests/
    HealthKitManagerTests.swift
project.yml                  # XcodeGen-Konfiguration
```

## Roadmap

Siehe Task-Liste der Session (M1–M11 + CI/CD) für den vollständigen
Meilensteinplan inkl. Definition of Done pro Meilenstein.
