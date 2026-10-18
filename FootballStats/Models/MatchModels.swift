import Foundation
import SwiftUI

enum PresetHomeTeam {
    /// Teams offered as one-tap choices on New Match. Empty in this copy: type your own
    /// team's name, and add presets here if you want them.
    static let names: [String] = []

    /// Used when the home team's name is left blank.
    static let defaultName = names.first ?? "My Team"

    /// Pre-selects `GameFormat` on New Match, and infers the format for matches recorded
    /// before this field existed (`MatchState.init(from:)`). Add a case for any preset
    /// team that plays Futsal.
    static func defaultGameFormat(for teamName: String) -> GameFormat {
        .outdoor
    }
}

/// Outdoor and Futsal score at very different rates (Futsal runs shorter and much faster),
/// so `StandoutMomentEngine` picks its thresholds based on this rather than using one flat
/// rule for every match.
enum GameFormat: String, Codable, CaseIterable, Identifiable {
    case outdoor
    case futsal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .outdoor: "Outdoor"
        case .futsal: "Futsal"
        }
    }
}

enum KickoffTimingMode: String, Codable, CaseIterable, Identifiable {
    case live
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: "Live"
        case .video: "Video Replay"
        }
    }
}

enum TeamSide: String, Codable, CaseIterable {
    case home
    case away

    var opposite: TeamSide {
        switch self {
        case .home: .away
        case .away: .home
        }
    }

    func label(homeName: String, awayName: String) -> String {
        switch self {
        case .home: homeName
        case .away: awayName
        }
    }
}

enum ShotDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy to Score"
    case normal = "Normal Chance"
    case hard = "Hard to Score"
    case corner = "Corners"

    var id: String { rawValue }
}

enum ShotOutcome: String, Codable, CaseIterable, Identifiable {
    case goal = "Goal"
    case notOnTarget = "Not on target"
    case onTarget = "On target"

    var id: String { rawValue }
}

/// Stamped onto each match so pressure / summary rules can change for new recordings
/// without rewriting how older matches are interpreted.
///
/// - `1` — corners as a shot difficulty; every on-target non-goal counts toward keeper saves.
///   Existing backups without the field decode as `1`.
/// - `2` — set-piece setup events (corner / penalty / free kick) instead of corner shots;
///   defender-block / save distinctions land with this generation's live UI.
/// - `3` — shorter inferred-steal window (2s -> 1s). Matches recorded under `1`/`2` keep
///   being scored against the older, longer window.
enum MatchRulesVersion {
    static let current = 3
}

enum SetPieceKind: String, Codable, CaseIterable, Identifiable {
    case corner
    case penalty
    case freeKick

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .corner: "Corner"
        case .penalty: "Penalty"
        case .freeKick: "Free Kick"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .corner: "Setup corner"
        case .penalty: "Setup penalty"
        case .freeKick: "Opportunistic free kick"
        }
    }
}

struct SetPieceEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: SetPieceKind
    let team: TeamSide
    let matchSeconds: Int

    init(
        id: UUID = UUID(),
        kind: SetPieceKind,
        team: TeamSide,
        matchSeconds: Int
    ) {
        self.id = id
        self.kind = kind
        self.team = team
        self.matchSeconds = matchSeconds
    }
}

/// A goal, derived from the shot that scored it rather than stored alongside it.
/// The `id` is the scoring shot's, so SwiftUI identity stays stable across reads.
struct GoalEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let team: TeamSide
    let matchSeconds: Int
    /// Threaded through from the scoring `ShotEvent` — see `MatchState.goals`.
    let creditedPlayerID: UUID?

    init(id: UUID = UUID(), team: TeamSide, matchSeconds: Int, creditedPlayerID: UUID? = nil) {
        self.id = id
        self.team = team
        self.matchSeconds = matchSeconds
        self.creditedPlayerID = creditedPlayerID
    }
}

struct ShotEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let team: TeamSide
    let difficulty: ShotDifficulty
    let outcome: ShotOutcome
    let matchSeconds: Int
    /// The roster player (`RosterModels.swift`) credited for this shot — the scorer for a
    /// goal, or the keeper/defender for a big save. `nil` until credited, or if no roster
    /// exists for the team. Old backups decode this as `nil` automatically (synthesized
    /// `Codable`, no migration needed for a new `Optional` property).
    var creditedPlayerID: UUID?

    init(
        id: UUID = UUID(),
        team: TeamSide,
        difficulty: ShotDifficulty,
        outcome: ShotOutcome,
        matchSeconds: Int,
        creditedPlayerID: UUID? = nil
    ) {
        self.id = id
        self.team = team
        self.difficulty = difficulty
        self.outcome = outcome
        self.matchSeconds = matchSeconds
        self.creditedPlayerID = creditedPlayerID
    }
}

enum PassEventType: String, Codable {
    case ourPass
    case theirPass
    case weIntercepted
    case theyIntercepted
    case homeBallOut
    case awayBallOut
    case possessionToHome
    case possessionToAway
}

