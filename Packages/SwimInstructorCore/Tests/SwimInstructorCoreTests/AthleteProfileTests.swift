import XCTest
@testable import SwimInstructorCore

final class AthleteProfileTests: XCTestCase {
    private func storedContractProfile() throws -> AthleteProfile {
        try JSONDecoder().decode(AthleteProfile.self, from: RepoPaths.contractData("app-storage/athlete-profile.json"))
    }

    // MARK: - Was zum Server geht

    func testContractProfileBecomesTheWireProfile() throws {
        let profile = try storedContractProfile()
        let wire = try AthleteStateSnapshot.jsonDecoder().decode(
            AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2-athlete-profile.json")
        )
        // Health kennt das Alter (52), das Geburtsjahr unter "Über mich" zählt dann nicht.
        let age = profile.age(healthAge: 52, now: TestFixtures.now, calendar: TestFixtures.utc)
        XCTAssertEqual(profile.snapshotProfile(age: age, sports: [.swim, .bike, .run]), wire.athleteProfile)
    }

    func testSnapshotV2WithAthleteProfileRoundTripsWithoutLosingFields() throws {
        let data = try RepoPaths.contractData("wire/snapshot-v2-athlete-profile.json")
        let snapshot = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: data)
        let reencoded = try AthleteStateSnapshot.jsonEncoder().encode(snapshot)

