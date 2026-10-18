import Foundation

extension Notification.Name {
    static let activeMatchDidUpdateExternally = Notification.Name("activeMatchDidUpdateExternally")
}

private struct PersistedActiveMatch: Codable {
    var match: MatchState
    var savedAt: Date
    var revision: UInt64
}

enum ActiveMatchActionResult {
    case success
    case noActiveMatch
    case noPossession
    case actionUnavailable
}

final class ActiveMatchStore {
    static let shared = ActiveMatchStore()
    static let appGroupID = "group.com.footballstats.app"

    private let fileName = "activeMatch.json"
    private let legacyFileName = "activeMatch.json"

    /// Opening `UserDefaults(suiteName:)` for the App Group triggers a harmless but noisy
    /// CFPrefs warning on launch ("Using kCFPreferencesAnyUser with a container…"). The
    /// match already lives as JSON in the group container with its revision inside, so
    /// there is nothing left for shared defaults to do.
    private var storageDirectory: URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) {
            return groupURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var storeURL: URL {
        storageDirectory.appendingPathComponent(fileName)
    }

    private var revisionCounter: UInt64 = 0

    private init() {
        migrateLegacyStoreIfNeeded()
        revisionCounter = peekPersisted()?.revision ?? 0
    }

    var latestRevision: UInt64 {
        max(revisionCounter, peekPersisted()?.revision ?? 0)
    }

    func save(_ match: MatchState) {
        revisionCounter += 1
        let persisted = PersistedActiveMatch(
            match: match,
            savedAt: Date(),
            revision: revisionCounter
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    @discardableResult
    func saveFromApp(_ match: MatchState, acknowledgedRevision: UInt64) -> Bool {
        let diskRevision = peekPersisted()?.revision ?? 0
        if diskRevision > acknowledgedRevision {
            return false
        }
        save(match)
        return true
    }

    func load() -> MatchState? {
        guard var persisted = peekPersisted() else { return nil }

        revisionCounter = max(revisionCounter, persisted.revision)

        if persisted.match.isRunning {
            let elapsed = Int(Date().timeIntervalSince(persisted.savedAt))
            if elapsed > 0 {
                persisted.match.elapsedSeconds += elapsed
                persisted.savedAt = Date()
                save(persisted.match)
            }
        }

        return persisted.match
    }

    func clear() {
        try? FileManager.default.removeItem(at: storeURL)
        revisionCounter = 0
    }

    func recordPass() -> ActiveMatchActionResult {
        guard var match = load() else { return .noActiveMatch }
        guard MatchEventProcessor.recordPass(in: &match) else {
            return .actionUnavailable
        }
        save(match)
        ActiveMatchCrossProcessNotifier.post()
        return .success
    }

    func recordBallOut() -> ActiveMatchActionResult {
        guard var match = load() else { return .noActiveMatch }
        guard MatchEventProcessor.recordBallOut(in: &match) else {
            return .actionUnavailable
        }
        save(match)
        ActiveMatchCrossProcessNotifier.post()
        return .success
    }

    func recordPossessionChange() -> ActiveMatchActionResult {
        guard var match = load() else { return .noActiveMatch }
        guard MatchEventProcessor.recordPossessionChange(in: &match) else {
            return .actionUnavailable
        }
        save(match)
        ActiveMatchCrossProcessNotifier.post()
        return .success
    }

    private func peekPersisted() -> PersistedActiveMatch? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }

        if let persisted = try? JSONDecoder().decode(PersistedActiveMatch.self, from: data) {
            return persisted
        }

        struct LegacyPersistedActiveMatch: Codable {
            var match: MatchState
            var savedAt: Date
        }

        guard let legacy = try? JSONDecoder().decode(LegacyPersistedActiveMatch.self, from: data) else {
            return nil
        }

        return PersistedActiveMatch(match: legacy.match, savedAt: legacy.savedAt, revision: 0)
    }

    private func migrateLegacyStoreIfNeeded() {
        guard !FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let legacyURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(legacyFileName)
        guard let legacyData = try? Data(contentsOf: legacyURL) else { return }

        try? legacyData.write(to: storeURL, options: .atomic)
    }
}