struct PassEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let type: PassEventType
    let matchSeconds: Int

    /// Persisted fields only — `id` is minted at runtime so backups don't carry a UUID
    /// for every pass tap (often hundreds per match).
    private enum CodingKeys: String, CodingKey {
        case type
        case matchSeconds
    }

    init(id: UUID = UUID(), type: PassEventType, matchSeconds: Int) {
        self.id = id
        self.type = type
        self.matchSeconds = matchSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(PassEventType.self, forKey: .type)
        matchSeconds = try container.decode(Int.self, forKey: .matchSeconds)
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(matchSeconds, forKey: .matchSeconds)
    }

    /// Identity is for in-memory UI only; two taps with the same type and clock are
    /// the same event for persistence / equality, even if their runtime ids differ.
    static func == (lhs: PassEvent, rhs: PassEvent) -> Bool {
        lhs.type == rhs.type && lhs.matchSeconds == rhs.matchSeconds
    }
}

struct MatchState: Codable, Equatable {
    var homeTeamName: String
    var awayTeamName: String
    var kickoffDate: Date
    var kickoffTimingMode: KickoffTimingMode
    var gameFormat: GameFormat
    var isRunning: Bool
    var elapsedSeconds: Int
    var shots: [ShotEvent]
    var passes: [PassEvent]
    var setPieces: [SetPieceEvent]
    /// Who holds the ball *right now* — not who kicked off, despite what this field used
    /// to be called. `MatchViewModel.pauseClock()` rewrites it on every pause so the Live
    /// screen can restore possession when the clock resumes, which means that by the time
    /// a match reaches History it holds whoever was in possession at the final whistle.
    ///
    /// Nothing should read this to find out how the match started. `PressureEngine`
    /// derives that from the first recorded event instead
    /// (`PressureEngine.openingPossession(for:)`).
    var currentPossession: TeamSide
    var possessionBaseline: TeamSide
    var possessionBaselineSeconds: Int
    /// Which interpretation rules this recording was made under. Never rewrite on load —
    /// only mint `MatchRulesVersion.current` when creating a new match.
    var rulesVersion: Int

    init(
        homeTeamName: String,
        awayTeamName: String,
        kickoffDate: Date,
        kickoffTimingMode: KickoffTimingMode = .live,
        gameFormat: GameFormat = .outdoor,
        isRunning: Bool,
        elapsedSeconds: Int,
        shots: [ShotEvent],
        passes: [PassEvent],
        setPieces: [SetPieceEvent] = [],
        currentPossession: TeamSide = .home,
        possessionBaseline: TeamSide = .home,
        possessionBaselineSeconds: Int = 0,
        rulesVersion: Int = MatchRulesVersion.current
    ) {
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.kickoffDate = kickoffDate
        self.kickoffTimingMode = kickoffTimingMode
        self.gameFormat = gameFormat
        self.isRunning = isRunning
        self.elapsedSeconds = elapsedSeconds
        self.shots = shots
        self.passes = passes
        self.setPieces = setPieces
        self.currentPossession = currentPossession
        self.possessionBaseline = possessionBaseline
        self.possessionBaselineSeconds = possessionBaselineSeconds
        self.rulesVersion = rulesVersion
    }

    /// Every goal is a shot that went in, so the scoring shots *are* the score.
    /// Keeping a parallel goal array let the two drift apart: deleting a goal in the
    /// history editor once dropped a match to 2-2 while its shots still read 3-2.
    var goals: [GoalEvent] {
        shots
            .filter { $0.outcome == .goal }
            .sorted { $0.matchSeconds < $1.matchSeconds }
            .map { GoalEvent(id: $0.id, team: $0.team, matchSeconds: $0.matchSeconds, creditedPlayerID: $0.creditedPlayerID) }
    }

    enum CodingKeys: String, CodingKey {
        case homeTeamName
        case awayTeamName
        case kickoffDate
        case kickoffTimingMode
        case gameFormat
        case isRunning
        case elapsedSeconds
        case shots
        case passes
        case setPieces
        case currentPossession
        case possessionBaseline
        case possessionBaselineSeconds
        case rulesVersion
    }

