import XCTest
@testable import SwimInstructorCore

/// Erfundene Sportart nur für Tests, mit anderer Logik als die drei echten: geplant nach Zeit, Intensität nach
/// Schlagzahl. Läuft durch dieselben Prüfungen wie Schwimmen, Rad und Laufen. Bricht sie, ist der Kern nicht
/// mehr allgemein genug für weitere Sportarten.
struct RowingTestModule: SportModule {
    let id: SportID = "rowing"
    let displayName = "Rudern"
    let symbolName = "figure.rower"
    let measures: Set<StepMeasure> = [.duration, .distance]
    let targets: Set<StepTarget> = [.strokeRate, .power, .heartRateZone]
}

/// Prüfungen, die jedes Modul bestehen muss. Jeder Umbauschritt hängt hier seine neuen Anforderungen an
/// (Health-Umwandlung, Belastung, Fortschritt, Statistik); sie gelten dann automatisch für jede Sportart.
final class SportModuleConformanceTests: XCTestCase {
    /// Die echten Module plus die Test-Sportart.
    private var allModules: [any SportModule] {
        SportRegistry.standard.modules + [RowingTestModule() as any SportModule]
    }

    func testEveryModuleIsCompleteAndRegistrable() throws {
        let registry = try SportRegistry(modules: allModules)
        XCTAssertEqual(registry.ids.count, SportRegistry.standard.ids.count + 1)
        for module in allModules {
            XCTAssertTrue(module.id.isWellFormed, "\(module.id)")
            XCTAssertFalse(module.displayName.isEmpty, "\(module.id)")
            XCTAssertFalse(module.symbolName.isEmpty, "\(module.id)")
            XCTAssertFalse(module.measures.isEmpty, "\(module.id)")
            XCTAssertFalse(module.targets.isEmpty, "\(module.id): ohne Ziel kann kein Schritt eine Intensität vorgeben")
        }
    }

    func testEveryModuleCanBePlannedWithoutTargetAndWithEachOfItsTargets() {
        for module in allModules {
            for measure in module.measures {
                XCTAssertTrue(module.supports(measure: measure, target: nil), "\(module.id) \(measure)")
                for target in module.targets {
                    XCTAssertTrue(module.supports(measure: measure, target: target), "\(module.id) \(measure) \(target)")
                }
            }
        }
    }

    func testEveryModuleIsFoundByItsID() throws {
        let registry = try SportRegistry(modules: allModules)
        for module in allModules {
            XCTAssertEqual(registry.module(for: module.id)?.displayName, module.displayName)
        }
    }

    func testTestSportReallyHasItsOwnLogic() {
        // Rudern plant nach Schlagzahl, was keine der echten Sportarten kann: Der Test beweist nur dann etwas,
        // wenn die Test-Sportart nicht bloß eine Kopie einer echten ist.
        XCTAssertTrue(RowingTestModule().targets.contains(.strokeRate))
        XCTAssertFalse(SportRegistry.standard.modules.contains { $0.targets.contains(.strokeRate) })
    }
}
