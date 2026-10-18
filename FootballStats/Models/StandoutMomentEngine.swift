import Foundation

/// Detects match-worthy moments — a keeper's big night, a goal burst, a long spell of
/// controlled passing, a comeback — validated against real recorded matches before being
/// built (see `BACKBURNER.md`'s "Standout-moment call-outs" entry for the full history).
///
/// Unlike `MatchObservationEngine`, this isn't "coaching feedback for our team" — a
/// standout moment from either side is part of the match's story, so both teams are
/// checked every time, not just `.home`.
enum StandoutMomentEngine {
    private struct Thresholds {
        let bigSaves: Int
        let cleanSheetMinFaced: Int
        let burstCount: Int
        let burstWindowSeconds: Int
        let passStreak: Int
        let comebackDeficit: Int
    }

    /// Outdoor games run longer (~50-60 min) and score far more slowly than Futsal
    /// (~35-40 min) — a flat threshold either never fires for Outdoor or fires on nearly
    /// every Futsal match. Picked by looking at the actual spread of values within each
    /// format across every recorded match, aiming for roughly the rarest 15-20%.
    private static let outdoor = Thresholds(
        bigSaves: 2, cleanSheetMinFaced: 4, burstCount: 2, burstWindowSeconds: 300,
        passStreak: 12, comebackDeficit: 1
    )
    private static let futsal = Thresholds(
        bigSaves: 5, cleanSheetMinFaced: 8, burstCount: 4, burstWindowSeconds: 300,
        passStreak: 10, comebackDeficit: 2
    )

    static func moments(for match: MatchState) -> [String] {
        let thresholds = match.gameFormat == .futsal ? futsal : outdoor
        return keeperMoments(match: match, thresholds: thresholds)
            + burstMoments(match: match, thresholds: thresholds)
            + streakMoments(match: match, thresholds: thresholds)
            + comebackMoments(match: match, thresholds: thresholds)
    }

    private static func name(_ team: TeamSide, in match: MatchState) -> String {
        TeamDisplayNames.short(team.label(homeName: match.homeTeamName, awayName: match.awayTeamName))
    }

    // MARK: - Keeper performances

    private static func keeperMoments(match: MatchState, thresholds: Thresholds) -> [String] {
        var lines: [String] = []
        for side in TeamSide.allCases {
            let opponent: TeamSide = side == .home ? .away : .home
            let conceded = match.shots.filter { $0.team == opponent && PressureEngine.countsAsShot($0) }
            let onTarget = conceded.filter { $0.outcome == .goal || $0.outcome == .onTarget }
            let saves = onTarget.filter { $0.outcome == .onTarget }
            let bigSaves = saves.filter { $0.difficulty == .easy }
            let goalsConceded = onTarget.count - saves.count
            let label = name(side, in: match)

            if bigSaves.count >= thresholds.bigSaves {
                lines.append("\(label)'s keeper stood tall — \(bigSaves.count) big saves out of \(onTarget.count) attempts faced.")
            } else if goalsConceded == 0, onTarget.count >= thresholds.cleanSheetMinFaced {
                lines.append("\(label) kept a clean sheet despite \(onTarget.count) shots on target — a real shutout, not a quiet night.")
            }
        }
        return lines
    }

    // MARK: - Goal bursts

    private static func burstMoments(match: MatchState, thresholds: Thresholds) -> [String] {
        var lines: [String] = []
        for side in TeamSide.allCases {
            let goals = match.shots
                .filter { $0.team == side && $0.outcome == .goal }
                .map(\.matchSeconds)
                .sorted()
            guard goals.count >= thresholds.burstCount else { continue }

            var bestCount = 1
            var bestSpan = 0
            var bestStart = 0
            for i in 0..<goals.count {
                for j in (i + 1)..<goals.count {
                    let span = goals[j] - goals[i]
                    guard span <= thresholds.burstWindowSeconds else { continue }
                    let count = j - i + 1
                    if count > bestCount {
                        bestCount = count
                        bestSpan = span
                        bestStart = goals[i]
                    }
                }
            }

            guard bestCount >= thresholds.burstCount else { continue }
            let label = name(side, in: match)
            lines.append("\(label) scored \(bestCount) goals in \(spanText(bestSpan)), starting from \(clockText(bestStart)) — a real purple patch.")
        }
        return lines
    }

    // MARK: - Pass streaks

    private static func streakMoments(match: MatchState, thresholds: Thresholds) -> [String] {
        var currentTeam: TeamSide?
        var currentRun = 0
        var bestHome = 0
        var bestAway = 0

        for pass in match.passes.sorted(by: { $0.matchSeconds < $1.matchSeconds }) {
            let team = PressureEngine.gainingTeam(for: pass.type)
            let isPlainPass = pass.type == .ourPass || pass.type == .theirPass

            if team != currentTeam {
                currentTeam = team
                currentRun = isPlainPass ? 1 : 0
            } else {
                currentRun = isPlainPass ? currentRun + 1 : 0
            }

            if team == .home {
                bestHome = max(bestHome, currentRun)
            } else {
                bestAway = max(bestAway, currentRun)
            }
        }

        var lines: [String] = []
        if bestHome >= thresholds.passStreak {
            lines.append("\(name(.home, in: match)) strung together \(bestHome) consecutive passes without losing the ball — the longest spell of controlled play in the match.")
        }
        if bestAway >= thresholds.passStreak {
            lines.append("\(name(.away, in: match)) strung together \(bestAway) consecutive passes without losing the ball — the longest spell of controlled play in the match.")
        }
        return lines
    }

    // MARK: - Comebacks

    private static func comebackMoments(match: MatchState, thresholds: Thresholds) -> [String] {
        let goals = match.shots
            .filter { $0.outcome == .goal }
            .sorted { $0.matchSeconds < $1.matchSeconds }

        var home = 0
        var away = 0
        var maxHomeDeficit = 0
        var maxAwayDeficit = 0
        for goal in goals {
            if goal.team == .home { home += 1 } else { away += 1 }
            maxHomeDeficit = max(maxHomeDeficit, away - home)
            maxAwayDeficit = max(maxAwayDeficit, home - away)
        }

        var lines: [String] = []
        if maxHomeDeficit >= thresholds.comebackDeficit, home >= away {
            lines.append("\(name(.home, in: match)) came back from \(maxHomeDeficit) goal\(maxHomeDeficit == 1 ? "" : "s") down to finish \(home)-\(away) — a genuine comeback.")
        }
        if maxAwayDeficit >= thresholds.comebackDeficit, away >= home {
            lines.append("\(name(.away, in: match)) came back from \(maxAwayDeficit) goal\(maxAwayDeficit == 1 ? "" : "s") down to finish \(away)-\(home) — a genuine comeback.")
        }
        return lines
    }

    // MARK: - Formatting

    private static func spanText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) seconds" }
        return String(format: "%.1f minutes", Double(seconds) / 60)
    }

    private static func clockText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
