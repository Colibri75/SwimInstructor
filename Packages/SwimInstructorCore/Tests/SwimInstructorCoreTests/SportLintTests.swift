import XCTest

/// Sorgt dafür, dass außerhalb der Sport-Module niemand nach einer bestimmten Sportart verzweigt. Sonst wäre
/// eine neue Sportart wieder eine Änderung quer durch den Code statt ein neues Modul.
///
/// Erlaubt ist das nur unter `Sports/` im Package (Module, Registry, später die Umstellung alter Daten).
final class SportLintTests: XCTestCase {
    private static let forbidden: [(pattern: String, why: String)] = [
        (#"SportID\.(swim|bike|run)\b"#, "feste Sportart"),
        (#"case\s+\.(swim|bike|run)\b"#, "switch über Sportarten"),
        (#"[=!]=\s*\.(swim|bike|run)\b"#, "Vergleich mit fester Sportart"),
        (#""(swim|bike|run)""#, "Sport-Kennung als Text")
    ]

    func testNoSportSpecificBranchingOutsideModules() throws {
        let checkedDirectories = [
            RepoPaths.packageSources,
            RepoPaths.root.appendingPathComponent("App"),
            RepoPaths.root.appendingPathComponent("WatchApp")
        ]
        let allowed = RepoPaths.packageSources.appendingPathComponent("Sports").standardizedFileURL.path + "/"
        let expressions = try Self.forbidden.map { (try NSRegularExpression(pattern: $0.pattern), $0.why) }

        var checkedFiles = 0
        var violations: [String] = []
        for directory in checkedDirectories {
            for file in RepoPaths.swiftFiles(in: directory) where !file.standardizedFileURL.path.hasPrefix(allowed) {
                checkedFiles += 1
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    let range = NSRange(line.startIndex..., in: line)
                    for (expression, why) in expressions where expression.firstMatch(in: line, range: range) != nil {
                        violations.append("\(file.lastPathComponent):\(index + 1) \(why): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }

        XCTAssertGreaterThan(checkedFiles, 20, "Lint hat die Quelltexte nicht gefunden")
        XCTAssertTrue(violations.isEmpty, "Sportart-Logik gehört in ein Modul unter Sports/:\n" + violations.joined(separator: "\n"))
    }

    func testLintCatchesWhatItShould() throws {
        let expressions = try Self.forbidden.map { try NSRegularExpression(pattern: $0.pattern) }
        func flagged(_ line: String) -> Bool {
            expressions.contains { $0.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
        }
        XCTAssertTrue(flagged("if workout.sport == .run {"))
        XCTAssertTrue(flagged("case .swim: return 50"))
        XCTAssertTrue(flagged("let sport = SportID.bike"))
        XCTAssertTrue(flagged(#"let id = "bike""#))
        XCTAssertFalse(flagged(#"Label("Heute", systemImage: "figure.pool.swim")"#))
        XCTAssertFalse(flagged("case .swimming: break"))
        XCTAssertFalse(flagged("let running = true"))
    }
}
