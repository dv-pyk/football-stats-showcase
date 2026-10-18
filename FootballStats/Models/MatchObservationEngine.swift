import Foundation

struct DifficultyShotBreakdown {
    let difficulty: ShotDifficulty
    let total: Int
    let goals: Int
    let notOnTarget: Int

    var onTargetAttempts: Int { total - notOnTarget }
    var savedOrBlocked: Int { max(0, total - goals - notOnTarget) }

    var onTargetConversionRate: Double? {
        guard onTargetAttempts > 0 else { return nil }
        return Double(goals) / Double(onTargetAttempts)
    }
}

private struct RankedObservation {
    let text: String
    let priority: Int
}

enum MatchObservationEngine {
    static let defaultLimit = 4

    static func observations(
        for match: MatchState,
        ourTeam: TeamSide = .home,
        limit: Int = defaultLimit
    ) -> [String] {
        guard !match.shots.isEmpty else { return [] }

        let ourName = shortName(ourTeam.label(homeName: match.homeTeamName, awayName: match.awayTeamName))
        let theirName = shortName(ourTeam == .home ? match.awayTeamName : match.homeTeamName)
        let theirTeam: TeamSide = ourTeam == .home ? .away : .home

        var ranked: [RankedObservation] = []

        let ourLines = ShotDifficulty.allCases.map { breakdown(for: ourTeam, difficulty: $0, in: match) }
        let theirLines = ShotDifficulty.allCases.map { breakdown(for: theirTeam, difficulty: $0, in: match) }

        // Observations that talk about "attempts" or "shots" without naming a difficulty
        // have to agree with the share image, which counts an unscored corner as a
        // delivery rather than a shot.
        let ourShotLines = shotCountingLines(ourLines)
        let theirShotLines = shotCountingLines(theirLines)

        appendAccuracyObservations(into: &ranked, ourName: ourName, lines: ourShotLines)
        appendDefenceObservations(into: &ranked, ourName: ourName, theirName: theirName, theirLines: theirLines)
        appendAttackQualityObservations(
            into: &ranked,
            ourName: ourName,
            theirName: theirName,
            ourLines: ourLines,
            theirLines: theirLines
        )
        appendEasyChanceObservations(
            into: &ranked,
            ourName: ourName,
            theirName: theirName,
            ourLines: ourLines,
            theirLines: theirLines
        )
        appendVolumeObservations(
            into: &ranked,
            ourName: ourName,
            theirName: theirName,
            ourLines: ourShotLines,
            theirLines: theirShotLines
        )
        appendCornerObservations(
            into: &ranked,
            ourName: ourName,
            theirName: theirName,
            ourLines: ourLines,
            theirLines: theirLines
        )

        return ranked
            .sorted { $0.priority > $1.priority }
            .prefix(limit)
            .map(\.text)
    }

    private static func shortName(_ name: String) -> String {
        TeamDisplayNames.short(name)
    }

    private static func breakdown(
        for team: TeamSide,
        difficulty: ShotDifficulty,
        in match: MatchState
    ) -> DifficultyShotBreakdown {
        let shots = match.shots.filter { $0.team == team && $0.difficulty == difficulty }
        return DifficultyShotBreakdown(
            difficulty: difficulty,
            total: shots.count,
            goals: shots.filter { $0.outcome == .goal }.count,
            notOnTarget: shots.filter { $0.outcome == .notOnTarget }.count
        )
    }

