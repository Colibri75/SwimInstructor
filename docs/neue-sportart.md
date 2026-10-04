# Neue Sportart hinzufügen

Eine Sportart ist ein **Modul in der App**, ein **Modul auf dem Server** und ein **Eintrag im Vertrag** dazwischen. Der
Rest der App fragt nie "welche Sportart ist das?", sondern immer das Modul: Ziel, Plan, Watch, Leistungsprofil,
Statistik und Health nehmen eine neue Sportart von selbst auf. Lint-Tests auf beiden Seiten sorgen dafür, dass das so
bleibt.

Als Beispiel steht hier **Rudern** (Kennung `rowing`). Rudern wurde genau nach dieser Anleitung als echtes Modul
angelegt und in der CI geprüft, siehe [Die Probe](#die-probe) am Ende.

## Diese Dateien ändern sich, sonst keine

`<Name>` ist der Name in Swift (z. B. `Rowing`), `<id>` die Kennung (z. B. `rowing`).

| | Datei | Was |
|---|---|---|
| 1 | `contracts/sports.json` | Neuer Eintrag unter `sports` |
| 2 | `Packages/SwimInstructorCore/Sources/SwimInstructorCore/Sports/Modules/<Name>Module.swift` | Neu: das App-Modul |
| 3 | `Packages/SwimInstructorCore/Sources/SwimInstructorCore/Sports/SportModule.swift` | Das Modul in `SportRegistry.standard` anhängen |
| 4 | `Packages/SwimInstructorCore/Tests/SwimInstructorCoreTests/<Name>ModuleTests.swift` | Neu: Tests der eigenen Logik |
| 5 | `backend/src/sports/modules/<id>.ts` | Neu: das Server-Modul |
| 6 | `backend/src/sports/registry.ts` | Import und Eintrag in `SPORTS` |
| 7 | `backend/test/sports/<id>.test.ts` | Neu: Tests der eigenen Logik |
| 8 | `README.md` | Zeile in der Tabelle "Sportarten" |

`App/`, `WatchApp/`, der Plan-Kern (`backend/src/plan/`), die Statistik und die Tests der anderen Sportarten bleiben
unberührt. Wird dort ein Test rot, ist das ein Fehler im Kern, kein fehlender Schritt dieser Anleitung.

Neue Ziele (`targets`), Maße (`measures`) oder Live-Werte der Watch gehören nicht zu einer Sportart, sondern zum
gemeinsamen Wortschatz. Sie sind eine eigene Änderung am Kern, vor der neuen Sportart.

## 1. Vertrag: `contracts/sports.json`

Zuerst der Vertrag, denn App und Server prüfen sich beide gegen ihn (`ContractTests`, `test/contracts.test.ts`). Neue
Sportarten kommen ans Ende der Liste; die Reihenfolge ist die Reihenfolge in der App.

```json
{
  "id": "rowing",
  "display_name": "Rudern",
  "measures": ["duration", "distance"],
  "targets": ["stroke_rate", "heart_rate_zone", "perceived_effort"],
  "goal_speed": {"min_meters_per_second": 2, "max_meters_per_second": 7},
  "load_factor": 0.9,
  "plan_unit": "minutes",
  "typical_speed_meters_per_second": 3.5,
  "performance_metrics": [
    {"id": "threshold_heart_rate", "display_name": "Schwellenpuls", "unit": "bpm", "min": 100, "max": 215},
    {"id": "time_2000m", "display_name": "2000-m-Zeit", "unit": "s", "min": 330, "max": 1200}
  ],
  "performance_tests": [
    {"id": "time_trial_2000m", "display_name": "2000-m-Test", "produces": ["time_2000m", "threshold_heart_rate"], "maximal_effort": true, "duration_minutes": 8}
  ]
}
```

- `id`: Kleinbuchstaben, Ziffern und Unterstrich, beginnt mit einem Buchstaben, 2 bis 32 Zeichen. Nie wieder ändern:
  Sie steht in gespeicherten Plänen, Profilen und Kacheln.
- `measures` und `targets`: nur Werte aus den Listen oben in der Datei. `perceived_effort` muss dabei sein, der Server
  ersetzt damit jedes Ziel, das für den Athleten nicht passt.
- `goal_speed`: Durchschnittstempo, das ein Wettkampfziel haben darf (Strecke durch Zielzeit). Schützt vor Tippfehlern;
  das Obere muss mehr als doppelt so groß sein wie das Untere.
- `load_factor`: Belastung einer Minute verglichen mit einer Minute Laufen (1,0).
- `plan_unit`: `meters` oder `minutes`, in dieser Einheit plant und begrenzt der Server den Umfang.
- `typical_speed_meters_per_second`: Trainingstempo inklusive Pausen, zum Umrechnen von Metern und Minuten.
- `performance_metrics`: eigene Leistungswerte. Maximal- und Ruhepuls gehören allen Sportarten und stehen nicht hier.
- `performance_tests`: mindestens ein Test, der nur eigene Werte ermittelt.

## 2. App-Modul: `Sports/Modules/<Name>Module.swift`

Eine Struktur, die `SportModule` erfüllt. Alle Werte, die auch im Vertrag stehen, müssen dort genau so stehen.

```swift
import Foundation
import HealthKit

public extension SportID {
    static let rowing: SportID = "rowing"
}

public extension PerformanceMetric {
    static let twoKilometerRowingTime: PerformanceMetric = "time_2000m"
}

public struct RowingModule: SportModule {
    public init() {}

    public let id = SportID.rowing
    public let displayName = "Rudern"
    public let symbolName = "figure.rower"                 // SF Symbol
    public let measures: Set<StepMeasure> = [.duration, .distance]
    public let targets: Set<StepTarget> = [.strokeRate, .heartRateZone, .perceivedEffort]
    public let health = SportHealthMapping(activityTypes: [.rowing], distance: nil)
    public let loadFactor = 0.9
    public let goalSpeedRange: ClosedRange<Double> = 2...7
    public let planUnit = PlanUnit.minutes
    public let typicalSpeedMetersPerSecond: Double = 3.5

    public let performanceMetrics: [PerformanceMetricDefinition] = [
        .thresholdHeartRate,
        PerformanceMetricDefinition(metric: .twoKilometerRowingTime, displayName: "2000-m-Zeit", unit: "s", plausibleRange: 330...1200)
    ]
    public let performanceTests: [PerformanceTest] = [
        PerformanceTest(
            id: "time_trial_2000m", displayName: "2000-m-Test",
            produces: [.twoKilometerRowingTime, .thresholdHeartRate], maximalEffort: true, durationMinutes: 8,
            resultHint: "Zeit für die 2000 m, Schwellenpuls: Schnitt der letzten 5 Minuten.",
            recorded: [.average(input: PerformanceMetric.thresholdHeartRate.rawValue, signal: .heartRate, lastSeconds: 5 * 60)]
        )
    ]
    public let zoneSchemes: [ZoneScheme] = [
        ZoneScheme(target: .heartRateZone, basis: .thresholdHeartRate, bounds: [0.80, 0.88, 0.94, 1.00])
    ]

    public func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate] { … }
}
```

Pflicht:

- **`health`**: die Workout-Arten aus Health. Jede gehört genau einer Sportart. Strecke (`distance`) und Messwerte
  (`metrics`) nur mit Typen, die es ab iOS 17 und watchOS 10 gibt (neuere als Text-Kennung wie bei
  `BikeModule`), sonst `nil` bzw. weglassen.
- **Ein Leistungstest mit `resultHint`.** Ohne `inputs` trägt der Athlet je ermitteltem Wert ein Feld aus; was die Watch
  selbst messen kann, steht in `recorded` und muss eines dieser Felder sein.
- **Coverage:** Jede Datei unter `Sports/` braucht 90 % Zeilen-Coverage (Fastlane `check_sports_coverage`). Die
  allgemeinen Prüfungen decken die festen Werte ab; eigene Logik (Schätzungen, Zonen) testet Schritt 4.

Mit Standard, wenn nichts angegeben ist:

| Eigenschaft | Standard |
|---|---|
| `recording` | Draußen mit GPS oder drinnen, groß das Tempo in km/h, dazu die Strecke |
| `statistics` | Aus `health` abgeleitet: Strecke und Tempo nur mit `distance`, dazu Zeit, Einheiten, Puls, Punkte |
| `zoneSchemes` | keine Zonen; dann gibt der Server kein Pulszonenziel und plant nach gefühlter Anstrengung |
| `estimatePerformance` | keine Schätzung ohne Test |

Regeln, die die Lint-Tests prüfen: Die Kennung (`SportID.rowing`, `"rowing"`, `case .rowing`) steht nur unter
`Sports/`. App und Watch fragen das Modul, nie die Kennung.

## 3. App-Registry: `Sports/SportModule.swift`

Eine Zeile, das Modul hinten anhängen:

```swift
public static let standard: SportRegistry = try! SportRegistry(modules: [SwimModule(), BikeModule(), RunModule(), RowingModule()])
```

Die Registry prüft beim Anlegen, dass das Modul vollständig ist (Kennung, Name, Symbol, Workout-Arten, Tempo, Werte,
Tests, Zonen, Aufzeichnung, Kennzahlen). `SportRegistryTests` und `ContractTests` legen sie in der CI an.

## 4. App-Tests: `Tests/SwimInstructorCoreTests/<Name>ModuleTests.swift`

Nur die eigene Logik, zum Beispiel die Schätzung der 2000-m-Zeit und die Grenzen der Zonen. Alles Allgemeine läuft für
jedes Modul der Registry von selbst:

- `SportModuleConformanceTests`: vollständig, Health-Umwandlung, Belastung, Zieltempo, Ziel mit allen Schwerpunkten,
  Leistungswerte, Zonen, Schätzungen, Kennzahlen
- `ContractTests`: Modul gleich Vertrag
- `SportRecordingTests`, `TestEvaluationTests`, `RecordedTestEvaluationTests`: Aufzeichnung und Tests
- `SportLintTests`: keine Kennung außerhalb von `Sports/`

## 5. Server-Modul: `backend/src/sports/modules/<id>.ts`

Ein `SportDefinition`-Objekt (Typ in `backend/src/sports/types.ts`). Die Felder aus dem Vertrag stehen gleich da, dazu
die Planung:

```ts
export const rowing: SportDefinition = {
  id: "rowing",
  displayName: "Rudern",
  measures: ["duration", "distance"],
  targets: ["stroke_rate", "heart_rate_zone", "perceived_effort"],
  goalSpeed: { minMetersPerSecond: 2, maxMetersPerSecond: 7 },
  loadFactor: 0.9,
  performanceMetrics: [THRESHOLD_HEART_RATE, TIME_2000M],
  performanceTests: [{ id: "time_trial_2000m", displayName: "2000-m-Test", produces: ["time_2000m", "threshold_heart_rate"], maximalEffort: true, durationMinutes: 8 }],
  planning: {
    limitUnit: "minutes",               // gleich plan_unit
    limits: { sessionGrowthFactor: 1.2, minSessionCap: 40, absoluteMaxSession: 150, weeklyGrowthFactor: 1.25, minWeeklyCap: 80,
              minSession: 20, pauseSessionCap: 30, pauseAfterDays: 10, maxSessionsPerWeek: 4, macroGrowthFactor: 1.1, amountStep: 5 },
    startingLevel: { factors: { regular: 1, short_break: 0.7, long_break: 0.5 }, returnGrowthFactor: 1.2 },
    typicalSpeedMetersPerSecond: 3.5,   // gleich typical_speed_meters_per_second
    stepMeasures: ["duration", "distance"],
    distanceStepMeters: 250, minStepMeters: 250, maxStepMeters: 20_000,
    minStepSeconds: 30, maxStepSeconds: 2 * 3600,
    targetRange,                        // erlaubter Bereich je Ziel, null wenn es für den Athleten nicht passt
    testSessions: TEST_SESSIONS,        // Schritte je Leistungstest
    equipment: {},
    promptRules: `- …`                  // Regeln für Claude, je Zeile "- "
  }
};
```

- **`limits`**: die Sicherheitsgrenzen in `limitUnit` (Bedeutung jedes Felds in `types.ts`, die Werte der drei
  Triathlon-Sportarten in [`multisport-planning.md`](multisport-planning.md#grenzen-je-sportart)). Startwerte aus dem
  Trainingswissen, im Betatest justieren.
- **`startingLevel`**: wie viel eines selbst angegebenen Startniveaus gilt (je Trainingsstand ein Anteil von 0 bis 1;
  0 heißt, die Angabe zählt nicht) und wie schnell der Gesamtplan bis zum Niveau vor einer Pause steigen darf
  (mindestens `macroGrowthFactor`, höchstens 1,5). Werte der drei Triathlon-Sportarten in
  [`multisport-planning.md`](multisport-planning.md#selbst-angegebenes-startniveau).
- **`targetRange`**: `perceived_effort` immer 1 bis 10; `heart_rate_zone` nur über `zoneRange(context, target)`, also
  nur, wenn die App Zonen gerechnet hat; Ziele außerhalb von `targets` geben `null`. Bausteine in `modules/shared.ts`.
- **`testSessions`**: je Leistungstest die Schritte. Sie beginnen und enden locker (Anstrengung höchstens 3), die
  Testbelastung hat bei Vollbelastung eine Anstrengung ab 9 und dauert mindestens `durationMinutes`, der Kurztext
  (`cue`) hat höchstens 30 Zeichen, Strecken liegen im Raster `distanceStepMeters`.
- **`promptRules`**: wie Claude die Sportart plant, auf Deutsch, ohne Datum und ohne Zahlen des Athleten.

## 6. Server-Registry: `backend/src/sports/registry.ts`

```ts
import { rowing } from "./modules/rowing";
…
export const SPORTS = new SportRegistry([swim, bike, run, rowing]);
```

## 7. Server-Tests: `backend/test/sports/<id>.test.ts`

Wieder nur die eigene Logik, etwa die Bereiche von `targetRange` und die Länge der Testeinheit. Für jede Sportart in
`SPORTS` laufen von selbst `conformance.test.ts`, `modules.test.ts` (Zielbereiche, Testeinheiten durch die
Sicherheitsschicht), `contracts.test.ts` (gleich Vertrag), `lint.test.ts` und die Zufallstests der Planung. Für
`src/sports/` gilt eine Coverage-Schwelle von 90 %.

## 8. README

Eine Zeile in der Tabelle [Sportarten](../README.md#sportarten).

## Prüfen

```bash
cd backend && npm run typecheck && npm test   # Server, lokal
git status                                    # nur die acht Dateien oben
```

Die App-Tests laufen in der CI (Push auf einen `claude/**`-Branch oder ein PR) oder auf einem Mac mit
`bundle exec fastlane test`: Package-Tests, Sport-Coverage und die Builds von App und Watch.

## Ausliefern

1. **Erst den Server** mit dem neuen Stand deployen ([`backend-deploy.md`](backend-deploy.md)). Ein Server, der die
   Sportart nicht kennt, lehnt jeden Snapshot ab, in dem sie vorkommt (etwa weil Health eine Einheit davon hat), und
   die App bekäme gar keinen Plan mehr.
2. **Dann die App** über `main` (TestFlight). Bringt das Modul neue Health-Typen mit, fragt die App beim nächsten Start
   nach der Freigabe.
3. Im Ziel die Sportart als Disziplin oder mit Schwerpunkt wählen, sonst plant der Server sie nicht ein.

Danach erscheint sie überall: Ziel und Schwerpunkte, Heute und Plan (auch beim Tauschen der Sportart), Gesamtplan mit
Testterminen, Watch mit den Orten aus `recording`, Leistungsprofil, Verlauf und zwei neue Kacheln am Ende des
Dashboards.

## Die Probe

Rudern wurde in [PR #42](https://github.com/Colibri75/SwimInstructor/pull/42) nach dieser Anleitung als echtes Modul
angelegt (Commit "Probe: Rudern als echtes Modul"): Es änderten sich genau die acht Dateien oben, alle Tests und die
Builds von App und Watch liefen grün. Danach wurde die Probe wieder herausgenommen, weil Rudern nicht zum Triathlon-Ziel
gehört. Wer Rudern wirklich haben will, nimmt den Revert-Commit zurück.

Die erfundene Test-Sportart `RowingTestModule` (Swift) und `rowingTestSport` (Jest) bleibt davon unberührt: Sie prüft
mit anderer Logik als die echten Sportarten, dass der Kern allgemein bleibt. Gibt es Rudern als echtes Modul, laufen die
allgemeinen Prüfungen mit diesem.