        XCTAssertEqual(try JSONKeyPaths.of(reencoded), try JSONKeyPaths.of(data))
        let plain = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2.json"))
        XCTAssertEqual(snapshot.withAthleteProfile(nil), plain)
        XCTAssertEqual(plain.withAthleteProfile(snapshot.athleteProfile), snapshot)
    }

    func testAgeComesFromHealthElseFromTheBirthYear() {
        let profile = AthleteProfile(birthYear: 1980)
        XCTAssertEqual(profile.age(healthAge: 44, now: TestFixtures.now, calendar: TestFixtures.utc), 44)
        XCTAssertEqual(profile.age(healthAge: nil, now: TestFixtures.now, calendar: TestFixtures.utc), 46)
        XCTAssertNil(AthleteProfile().age(healthAge: nil, now: TestFixtures.now, calendar: TestFixtures.utc))
        XCTAssertNil(AthleteProfile(birthYear: 2024).age(healthAge: nil, now: TestFixtures.now, calendar: TestFixtures.utc), "unter 10 Jahren keine Angabe")
    }

    func testEmptyProfileSendsNothing() {
        XCTAssertNil(AthleteProfile.empty.snapshotProfile(age: nil, sports: [.swim, .run]))
        // Eine Sportart ohne Angaben fällt weg, wie leere Fähigkeiten (keine Angabe).
        let profile = AthleteProfile(sports: [AthleteProfile.SportPreferences(sport: .swim, skills: [])])
        XCTAssertNil(profile.snapshotProfile(age: nil, sports: [.swim]))
    }

    func testOnlyWhatTheModuleKnowsGoesToTheServer() throws {
        let profile = AthleteProfile(sports: [
            AthleteProfile.SportPreferences(sport: .swim, skills: ["butterfly", "unknown", "freestyle"], lapLengthMeters: 33, poolWeekdays: [1, 2, 3, 4, 5, 6, 7]),
            AthleteProfile.SportPreferences(sport: .bike, skills: ["freestyle"], longSessionWeekday: 6, lapLengthMeters: 25, poolWeekdays: [2]),
            AthleteProfile.SportPreferences(sport: .run, longSessionWeekday: 9)
        ])
        let summary = try XCTUnwrap(profile.snapshotProfile(age: nil, sports: [.swim, .bike, .run]))
        let sports = try XCTUnwrap(summary.sports)

        // Schwimmen: Reihenfolge des Moduls, keine fremde Bahnlänge, jeder Tag heißt ohne Angabe.
        XCTAssertEqual(sports.map(\.sport), [.swim, .bike])
        XCTAssertEqual(sports[0].skills, ["freestyle", "butterfly"])
        XCTAssertNil(sports[0].lapLengthMeters)
        XCTAssertNil(sports[0].poolWeekdays)
        // Rad kennt weder Fähigkeiten noch eine Bahn, nur den langen Tag; Laufen hat keinen gültigen Tag.
        XCTAssertNil(sports[1].skills)
        XCTAssertNil(sports[1].lapLengthMeters)
        XCTAssertNil(sports[1].poolWeekdays)
        XCTAssertEqual(sports[1].longSessionWeekday, 6)
    }

    func testSportsOutsideTheSnapshotAreLeftOut() {
        let profile = AthleteProfile(sports: [AthleteProfile.SportPreferences(sport: .run, longSessionWeekday: 7)])
        XCTAssertNil(profile.snapshotProfile(age: nil, sports: [.swim]))
    }

    // MARK: - Bearbeiten und Speichern

    func testEditingKeepsInjuriesInBodyOrderAndDropsEmptySports() {
        var profile = AthleteProfile()
        profile.setInjury(.past, at: .shoulder)
        profile.setInjury(.current, at: .knee)
        profile.setInjury(.recurring, at: .shoulder)
        XCTAssertEqual(profile.injuries, [.init(area: .knee, status: .current), .init(area: .shoulder, status: .recurring)])
        profile.setInjury(nil, at: .knee)
        XCTAssertEqual(profile.injuryStatus(at: .knee), nil)

        profile.setPreferences(.init(sport: .run, longSessionWeekday: 7))
        XCTAssertEqual(profile.preferences(for: .run).longSessionWeekday, 7)
        profile.setPreferences(.init(sport: .run))
        XCTAssertTrue(profile.sports.isEmpty)
    }

    func testStoredProfileLoadsAndRoundTrips() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AthleteProfileTests-\(UUID().uuidString)"))
        let store = UserDefaultsAthleteProfileStore(defaults: defaults)
        XCTAssertEqual(store.profile(), .empty)

        defaults.set(try RepoPaths.contractData("app-storage/athlete-profile.json"), forKey: UserDefaultsAthleteProfileStore.storageKey)
        let stored = store.profile()
        XCTAssertEqual(stored.birthYear, 1974)
        XCTAssertEqual(stored.injuryStatus(at: .achilles), .recurring)
        XCTAssertEqual(stored.preferences(for: .swim).poolWeekdays, [1, 3, 5])
        XCTAssertTrue(stored.shiftWork)

        var changed = stored
        changed.intensityPreference = .intense
        store.save(changed)
        XCTAssertEqual(store.profile(), changed)
    }

    func testMissingFieldsDecodeToDefaults() throws {
        let profile = try JSONDecoder().decode(AthleteProfile.self, from: Data(#"{"trainingYears":3}"#.utf8))
        XCTAssertEqual(profile, AthleteProfile(trainingYears: 3))
    }

    // MARK: - Snapshot

    func testBuilderSendsTheProfileWithAgeFromHealth() async throws {
        let goal = GoalTemplate.template(id: "triathlon_olympic")!
            .goal(targetDate: AthleteGoal.default.targetDate, trainingDaysPerWeek: 5, weeklyHours: 7)
        let profile = AthleteProfile(birthYear: 1990, trainingYears: 2, lifeStress: .high)
        let builder = SnapshotBuilder(
            repository: FakeAllSportsRepository(workouts: []),
            vitalsRepository: FakeVitalsRepository(),
            trainingGoalProvider: { goal },
            performanceRepository: FakePerformanceRepository(age: 41),
            athleteProfileProvider: { profile },
            calendar: TestFixtures.utc
        )

        let snapshot = try await builder.build(now: TestFixtures.now).snapshot

        XCTAssertEqual(snapshot.athleteProfile?.age, 41)
        XCTAssertEqual(snapshot.athleteProfile?.trainingYears, 2)
        XCTAssertEqual(snapshot.athleteProfile?.lifeStress, .high)
        XCTAssertNil(snapshot.athleteProfile?.shiftWork)
    }

    func testSwimModuleOffersPoolAndSkills() throws {
        let swim = try XCTUnwrap(SportRegistry.standard.module(for: .swim))
        XCTAssertEqual(swim.pool?.lapLengths, [25, 50])
        XCTAssertEqual(swim.skills.map(\.id), ["freestyle", "breaststroke", "backstroke", "butterfly", "flip_turn"])
        XCTAssertNil(SportRegistry.standard.module(for: .run)?.pool)
        XCTAssertTrue(SportRegistry.standard.module(for: .bike)?.skills.isEmpty == true)
    }
}
