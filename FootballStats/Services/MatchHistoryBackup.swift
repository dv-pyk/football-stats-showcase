import Foundation

enum MatchHistoryBackup {
    static let fileName = "match_history.json"

    static var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static func loadMatches() -> [SavedMatch] {
        deduplicated(decode(from: localURL) ?? [])
    }

    static func saveMatches(_ matches: [SavedMatch]) {
        guard let data = encode(matches) else { return }
        try? data.write(to: localURL, options: .atomic)
    }

    /// A portable backup bundles match history together with team rosters (including
    /// avatar photo bytes) into one shareable file. Day to day, rosters live in their own
    /// local store (`RosterStore`/`rosters.json`) — this wrapper only exists for the
    /// export/import round-trip, so a backup stays a single self-contained file.
    private struct Payload: Codable {
        var matches: [SavedMatch]
        var rosters: [BackupTeamRoster]
    }

    static func makeExportFile(matches: [SavedMatch], rosters: [BackupTeamRoster]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Payload(matches: matches, rosters: rosters)) else {
            throw MatchHistoryBackupError.encodingFailed
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStamp = formatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Football-Stats-Backup-\(dateStamp).json")

        try data.write(to: url, options: .atomic)
        return url
    }

    /// Backups written before app 1.7 are a bare JSON array of matches, no roster data at
    /// all — those still decode fine here, just with an empty roster list, rather than
    /// being rejected as invalid.
    static func importPayload(from url: URL) throws -> (matches: [SavedMatch], rosters: [BackupTeamRoster]) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let payload = try? decoder.decode(Payload.self, from: data) {
            return (payload.matches, payload.rosters)
        }
        if let matches = try? decoder.decode([SavedMatch].self, from: data) {
            return (matches, [])
        }
        throw MatchHistoryBackupError.invalidBackup
    }

    static func merge(existing: [SavedMatch], imported: [SavedMatch]) -> [SavedMatch] {
        var byID: [UUID: SavedMatch] = [:]

        for match in existing + imported {
            if let current = byID[match.id] {
                byID[match.id] = match.savedAt > current.savedAt ? match : current
            } else {
                byID[match.id] = match
            }
        }

        return deduplicated(byID.values.sorted { $0.savedAt > $1.savedAt })
    }

    /// The same fixture can end up saved twice under different identifiers, which then
    /// survives id-based merging and double-counts in history. Two records describing
    /// the same teams, kickoff and event totals are the same recording, so keep the
    /// most recently saved one.
    private struct MatchFingerprint: Hashable {
        let homeTeamName: String
        let awayTeamName: String
        let kickoffDate: Date
        let elapsedSeconds: Int
        let shotCount: Int
        let passCount: Int

        init(_ match: MatchState) {
            homeTeamName = match.homeTeamName
            awayTeamName = match.awayTeamName
            kickoffDate = match.kickoffDate
            elapsedSeconds = match.elapsedSeconds
            shotCount = match.shots.count
            passCount = match.passes.count
        }
    }

    static func deduplicated(_ matches: [SavedMatch]) -> [SavedMatch] {
        var seen: Set<MatchFingerprint> = []

        return matches
            .sorted { $0.savedAt > $1.savedAt }
            .filter { seen.insert(MatchFingerprint($0.match)).inserted }
    }

    private static func encode(_ matches: [SavedMatch]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(matches)
    }

    private static func decode(from url: URL) -> [SavedMatch]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([SavedMatch].self, from: data)
    }
}

enum MatchHistoryBackupError: LocalizedError {
    case encodingFailed
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Could not create a backup file."
        case .invalidBackup:
            "That file is not a valid Football Stats backup."
        }
    }
}