    private static func appendAccuracyObservations(
        into results: inout [RankedObservation],
        ourName: String,
        lines: [DifficultyShotBreakdown]
    ) {
        let easy = line(lines, .easy)
        let normal = line(lines, .normal)
        let hard = line(lines, .hard)

        let combinedOnTarget = easy.onTargetAttempts + normal.onTargetAttempts
        let combinedGoals = easy.goals + normal.goals
        let combinedMisses = easy.notOnTarget + normal.notOnTarget

        if combinedOnTarget >= 2,
           combinedGoals >= 2,
           Double(combinedGoals) / Double(combinedOnTarget) >= 0.75,
           combinedMisses >= 3 {
            results.append(RankedObservation(
                text: "When \(ourName) got Easy or Normal shots on target, most went in — but \(combinedMisses) attempts were off target. Improving accuracy on those chances could add more goals without needing better chances.",
                priority: 95
            ))
            return
        }

        for item in [easy, normal, hard] where item.total >= 3 {
            guard let rate = item.onTargetConversionRate, item.onTargetAttempts >= 2 else { continue }
            if rate >= 0.75, item.notOnTarget >= 2 {
                results.append(RankedObservation(
                    text: "\(item.difficulty.rawValue): \(item.notOnTarget) off target vs \(item.goals) goals — on-target efforts usually scored, so tightening accuracy here is a clear lever.",
                    priority: 88
                ))
            }
        }

        let totalMisses = lines.reduce(0) { $0 + $1.notOnTarget }
        let totalGoals = lines.reduce(0) { $0 + $1.goals }
        if totalMisses >= 8, totalMisses > totalGoals * 2 {
            results.append(RankedObservation(
                text: "\(ourName) had \(totalMisses) shots off target compared with \(totalGoals) goals — more shots on frame would likely boost the scoreline.",
                priority: 82
            ))
        }
    }

    private static func appendDefenceObservations(
        into results: inout [RankedObservation],
        ourName: String,
        theirName: String,
        theirLines: [DifficultyShotBreakdown]
    ) {
        let theirEasy = line(theirLines, .easy)
        let theirNormal = line(theirLines, .normal)
        let theirHard = line(theirLines, .hard)
        let theirCorner = line(theirLines, .corner)

        let tougherAttempts = theirNormal.total + theirHard.total + theirCorner.total
        let tougherGoals = theirNormal.goals + theirHard.goals + theirCorner.goals

        if theirEasy.goals > 0,
           tougherAttempts >= 3,
           tougherGoals == 0 {
            results.append(RankedObservation(
                text: "\(theirName) only scored from Easy chances — \(ourName)'s defence and keeper dealt well with Normal, Hard, and Corner attempts.",
                priority: 90
            ))
        } else if theirNormal.savedOrBlocked + theirHard.savedOrBlocked >= 5,
                  theirNormal.goals + theirHard.goals == 0 {
            let stopped = theirNormal.savedOrBlocked + theirHard.savedOrBlocked
            results.append(RankedObservation(
                text: "Keeper and defence stood firm: \(stopped) Normal or Hard attempts were stopped without a goal.",
                priority: 78
            ))
        }

        if theirEasy.goals >= 4, theirEasy.goals >= theirNormal.goals + theirHard.goals + theirCorner.goals {
            results.append(RankedObservation(
                text: "Most of \(theirName)'s goals came from Easy chances — harder to stop when they get a clear look close in.",
                priority: 72
            ))
        }
    }

    private static func appendAttackQualityObservations(
        into results: inout [RankedObservation],
        ourName: String,
        theirName: String,
        ourLines: [DifficultyShotBreakdown],
        theirLines: [DifficultyShotBreakdown]
    ) {
        let ourNormal = line(ourLines, .normal)
        let ourHard = line(ourLines, .hard)
        let theirNormal = line(theirLines, .normal)
        let theirHard = line(theirLines, .hard)

        let ourQualityGoals = ourNormal.goals + ourHard.goals
        let theirQualityGoals = theirNormal.goals + theirHard.goals

        if ourQualityGoals >= 2, theirQualityGoals == 0,
           theirNormal.total + theirHard.total >= 3 {
            results.append(RankedObservation(
                text: "\(ourName) scored from Normal or Hard attempts while \(theirName) did not — creating and converting tougher chances was a strength.",
                priority: 70
            ))
        }

        if ourNormal.goals >= 3, ourNormal.notOnTarget >= 5 {
            results.append(RankedObservation(
                text: "Normal Chance produced \(ourNormal.goals) goals but \(ourNormal.notOnTarget) misses — the volume is there; calmer finishing could reward it.",
                priority: 68
            ))
        }
    }