    /// Keys this app no longer writes but still has to read.
    ///
    /// - `goals` — backups written before the score became derived carry their own array.
    /// - `kickoffPossession` — what `currentPossession` was called before the name was
    ///   found to be wrong (it always tracked live possession, never the kick-off). Old
    ///   files stay readable forever; the value carries straight over, because the field's
    ///   behaviour never changed, only its name.
    private enum LegacyCodingKeys: String, CodingKey {
        case goals
        case kickoffPossession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homeTeamName = try container.decode(String.self, forKey: .homeTeamName)
        awayTeamName = try container.decode(String.self, forKey: .awayTeamName)
        kickoffDate = try container.decode(Date.self, forKey: .kickoffDate)
        kickoffTimingMode = try container.decodeIfPresent(KickoffTimingMode.self, forKey: .kickoffTimingMode) ?? .live
        // Backups from before this field existed don't just get a flat default — the
        // correct format is knowable from which of the preset teams played.
        gameFormat = try container.decodeIfPresent(GameFormat.self, forKey: .gameFormat)
            ?? PresetHomeTeam.defaultGameFormat(for: homeTeamName)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        elapsedSeconds = try container.decode(Int.self, forKey: .elapsedSeconds)
        shots = try container.decode([ShotEvent].self, forKey: .shots)
        passes = try container.decode([PassEvent].self, forKey: .passes)
        setPieces = try container.decodeIfPresent([SetPieceEvent].self, forKey: .setPieces) ?? []
        currentPossession = try Self.decodeCurrentPossession(from: decoder, container: container)
        possessionBaseline = try container.decodeIfPresent(TeamSide.self, forKey: .possessionBaseline) ?? currentPossession
        possessionBaselineSeconds = try container.decodeIfPresent(Int.self, forKey: .possessionBaselineSeconds) ?? 0
        // Pre-stamping backups were all recorded under today's rules.
        rulesVersion = try container.decodeIfPresent(Int.self, forKey: .rulesVersion) ?? 1

        Self.reconcileLegacyGoals(from: decoder, into: &shots)
    }

    /// Reads live possession from whichever key the file carries — `currentPossession`,
    /// or the older `kickoffPossession` it was renamed from. Falls back to `.home`, which
    /// is what a match is created with.
    private static func decodeCurrentPossession(
        from decoder: Decoder,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> TeamSide {
        if let current = try container.decodeIfPresent(TeamSide.self, forKey: .currentPossession) {
            return current
        }
        guard let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self) else { return .home }
        return (try? legacy.decodeIfPresent(TeamSide.self, forKey: .kickoffPossession)) ?? .home
    }

    /// Brings an older file's `goals` array and its shots back into agreement, so a
    /// match keeps showing the score it showed before the score became derived.
    private static func reconcileLegacyGoals(from decoder: Decoder, into shots: inout [ShotEvent]) {
        guard
            let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self),
            let goals = try? legacy.decode([GoalEvent].self, forKey: .goals)
        else { return }

        var unclaimed = goals
        var reconciled: [ShotEvent] = []

        for shot in shots {
            guard shot.outcome == .goal else {
                reconciled.append(shot)
                continue
            }

            if let index = unclaimed.firstIndex(where: {
                $0.team == shot.team && $0.matchSeconds == shot.matchSeconds
            }) {
                unclaimed.remove(at: index)
                reconciled.append(shot)
                continue
            }

            // The goal was deleted in the history editor but its shot was left behind.
            // Honour the deletion by demoting the shot rather than resurrecting a goal
            // the recorder had already decided to remove.
            reconciled.append(
                ShotEvent(
                    id: shot.id,
                    team: shot.team,
                    difficulty: shot.difficulty,
                    outcome: .onTarget,
                    matchSeconds: shot.matchSeconds
                )
            )
        }

        // The reverse case: a goal with no shot at all means the shot record was lost,
        // so put one back instead of dropping it from the score.
        for goal in unclaimed {
            reconciled.append(
                ShotEvent(
                    id: goal.id,
                    team: goal.team,
                    difficulty: .normal,
                    outcome: .goal,
                    matchSeconds: goal.matchSeconds
                )
            )
        }

        shots = reconciled
    }

    static let empty = MatchState(
        homeTeamName: "Z",
        awayTeamName: "Opposition",
        kickoffDate: Date(),
        kickoffTimingMode: .live,
        isRunning: false,
        elapsedSeconds: 0,
        shots: [],
        passes: []
    )

    func score(for team: TeamSide) -> Int {
        shots.filter { $0.team == team && $0.outcome == .goal }.count
    }

    func formattedClock(from seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    var currentClock: String {
        formattedClock(from: elapsedSeconds)
    }

    var hasRecordableContent: Bool {
        elapsedSeconds > 0 || !shots.isEmpty || !passes.isEmpty || !setPieces.isEmpty
    }
}

struct SavedMatch: Identifiable, Codable, Equatable {
    let id: UUID
    let savedAt: Date
    var match: MatchState

    init(id: UUID = UUID(), savedAt: Date = Date(), match: MatchState) {
        self.id = id
        self.savedAt = savedAt
        var storedMatch = match
        storedMatch.isRunning = false
        self.match = storedMatch
    }

    var scoreLine: String {
        "\(match.score(for: .home))–\(match.score(for: .away))"
    }

    var title: String {
        "\(match.homeTeamName) vs \(match.awayTeamName)"
    }
}

struct ShotSummaryLine: Identifiable {
    let id = UUID()
    let difficulty: ShotDifficulty
    let total: Int
    let goals: Int
    let notOnTarget: Int
}

struct TeamShotSummary {
    let teamName: String
    let lines: [ShotSummaryLine]
    let totalAttempts: Int
    let totalGoals: Int
}

struct ConsolidatedPassButton {
    let type: PassEventType
    let title: String
    let color: Color
    let isEnabled: Bool
}
