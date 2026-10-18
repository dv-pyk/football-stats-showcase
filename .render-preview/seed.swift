import Foundation

// Seeds the App Group's activeMatch.json from a real backup match so the live screen can
// be exercised in the simulator. Optionally appends a fresh possession change to trigger
// the intercept affordance.
//
//   seed <backup.json> <out activeMatch.json> <revision> [--possession-change]

private struct PersistedActiveMatch: Codable {
    var match: MatchState
    var savedAt: Date
    var revision: UInt64
}

@main
enum Seed {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 3, let data = FileManager.default.contents(atPath: args[0]) else {
            FileHandle.standardError.write(Data("usage: seed <backup.json> <out> <revision> [--possession-change]\n".utf8))
            exit(2)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode([SavedMatch].self, from: data)

        guard var match = saved.first?.match else {
            FileHandle.standardError.write(Data("no match in backup\n".utf8))
            exit(1)
        }

        match.isRunning = true
        match.kickoffDate = Date().addingTimeInterval(-TimeInterval(match.elapsedSeconds))
        match.currentPossession = .away
        match.possessionBaseline = .away
        match.possessionBaselineSeconds = match.elapsedSeconds

        if args.contains("--possession-change") {
            match.passes.append(PassEvent(type: .possessionToHome, matchSeconds: match.elapsedSeconds))
        }

        let persisted = PersistedActiveMatch(
            match: match,
            savedAt: Date(),
            revision: UInt64(args[2]) ?? 1
        )

        // The app's ActiveMatchStore uses a plain JSONEncoder (deferredToDate), so match that.
        try JSONEncoder().encode(persisted).write(to: URL(fileURLWithPath: args[1]), options: .atomic)
        print("seeded revision \(args[2]) elapsed=\(match.elapsedSeconds) passes=\(match.passes.count)")
    }
}
