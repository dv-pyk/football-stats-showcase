import Foundation
import UIKit

/// Persists team rosters (`RosterModels.swift`) as a small JSON file, mirroring
/// `MatchHistoryStore`/`MatchHistoryBackup`'s split — except avatars, which are separate
/// JPEG files on disk (there's no precedent anywhere in this codebase for binary blobs
/// inside a `Codable` model, and keeping them out of the JSON keeps `rosters.json` small).
///
/// Day to day, rosters and avatars live in `Documents` only. `MatchHistoryBackup`'s portable
/// export/import file bundles a self-contained copy of them too (see `backupRosters()` /
/// `mergeFromBackup(_:)` below) — coordinated from `MatchHistoryView`, which already holds
/// both this store and `MatchHistoryStore`.
@MainActor
final class RosterStore: ObservableObject {
    @Published private(set) var rosters: [TeamRoster] = []

    private static let fileName = "rosters.json"
    private static let avatarsDirectoryName = "RosterAvatars"
    private static let avatarDownscaleMigrationKey = "avatarDownscaleV1Completed"
    private static let avatarOutputSize: CGFloat = 300

    init() {
        load()
        downscaleOversizedAvatarsIfNeeded()
    }

    // MARK: - Lookup

    func roster(for teamName: String) -> TeamRoster? {
        rosters.first { $0.teamName == teamName }
    }

    func player(id: UUID, in teamName: String) -> RosterPlayer? {
        roster(for: teamName)?.players.first { $0.id == id }
    }

    /// Same lookup, without needing to know which team's roster the player is on — used by
    /// the pressure chart's credited-row badges, which only carry a player id.
    func player(withID id: UUID) -> RosterPlayer? {
        for roster in rosters {
            if let player = roster.players.first(where: { $0.id == id }) {
                return player
            }
        }
        return nil
    }

    // MARK: - Mutation

    func addOrUpdatePlayer(_ player: RosterPlayer, to teamName: String) {
        if let index = rosters.firstIndex(where: { $0.teamName == teamName }) {
            if let playerIndex = rosters[index].players.firstIndex(where: { $0.id == player.id }) {
                rosters[index].players[playerIndex] = player
            } else {
                rosters[index].players.append(player)
            }
        } else {
            rosters.append(TeamRoster(teamName: teamName, players: [player]))
        }

        if player.isKeeper {
            unsetOtherKeepers(except: player.id, in: teamName)
        }

        persist()
    }

    func deletePlayer(id: UUID, from teamName: String) {
        guard let index = rosters.firstIndex(where: { $0.teamName == teamName }) else { return }
        rosters[index].players.removeAll { $0.id == id }
        deleteAvatar(for: id)
        persist()
    }

    /// Only one player per roster can be the keeper — setting one unsets any other.
    func setKeeper(id: UUID, in teamName: String) {
        guard let index = rosters.firstIndex(where: { $0.teamName == teamName }) else { return }
        for playerIndex in rosters[index].players.indices {
            rosters[index].players[playerIndex].isKeeper = rosters[index].players[playerIndex].id == id
        }
        persist()
    }

    private func unsetOtherKeepers(except id: UUID, in teamName: String) {
        guard let index = rosters.firstIndex(where: { $0.teamName == teamName }) else { return }
        for playerIndex in rosters[index].players.indices where rosters[index].players[playerIndex].id != id {
            rosters[index].players[playerIndex].isKeeper = false
        }
    }

    // MARK: - Avatars

    func avatarImage(for playerID: UUID) -> UIImage? {
        UIImage(contentsOfFile: avatarURL(for: playerID).path)
    }

    func saveAvatar(_ image: UIImage, for playerID: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: Self.avatarsDirectory, withIntermediateDirectories: true)
        try? data.write(to: avatarURL(for: playerID), options: .atomic)
    }

    func deleteAvatar(for playerID: UUID) {
        try? FileManager.default.removeItem(at: avatarURL(for: playerID))
    }

    private func avatarURL(for playerID: UUID) -> URL {
        Self.avatarsDirectory.appendingPathComponent("\(playerID.uuidString).jpg")
    }

    private static var avatarsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(avatarsDirectoryName)
    }

    /// One-time cleanup for avatars saved before `PhotoCropView` pinned its renderer to 1x
    /// scale: those files came out at 3x the intended pixel dimensions (900x900 instead of
    /// 300x300) at 9x the file size, for no visual benefit at thumbnail sizes. Since each
    /// avatar is already a square crop, downsampling in place to the correct size preserves
    /// the exact same composition — no need to re-crop, just re-encode smaller. Guarded by a
    /// UserDefaults flag so this only ever does the work once.
    private func downscaleOversizedAvatarsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.avatarDownscaleMigrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.avatarDownscaleMigrationKey) }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.avatarsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let target = Self.avatarOutputSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)

        for url in files where url.pathExtension.lowercased() == "jpg" {
            guard let image = UIImage(contentsOfFile: url.path),
                  image.size.width > target || image.size.height > target
            else { continue }

            let resized = renderer.image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: target, height: target))
            }
            guard let data = resized.jpegData(compressionQuality: 0.85) else { continue }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Backup

    /// Resolves every player's avatar file into raw bytes, so the whole roster can travel
    /// as one self-contained backup file rather than pointing at photos that only exist on
    /// this device.
    func backupRosters() -> [BackupTeamRoster] {
        rosters.map { roster in
            BackupTeamRoster(
                teamName: roster.teamName,
                players: roster.players.map { player in
                    BackupRosterPlayer(
                        id: player.id,
                        name: player.name,
                        jerseyNumber: player.jerseyNumber,
                        isKeeper: player.isKeeper,
                        avatarData: avatarImage(for: player.id)?.jpegData(compressionQuality: 0.85),
                        initials: player.initials
                    )
                }
            )
        }
    }

    /// Fills in whatever a backup has that this device doesn't — a new team, or a player id
    /// not already on the matching team's roster — without touching anything that already
    /// exists locally, so importing never clobbers an edit made since the backup was taken.
    func mergeFromBackup(_ backupRosters: [BackupTeamRoster]) {
        for backupRoster in backupRosters {
            let existingIDs = Set(roster(for: backupRoster.teamName)?.players.map(\.id) ?? [])

            for backupPlayer in backupRoster.players where !existingIDs.contains(backupPlayer.id) {
                if avatarImage(for: backupPlayer.id) == nil,
                   let data = backupPlayer.avatarData,
                   let image = UIImage(data: data) {
                    saveAvatar(image, for: backupPlayer.id)
                }

                addOrUpdatePlayer(
                    RosterPlayer(
                        id: backupPlayer.id,
                        name: backupPlayer.name,
                        jerseyNumber: backupPlayer.jerseyNumber,
                        isKeeper: backupPlayer.isKeeper,
                        initials: backupPlayer.initials
                    ),
                    to: backupRoster.teamName
                )
            }
        }
    }

    // MARK: - Persistence

    private static var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private func load() {
        guard
            FileManager.default.fileExists(atPath: Self.localURL.path),
            let data = try? Data(contentsOf: Self.localURL),
            let decoded = try? JSONDecoder().decode([TeamRoster].self, from: data)
        else { return }
        rosters = decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rosters) else { return }
        try? data.write(to: Self.localURL, options: .atomic)
    }
}
