import Foundation

/// A player on a team's roster. Avatars are not stored here — they live as separate JPEG
/// files on disk, named by `id`, so the roster JSON stays small text (`RosterStore.swift`).
struct RosterPlayer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var jerseyNumber: String?
    var isKeeper: Bool
    /// Manual override for the no-photo fallback badge. Most players won't set this —
    /// `displayInitials` derives something reasonable from `name` on its own — this is only
    /// for when the derived initials aren't the ones you'd actually want shown.
    var initials: String?

    init(id: UUID = UUID(), name: String, jerseyNumber: String? = nil, isKeeper: Bool = false, initials: String? = nil) {
        self.id = id
        self.name = name
        self.jerseyNumber = jerseyNumber
        self.isKeeper = isKeeper
        self.initials = initials
    }

    /// What to show in place of a photo: the manual override if set, otherwise derived from
    /// `name` — first letters of the first two words, or the first two letters of a
    /// single-word name.
    var displayInitials: String {
        let trimmed = initials?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty {
            return String(trimmed.prefix(3)).uppercased()
        }

        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let word = words.first {
            return String(word.prefix(2)).uppercased()
        }
        return "?"
    }
}

/// A roster is keyed by team name, not a team ID — the app has no team-identity concept
/// beyond the name string anywhere (`MatchState.homeTeamName`, `PresetHomeTeam`), so this
/// matches how every other part of the app already treats "which team."
///
/// Only the home (own) team ever gets a roster — the opposition is always free-typed with
/// no roster of its own.
struct TeamRoster: Codable, Equatable {
    let teamName: String
    var players: [RosterPlayer]
}

/// Roster data as it appears in a portable backup file — unlike `RosterPlayer`, this
/// carries the avatar's raw bytes (encoded as base64 by `JSONEncoder`'s default `Data`
/// handling), since a backup has to be one self-contained, shareable file rather than
/// pointing at a photo living separately on disk (`RosterStore.avatarImage(for:)`).
struct BackupRosterPlayer: Codable {
    let id: UUID
    let name: String
    let jerseyNumber: String?
    let isKeeper: Bool
    let avatarData: Data?
    let initials: String?
}

struct BackupTeamRoster: Codable {
    let teamName: String
    let players: [BackupRosterPlayer]
}
