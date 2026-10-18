import Foundation

@MainActor
final class MatchHistoryStore: ObservableObject {
    @Published private(set) var matches: [SavedMatch] = []
    @Published var lastBackupMessage: String?

    init() {
        load()
    }

    func save(_ match: MatchState) {
        guard match.hasRecordableContent else { return }

        let saved = SavedMatch(match: match)
        matches.insert(saved, at: 0)
        persist()
    }

    func updateMatch(id: UUID, match: MatchState) {
        guard let index = matches.firstIndex(where: { $0.id == id }) else { return }
        var updated = matches[index]
        var storedMatch = match
        storedMatch.isRunning = false
        updated.match = storedMatch
        matches[index] = updated
        persist()
    }

    func delete(_ match: SavedMatch) {
        matches.removeAll { $0.id == match.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        matches.remove(atOffsets: offsets)
        persist()
    }

    func makeExportFile(rosters: [BackupTeamRoster]) throws -> URL {
        try MatchHistoryBackup.makeExportFile(matches: matches, rosters: rosters)
    }

    /// Returns the backup's roster payload so the caller (`MatchHistoryView`, which holds
    /// both this store and `RosterStore`) can merge it in — this store only owns matches,
    /// not rosters.
    @discardableResult
    func importBackup(from url: URL) throws -> [BackupTeamRoster] {
        let (imported, rosters) = try MatchHistoryBackup.importPayload(from: url)
        let existingIDs = Set(matches.map(\.id))
        let merged = MatchHistoryBackup.merge(existing: matches, imported: imported)

        // Merging can now shrink the list, since re-saves of one fixture collapse
        // together, so the arrival count can't be inferred from the length alone.
        let addedCount = merged.filter { !existingIDs.contains($0.id) }.count
        let collapsedCount = max(0, matches.count + addedCount - merged.count)

        matches = merged
        persist()
        lastBackupMessage = Self.importMessage(added: addedCount, collapsed: collapsedCount)
        return rosters
    }

    private static func importMessage(added: Int, collapsed: Int) -> String {
        let duplicates = collapsed > 0
            ? " Merged \(collapsed) duplicate\(collapsed == 1 ? "" : "s")."
            : ""

        guard added > 0 else {
            return collapsed > 0
                ? "No new matches.\(duplicates)"
                : "Backup loaded. No new matches were added."
        }

        return "Imported \(added) match\(added == 1 ? "" : "es").\(duplicates)"
    }

    private func load() {
        matches = MatchHistoryBackup.loadMatches()
    }

    private func persist() {
        MatchHistoryBackup.saveMatches(matches)
    }
}