    private static func appendEasyChanceObservations(
        into results: inout [RankedObservation],
        ourName: String,
        theirName: String,
        ourLines: [DifficultyShotBreakdown],
        theirLines: [DifficultyShotBreakdown]
    ) {
        let ourEasy = line(ourLines, .easy)
        let theirEasy = line(theirLines, .easy)

        if theirEasy.goals >= 3, theirEasy.goals > ourEasy.goals + 1 {
            results.append(RankedObservation(
                text: "\(theirName) scored \(theirEasy.goals) Easy goals — denying easy opportunities (through defensive shape or pressure) would make the biggest difference.",
                priority: 100
            ))
        }

        if ourEasy.total <= 2, theirEasy.total >= 10 {
            results.append(RankedObservation(
                text: "\(theirName) had \(theirEasy.total) Easy attempts vs \(ourEasy.total) for \(ourName) — they found simpler chances more often.",
                priority: 62
            ))
        }

        if ourEasy.goals == 0, ourEasy.total >= 3, ourEasy.notOnTarget == ourEasy.total {
            results.append(RankedObservation(
                text: "All \(ourEasy.total) Easy attempts for \(ourName) missed the target — even the clearest chances need a calm finish.",
                priority: 86
            ))
        }
    }

    private static func appendVolumeObservations(
        into results: inout [RankedObservation],
        ourName: String,
        theirName: String,
        ourLines: [DifficultyShotBreakdown],
        theirLines: [DifficultyShotBreakdown]
    ) {
        let ourAttempts = ourLines.reduce(0) { $0 + $1.total }
        let theirAttempts = theirLines.reduce(0) { $0 + $1.total }

        guard ourAttempts > 0, theirAttempts > 0 else { return }

        if theirAttempts >= Int(Double(ourAttempts) * 1.4) {
            results.append(RankedObservation(
                text: "\(theirName) had \(theirAttempts) attempts to \(ourAttempts) — they created more volume; \(ourName) relied on efficiency when chances came.",
                priority: 55
            ))
        } else if ourAttempts >= Int(Double(theirAttempts) * 1.4) {
            results.append(RankedObservation(
                text: "\(ourName) outshot \(theirName) (\(ourAttempts) vs \(theirAttempts)) — more attempts, but conversion decided the scoreline.",
                priority: 55
            ))
        }
    }

    private static func appendCornerObservations(
        into results: inout [RankedObservation],
        ourName: String,
        theirName: String,
        ourLines: [DifficultyShotBreakdown],
        theirLines: [DifficultyShotBreakdown]
    ) {
        let ourCorners = line(ourLines, .corner)
        let theirCorners = line(theirLines, .corner)

        if ourCorners.total >= 5, ourCorners.goals == 0 {
            results.append(RankedObservation(
                text: "\(ourName) had \(ourCorners.total) corners without a goal — set pieces did not convert this match.",
                priority: 40
            ))
        }

        if theirCorners.total >= 8, theirCorners.goals == 0 {
            results.append(RankedObservation(
                text: "\(theirName) took \(theirCorners.total) corners without scoring — defending set pieces held up well.",
                priority: 45
            ))
        }
    }

    /// Restates the corner line the way `PressureEngine.countsAsShot` does: only a scored
    /// corner is an attempt, so unscored deliveries drop out of any aggregate tally.
    private static func shotCountingLines(_ lines: [DifficultyShotBreakdown]) -> [DifficultyShotBreakdown] {
        lines.map { item in
            guard item.difficulty == .corner else { return item }
            return DifficultyShotBreakdown(
                difficulty: .corner,
                total: item.goals,
                goals: item.goals,
                notOnTarget: 0
            )
        }
    }

    private static func line(_ lines: [DifficultyShotBreakdown], _ difficulty: ShotDifficulty) -> DifficultyShotBreakdown {
        lines.first { $0.difficulty == difficulty }
            ?? DifficultyShotBreakdown(difficulty: difficulty, total: 0, goals: 0, notOnTarget: 0)
    }
}
