import Foundation

// Checks the goal-derivation migration and the content de-duplication against a real
// exported backup, so the behaviour is confirmed on the user's own history rather than
// on invented fixtures.
//
//   verify <backup.json>

/// The scores the app displayed before the change, read straight from the raw JSON.
private struct RawGoal: Decodable { let team: TeamSide }
private struct RawMatch: Decodable { let goals: [RawGoal]; let awayTeamName: String }
private struct RawSaved: Decodable { let id: UUID; let match: RawMatch }

private func pad(_ name: String) -> String {
    name.padding(toLength: 24, withPad: " ", startingAt: 0)
}

@main
enum Verify {
    static func main() throws {
        guard let path = CommandLine.arguments.dropFirst().first,
              let data = FileManager.default.contents(atPath: path) else {
            FileHandle.standardError.write(Data("usage: verify <backup.json>\n".utf8))
            exit(2)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let saved = try decoder.decode([SavedMatch].self, from: data)
        let raw = try decoder.decode([RawSaved].self, from: data)
        let legacyScores = Dictionary(uniqueKeysWithValues: raw.map { entry in
            (
                entry.id,
                (
                    home: entry.match.goals.filter { $0.team == .home }.count,
                    away: entry.match.goals.filter { $0.team == .away }.count
                )
            )
        })

        print("=== score preserved through migration ===")
        var mismatches = 0
        for entry in saved {
            let derived = (home: entry.match.score(for: .home), away: entry.match.score(for: .away))
            let legacy = legacyScores[entry.id] ?? (home: -1, away: -1)
            let agrees = derived == legacy
            if !agrees { mismatches += 1 }
            let note = agrees ? "ok" : "CHANGED from \(legacy.home)-\(legacy.away)"
            print("  \(pad(entry.match.awayTeamName)) \(derived.home)-\(derived.away)  shots \(entry.match.shots.count)  \(note)")
        }
        print("  mismatches: \(mismatches)")

        print("\n=== goals now always agree with goal-outcome shots ===")
        for entry in saved {
            let goalShots = entry.match.shots.filter { $0.outcome == .goal }.count
            let flag = goalShots == entry.match.goals.count ? "ok" : "MISMATCH"
            print("  \(pad(entry.match.awayTeamName)) goals \(entry.match.goals.count)  goalShots \(goalShots)  \(flag)")
        }

        print("\n=== de-duplication ===")
        let deduped = MatchHistoryBackup.deduplicated(saved)
        print("  \(saved.count) records in file -> \(deduped.count) after de-duplication")
        for id in Set(saved.map(\.id)).subtracting(deduped.map(\.id)) {
            if let entry = saved.first(where: { $0.id == id }) {
                print("  dropped \(entry.match.awayTeamName) saved \(entry.savedAt)")
            }
        }

        print("\n=== goal ids are stable across reads ===")
        if let first = saved.first {
            let repeated = first.match.goals.map(\.id) == first.match.goals.map(\.id)
            print("  \(first.match.awayTeamName): \(repeated ? "stable" : "UNSTABLE")")
        }

        print("\n=== encode omits goals, round-trips cleanly ===")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let reEncoded = try encoder.encode(deduped)
        let text = String(decoding: reEncoded, as: UTF8.self)
        print("  \"goals\" key present in output: \(text.contains("\"goals\""))")

        let roundTripped = try decoder.decode([SavedMatch].self, from: reEncoded)
        let survives = zip(deduped, roundTripped).allSatisfy {
            $0.match.score(for: .home) == $1.match.score(for: .home)
                && $0.match.score(for: .away) == $1.match.score(for: .away)
                && $0.match.shots.count == $1.match.shots.count
        }
        print("  scores and shot counts survive a re-decode: \(survives)")
    }
}
