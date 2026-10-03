import Foundation

/// Zugriff auf `contracts/` im Repo und auf die Quelltexte für den Lint-Test. Die Pfade ergeben sich aus der
/// Lage dieser Datei; `swift test` läuft (lokal wie in der CI) immer im ausgecheckten Repo.
enum RepoPaths {
    /// `Packages/SwimInstructorCore/Tests/SwimInstructorCoreTests/` → Repo-Wurzel.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SwimInstructorCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SwimInstructorCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()

    static let contracts = root.appendingPathComponent("contracts")
    static let packageSources = root.appendingPathComponent("Packages/SwimInstructorCore/Sources/SwimInstructorCore")

    static func contract(_ path: String) -> URL {
        contracts.appendingPathComponent(path)
    }

    static func contractData(_ path: String) throws -> Data {
        try Data(contentsOf: contract(path))
    }

    /// Alle `.swift`-Dateien unter `directory`, rekursiv.
    static func swiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

/// Alle Schlüsselpfade eines JSON-Werts, z. B. `goal.distance_meters` oder `plan.sets[].cue`.
enum JSONKeyPaths {
    static func of(_ data: Data) throws -> Set<String> {
        collect(try JSONSerialization.jsonObject(with: data), prefix: "")
    }

    private static func collect(_ value: Any, prefix: String) -> Set<String> {
        if let object = value as? [String: Any] {
            var paths = Set<String>()
            for (key, child) in object {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                paths.insert(path)
                paths.formUnion(collect(child, prefix: path))
            }
            return paths
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(collect($1, prefix: "\(prefix)[]")) }
        }
        return []
    }
}
