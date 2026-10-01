import XCTest
@testable import SwimInstructorCore

final class OwnedEquipmentTests: XCTestCase {
    private func makeStore() -> (UserDefaultsOwnedEquipmentStore, UserDefaults) {
        let suite = "OwnedEquipmentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserDefaultsOwnedEquipmentStore(defaults: defaults), defaults)
    }

    func testNothingChosenYetMeansEverything() {
        let (store, _) = makeStore()

        XCTAssertEqual(store.ownedEquipment(), ["pull_buoy", "paddles", "fins", "snorkel", "kickboard", "ankle_band"])
    }

    func testTheChoiceIsStoredInAFixedOrder() {
        let (store, _) = makeStore()

        store.setOwnedEquipment([.kickboard, .pullBuoy])

        XCTAssertEqual(store.ownedEquipment(), ["pull_buoy", "kickboard"])
    }

    func testAnEmptyChoiceMeansNoEquipmentAndIsNotMistakenForUnset() {
        let (store, _) = makeStore()

        store.setOwnedEquipment([])

        XCTAssertEqual(store.ownedEquipment(), [])
    }

    func testUnknownStoredValuesAreIgnored() {
        let (store, defaults) = makeStore()
        defaults.set(["fins", "jetpack"], forKey: UserDefaultsOwnedEquipmentStore.storageKey)

        XCTAssertEqual(store.ownedEquipment(), ["fins"])
    }

    func testRawValuesMatchTheServerAndTitlesAreGerman() {
        XCTAssertEqual(EquipmentItem.allCases.map(\.rawValue), ["pull_buoy", "paddles", "fins", "snorkel", "kickboard", "ankle_band"])
        XCTAssertEqual(EquipmentItem.ankleBand.title, "Beinband")
        XCTAssertEqual(EquipmentItem.fins.title, "Flossen")
    }
}
