import Foundation

enum PressureWeight {
    static let pass: Double = 1
    static let intercept: Double = 5
    static let shotOffTarget: Double = 1
    static let shotOnTarget: Double = 3
    static let goal: Double = 8
    static let cornerBonus: Double = 1.5
    /// Credited the moment a set-piece is won, on top of whatever shot outcome eventually
    /// follows it — winning the situation is itself a threat, independent of conversion.
    /// A penalty converts far more often than a corner or free kick reaches goal, so it
    /// carries most of the way from an on-target shot (3) to a goal (8); corner and free
    /// kick sit at the old flat corner bonus.
    static func setPieceWeight(for kind: SetPieceKind) -> Double {
        switch kind {
        case .penalty: 6
        case .corner, .freeKick: 1.5
        }
    }
    /// A possession-change tap followed this quickly by a pass for the new holder is
    /// treated as a steal. Ball-outs typically leave a ~3s gap before the restart pass,
    /// so anything inside this window is assumed to be live play continuing after a steal.
    ///
    /// Versioned via `MatchRulesVersion` so a match already recorded keeps being scored
    /// against the window that was live when it happened — shortening this for new matches
    /// must never reclassify what an old one already inferred.
    static func inferredStealWindowSeconds(rulesVersion: Int) -> Int {
        rulesVersion >= 3 ? 1 : 2
    }
    static let lookbackSeconds = 120
    static let sampleStepSeconds = 15
    /// Quiet waits this long (subs, set pieces) are left out of possession % — the match
    /// clock still runs, but neither side is credited for the dead time.
    static let possessionIdleGapSeconds = 25
    static let liveActivityBucketCount = 45
    static let liveActivityBucketSeconds = 1
}

enum PressureEngine {
    static func events(from match: MatchState) -> [(seconds: Int, delta: Double)] {
        var result: [(Int, Double)] = []

        for pass in match.passes {
            switch pass.type {
            case .ourPass:
                result.append((pass.matchSeconds, PressureWeight.pass))
            case .theirPass:
                result.append((pass.matchSeconds, -PressureWeight.pass))
            case .weIntercepted:
                result.append((pass.matchSeconds, PressureWeight.intercept))
            case .theyIntercepted:
                result.append((pass.matchSeconds, -PressureWeight.intercept))
            case .homeBallOut, .awayBallOut, .possessionToHome, .possessionToAway:
                break
            }
        }

        // The Action Button only reports a neutral possession change, which covers both
        // steals and balls out of play. When that change is followed almost immediately
        // by a pass for the new holder, treat it as a steal and apply the interception
        // weight at the change. Explicit interception taps still take precedence above.
        let stealWindow = PressureWeight.inferredStealWindowSeconds(rulesVersion: match.rulesVersion)
        for steal in inferredSteals(in: match.passes, stealWindowSeconds: stealWindow) {
            let sign: Double = steal.team == .home ? 1 : -1
            result.append((steal.seconds, sign * PressureWeight.intercept))
        }

        for shot in match.shots {
            let sign: Double = shot.team == .home ? 1 : -1
            var weight: Double
            switch shot.outcome {
            case .goal:
                weight = PressureWeight.goal
            case .onTarget:
                weight = PressureWeight.shotOnTarget
            case .notOnTarget:
                weight = PressureWeight.shotOffTarget
            }
            if shot.difficulty == .corner {
                weight += PressureWeight.cornerBonus
            }
            result.append((shot.matchSeconds, sign * weight))
        }

        for setPiece in match.setPieces {
            let sign: Double = setPiece.team == .home ? 1 : -1
            result.append((setPiece.matchSeconds, sign * PressureWeight.setPieceWeight(for: setPiece.kind)))
        }

        return result.sorted { $0.0 < $1.0 }
    }

    /// Possession changes whose next same-team pass arrives inside the steal window,
    /// with no intervening flip. Each change is claimed at most once.
    static func inferredSteals(
        in passes: [PassEvent],
        stealWindowSeconds: Int
    ) -> [(seconds: Int, team: TeamSide)] {
        let ordered = passes.enumerated().sorted {
            if $0.element.matchSeconds != $1.element.matchSeconds {
                return $0.element.matchSeconds < $1.element.matchSeconds
            }
            return $0.offset < $1.offset
        }

        var claimed: Set<Int> = []
        var steals: [(seconds: Int, team: TeamSide)] = []

        for (index, (_, pass)) in ordered.enumerated() {
            let team: TeamSide
            switch pass.type {
            case .ourPass: team = .home
            case .theirPass: team = .away
            default: continue
            }

            priorSearch: for prior in ordered[..<index].reversed() {
                let gap = pass.matchSeconds - prior.element.matchSeconds
                if gap > stealWindowSeconds { break }

                switch prior.element.type {
                case .possessionToHome where team == .home,
                     .possessionToAway where team == .away:
                    if claimed.insert(prior.offset).inserted {
                        steals.append((prior.element.matchSeconds, team))
                    }
                    break priorSearch
                case .possessionToHome, .possessionToAway,
                     .weIntercepted, .theyIntercepted,
                     .homeBallOut, .awayBallOut:
                    // Someone else flipped possession in between — this pass isn't
                    // continuing the change we're looking at.
                    break priorSearch
                case .ourPass, .theirPass:
                    continue priorSearch
                }
            }
        }

        return steals
    }

    static func value(at seconds: Int, events: [(seconds: Int, delta: Double)]) -> Double {
        var total = 0.0
        for event in events where event.seconds <= seconds {
            let age = seconds - event.seconds
            guard age <= PressureWeight.lookbackSeconds else { continue }
            let fade = 1.0 - (Double(age) / Double(PressureWeight.lookbackSeconds)) * 0.6
            total += event.delta * fade
        }
        return total
    }

    static func chartPoints(for match: MatchState) -> [PressureChartPoint] {
        let events = events(from: match)
        let end = max(match.elapsedSeconds, events.last?.seconds ?? 0)

        var points: [PressureChartPoint] = [
            PressureChartPoint(matchSeconds: 0, value: 0)
        ]

        guard end > 0 else { return points }

        for t in stride(from: PressureWeight.sampleStepSeconds, through: end, by: PressureWeight.sampleStepSeconds) {
            points.append(
                PressureChartPoint(
                    matchSeconds: t,
                    value: value(at: t, events: events)
                )
            )
        }

        if points.last?.matchSeconds != end {
            points.append(
                PressureChartPoint(
                    matchSeconds: end,
                    value: value(at: end, events: events)
                )
            )
        }

        return points
    }

    static func currentPressure(from match: MatchState) -> Double {
        value(at: match.elapsedSeconds, events: events(from: match))
    }

    static func recentPressureBuckets(for match: MatchState) -> [Double] {
        let bucketCount = PressureWeight.liveActivityBucketCount
        let bucketSeconds = PressureWeight.liveActivityBucketSeconds
        let window = bucketCount * bucketSeconds
        let end = match.elapsedSeconds
        let windowStart = max(0, end - window)
        let events = events(from: match)

        return (0..<bucketCount).map { index in
            let bucketStart = windowStart + index * bucketSeconds
            let bucketEnd = bucketStart + bucketSeconds
            if bucketStart > end { return 0 }

            var total = 0.0
            for event in events where event.seconds >= bucketStart && event.seconds < bucketEnd {
                total += event.delta
            }
            return total
        }
    }

    /// Which team gains the ball as a result of an event.
    static func gainingTeam(for type: PassEventType) -> TeamSide {
        switch type {
        case .ourPass, .weIntercepted, .awayBallOut, .possessionToHome:
            .home
        case .theirPass, .theyIntercepted, .homeBallOut, .possessionToAway:
            .away
        }
    }

    /// The match broken into contiguous stretches of possession, used for the possession
    /// percentages. Spell boundaries are the recorded turnovers, so a run of taps for one
    /// side stays a single spell.
    static func possessionSpells(for match: MatchState) -> [(team: TeamSide, start: Int, end: Int)] {
        let end = max(match.elapsedSeconds, 1)

        struct TimedPossessionChange: Comparable {
            let seconds: Int
            let kind: Int
            let team: TeamSide

            static func < (lhs: TimedPossessionChange, rhs: TimedPossessionChange) -> Bool {
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                return lhs.kind < rhs.kind
            }
        }

        var changes = match.passes.map {
            TimedPossessionChange(seconds: $0.matchSeconds, kind: 0, team: gainingTeam(for: $0.type))
        }

        for goal in match.goals {
            let kickoffTeam = goal.team.opposite
            changes.append(TimedPossessionChange(seconds: goal.matchSeconds, kind: 1, team: kickoffTeam))
        }

        var spells: [(team: TeamSide, start: Int, end: Int)] = []
        // Not `match.currentPossession` — that tracks who has the ball *now*, so on a
        // saved match it names whoever held it at the final whistle, and the opening
        // spell would be credited to them. What actually happened at kick-off is already
        // in the events; read it back from there.
        var currentTeam = openingPossession(for: match) ?? match.currentPossession
        var segmentStart = 0

        for change in changes.sorted() {
            guard change.seconds > segmentStart, change.seconds <= end else {
                currentTeam = change.team
                continue
            }

            // Only close the spell when the ball actually changes hands. Consecutive
            // taps for the same side — a run of `ourPass`, say — describe one stretch of
            // possession, and splitting on each of them would leave almost every spell
            // shorter than a single hold tick.
            guard change.team != currentTeam else { continue }

            spells.append((currentTeam, segmentStart, change.seconds))
            currentTeam = change.team
            segmentStart = change.seconds
        }

        if end > segmentStart {
            spells.append((currentTeam, segmentStart, end))
        }

        return spells
    }

    /// Who had the ball at kick-off, read back from the first thing recorded rather than
    /// from a stored field — the same rule the score follows (see `MatchState.goals`):
    /// don't keep a second copy of what the events already say, because the copy drifts.
    /// `MatchState.currentPossession` is exactly such a copy gone stale; it tracked the
    /// kick-off correctly right up until the first pause overwrote it.
    ///
    /// The one case this reads wrong: if the side that kicked off lost the ball before
    /// anything was tapped, the opening seconds go to whoever touched it first instead.
    /// That's bounded by how soon the first tap lands — across the owner's 33 recorded
    /// matches the median is 1s and the worst is 7s, against matches of 28–63 minutes —
    /// and storing a kick-off field instead would only narrow that at the cost of another
    /// copy to keep honest.
    ///
    /// `nil` when nothing was ever recorded, which leaves the caller to pick a fallback.
    static func openingPossession(for match: MatchState) -> TeamSide? {
        let firstPass = match.passes.min { $0.matchSeconds < $1.matchSeconds }
        let firstGoal = match.goals.first

        switch (firstPass, firstGoal) {
        case let (pass?, goal?):
            // A tie goes to the pass, matching how `possessionSpells` orders passes
            // (kind 0) ahead of goal restarts (kind 1) within the same second.
            return pass.matchSeconds <= goal.matchSeconds ? possessorBefore(pass.type) : goal.team
        case let (pass?, nil):
            return possessorBefore(pass.type)
        case let (nil, goal?):
            // A restart is taken by the conceding side, so the ball belonged to the
            // scorer up to that point.
            return goal.team
        case (nil, nil):
            return nil
        }
    }

    /// Who held the ball immediately *before* this event was tapped. A pass is the
    /// possessor carrying on, so it's whoever gained it; everything else — an
    /// interception, a ball-out, a possession flip — is the moment they lost it.
    private static func possessorBefore(_ type: PassEventType) -> TeamSide {
        switch type {
        case .ourPass, .theirPass: gainingTeam(for: type)
        default: gainingTeam(for: type).opposite
        }
    }

    static func possessionPercentages(for match: MatchState) -> (home: Int, away: Int) {
        let idle = idlePossessionSeconds(for: match)
        var homeSeconds = 0
        var awaySeconds = 0

        for spell in possessionSpells(for: match) {
            for second in spell.start..<spell.end where !idle.contains(second) {
                if spell.team == .home {
                    homeSeconds += 1
                } else {
                    awaySeconds += 1
                }
            }
        }

        let total = max(homeSeconds + awaySeconds, 1)
        let home = Int((Double(homeSeconds) / Double(total) * 100).rounded())
        return (home, 100 - home)
    }

    /// Match-clock seconds that fall inside a quiet gap of at least
    /// `possessionIdleGapSeconds` between any recorded taps, or inside a dead-ball gap
    /// after a ball-out (however short — the ball isn't back in play until the restart
    /// pass, regardless of how quick the throw-in was). Action seconds themselves still
    /// count; only the empty interior of the wait is dropped.
    private static func idlePossessionSeconds(for match: MatchState) -> Set<Int> {
        var marks = Set(match.passes.map(\.matchSeconds))
        marks.formUnion(match.shots.map(\.matchSeconds))
        let times = marks.sorted()

        let ballOutSeconds = Set(match.passes
            .filter { $0.type == .homeBallOut || $0.type == .awayBallOut }
            .map(\.matchSeconds))

        var idle = Set<Int>()

        for (previous, next) in zip(times, times.dropFirst()) {
            let isDeadBallGap = ballOutSeconds.contains(previous)
            guard isDeadBallGap || next - previous >= PressureWeight.possessionIdleGapSeconds else { continue }
            for second in (previous + 1)..<next {
                idle.insert(second)
            }
        }

        // The most recent mark can still be sitting inside an unresolved gap — nothing
        // later has happened yet to close it off. Without this, the live clock (or a
        // match that ends mid-stoppage) keeps crediting whoever last touched the ball
        // right through an ongoing quiet period or dead ball.
        if let last = times.last, match.elapsedSeconds > last {
            let now = match.elapsedSeconds
            let isDeadBallGap = ballOutSeconds.contains(last)
            if isDeadBallGap || now - last >= PressureWeight.possessionIdleGapSeconds {
                for second in (last + 1)...now {
                    idle.insert(second)
                }
            }
        }

        return idle
    }

    static func possessingTeam(in match: MatchState) -> TeamSide {
        if !match.isRunning {
            return match.currentPossession
        }

        return possessionFromEvents(
            in: match,
            sinceSeconds: match.possessionBaselineSeconds,
            baseline: match.possessionBaseline
        )
    }

    private static func possessionFromEvents(
        in match: MatchState,
        sinceSeconds: Int,
        baseline: TeamSide
    ) -> TeamSide {
        var possession = baseline

        struct TimedPossessionChange: Comparable {
            let seconds: Int
            let kind: Int
            let team: TeamSide

            static func < (lhs: TimedPossessionChange, rhs: TimedPossessionChange) -> Bool {
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                return lhs.kind < rhs.kind
            }
        }

        var changes: [TimedPossessionChange] = []

        for pass in match.passes where pass.matchSeconds >= sinceSeconds {
            changes.append(
                TimedPossessionChange(
                    seconds: pass.matchSeconds,
                    kind: 0,
                    team: gainingTeam(for: pass.type)
                )
            )
        }

        for goal in match.goals where goal.matchSeconds >= sinceSeconds {
            let kickoffTeam = goal.team.opposite
            changes.append(TimedPossessionChange(seconds: goal.matchSeconds, kind: 1, team: kickoffTeam))
        }

        for change in changes.sorted() {
            possession = change.team
        }

        return possession
    }

    static func canRecordPass(_ type: PassEventType, possession: TeamSide?) -> Bool {
        switch type {
        case .ourPass:
            possession != .away
        case .theirPass:
            possession != .home
        case .weIntercepted:
            possession == .away
        case .theyIntercepted:
            possession == .home
        case .homeBallOut:
            possession == .home
        case .awayBallOut:
            possession == .away
        case .possessionToHome:
            possession != .home
        case .possessionToAway:
            possession != .away
        }
    }

    static func ballOutType(for possession: TeamSide) -> PassEventType {
        possession == .home ? .homeBallOut : .awayBallOut
    }

    static func goalMarkers(for match: MatchState) -> [GoalChartMarker] {
        let events = events(from: match)
        var homeScore = 0
        var awayScore = 0

        return match.goals
            .sorted { $0.matchSeconds < $1.matchSeconds }
            .map { goal in
                switch goal.team {
                case .home: homeScore += 1
                case .away: awayScore += 1
                }
                return GoalChartMarker(
                    id: goal.id,
                    matchSeconds: goal.matchSeconds,
                    team: goal.team,
                    pressureValue: value(at: goal.matchSeconds, events: events),
                    homeScore: homeScore,
                    awayScore: awayScore,
                    creditedPlayerID: goal.creditedPlayerID,
                    placement: goal.placement
                )
            }
    }

    static func shotTicks(for match: MatchState) -> [ShotTickMarker] {
        // Same definition as the shots comparison bar: unscored corners are deliveries,
        // not attempts, so they must not appear in the tick strip either.
        match.shots
            .filter(countsAsShot)
            .sorted { $0.matchSeconds < $1.matchSeconds }
            .map { shot in
                ShotTickMarker(
                    id: shot.id,
                    matchSeconds: shot.matchSeconds,
                    team: shot.team,
                    difficulty: shot.difficulty,
                    isOnTarget: shot.outcome != .notOnTarget,
                    isGoal: shot.outcome == .goal,
                    creditedPlayerID: shot.creditedPlayerID
                )
            }
    }

    /// A corner is a delivery rather than an attempt, so it stays out of the shot
    /// totals unless it was scored — a scored corner is unambiguously a shot on target.
    static func countsAsShot(_ shot: ShotEvent) -> Bool {
        shot.difficulty != .corner || shot.outcome == .goal
    }

    /// Rendered on its own above the chart, standing in for the score line.
    static func goalsStat(for match: MatchState) -> ComparisonStat {
        .counts(
            label: "Goals",
            home: match.score(for: .home),
            away: match.score(for: .away)
        )
    }

    /// Sits directly under Goals in the header: score and possession are the two figures
    /// everyone already reads, so they lead before the match-flow chart.
    static func possessionStat(for match: MatchState) -> ComparisonStat {
        let possession = possessionPercentages(for: match)
        return ComparisonStat(
            label: "Possession",
            homeValue: Double(possession.home),
            awayValue: Double(possession.away),
            homeText: "\(possession.home)%",
            awayText: "\(possession.away)%",
            style: .share,
            alwaysVisible: true
        )
    }

    static func comparisonStats(for match: MatchState) -> [ComparisonStat] {
        func count(_ team: TeamSide, _ isIncluded: (ShotEvent) -> Bool) -> Int {
            match.shots.filter { $0.team == team && isIncluded($0) }.count
        }

        /// Hard + on-target is a defender foot block: on target, but never a keeper event.
        func isDefenderBlock(_ shot: ShotEvent) -> Bool {
            shot.difficulty == .hard && shot.outcome == .onTarget
        }

        func isKeeperOnTarget(_ shot: ShotEvent) -> Bool {
            shot.outcome == .onTarget && !isDefenderBlock(shot)
        }

        /// Shots the keeper faced, and how many were kept out. Defender blocks are excluded:
        /// the ball never became a keeper problem. Saves + goals conceded still equals
        /// opponent on-target shots that reached the keeper.
        func keeping(for team: TeamSide) -> (saves: Int, faced: Int) {
            let opponent: TeamSide = team == .home ? .away : .home
            let reachedKeeper = match.shots.filter {
                $0.team == opponent && countsAsShot($0) && (
                    $0.outcome == .goal || isKeeperOnTarget($0)
                )
            }
            return (reachedKeeper.filter(isKeeperOnTarget).count, reachedKeeper.count)
        }

        /// Easy chance stopped by the keeper — the glowing subset of the Saves bar.
        func bigSaves(by team: TeamSide) -> Int {
            let opponent: TeamSide = team == .home ? .away : .home
            return count(opponent) { $0.difficulty == .easy && $0.outcome == .onTarget }
        }

        /// On-target attempts stopped by an outfield defender (hard blocks only).
        func defended(by team: TeamSide) -> Int {
            let opponent: TeamSide = team == .home ? .away : .home
            return count(opponent, isDefenderBlock)
        }

        let candidates: [ComparisonStat] = [
            .subset(
                label: "Shots on target and total attempts",
                home: count(.home) { countsAsShot($0) && $0.outcome != .notOnTarget },
                homeOf: count(.home, countsAsShot),
                away: count(.away) { countsAsShot($0) && $0.outcome != .notOnTarget },
                awayOf: count(.away, countsAsShot)
            ),
            .counts(
                label: "Easy Chances Taken",
                home: count(.home) { $0.difficulty == .easy },
                away: count(.away) { $0.difficulty == .easy }
            ),
            .counts(
                label: "Shots blocked",
                home: defended(by: .home),
                away: defended(by: .away)
            ),
            .saves(
                label: "Saves",
                homeSaves: keeping(for: .home).saves,
                homeFaced: keeping(for: .home).faced,
                homeBig: bigSaves(by: .home),
                awaySaves: keeping(for: .away).saves,
                awayFaced: keeping(for: .away).faced,
                awayBig: bigSaves(by: .away)
            )
        ]

        return candidates.filter { $0.alwaysVisible || $0.homeValue > 0 || $0.awayValue > 0 }
    }
}

struct GoalChartMarker: Identifiable {
    let id: UUID
    let matchSeconds: Int
    let team: TeamSide
    let pressureValue: Double
    let homeScore: Int
    let awayScore: Int
    let creditedPlayerID: UUID?
    /// Where the goal came from and went in, once the recorder has placed it — the Goal Map
    /// on the Summary tab draws from this.
    let placement: ShotPlacement?

    var scoreLabel: String { "\(homeScore)-\(awayScore)" }

    var minuteLabel: String { "\((matchSeconds + 30) / 60)'" }
}

struct ShotTickMarker: Identifiable {
    let id: UUID
    let matchSeconds: Int
    let team: TeamSide
    let difficulty: ShotDifficulty
    let isOnTarget: Bool
    let isGoal: Bool
    let creditedPlayerID: UUID?

    /// The Easy row's on-target column is captioned "Big Save" on the Live tab
    /// (`ShotTileIcons.caption(for:)`) regardless of which team is shooting — the chart
    /// glows this tick either way. Only an away attempt is *creditable* though (see
    /// `isCreditableSave`), since crediting means it was our keeper who made the save.
    var isBigSave: Bool { difficulty == .easy && isOnTarget && !isGoal }

    /// A save our own keeper could have made — the only case with a credited-row face
    /// slot, since only the home roster exists. A home attempt saved by the opposing
    /// keeper is still a big save (still glows) but can never be credited to anyone.
    var isCreditableSave: Bool { isBigSave && team == .away }
}

enum ComparisonStatStyle {
    /// Bar splits proportionally, because the two values share one total.
    case share
    /// Each side fills its own half-track, because the values are independent
    /// percentages. A proportional split would flatten 87% vs 75% to near 50/50.
    case rate
    /// A total and a highlighted subset in one row: the full count is drawn dimmed in
    /// the team colour, with the subset lit up on top of it.
    case nested
    /// Keeper story: the bar is shots faced (saves in team colour + goals conceded in
    /// grey), with big saves glowing on the saves segment. Save rate lives in the text.
    case keeping
}

struct ComparisonStat: Identifiable {
    let id = UUID()
    let label: String
    let homeValue: Double
    let awayValue: Double
    let homeText: String
    let awayText: String
    var style: ComparisonStatStyle = .share
    var alwaysVisible: Bool = false
    var homeTotal: Double = 0
    var awayTotal: Double = 0
    /// Lit subset for `.keeping` (big saves). Unused by other styles.
    var homeGlow: Double = 0
    var awayGlow: Double = 0

    static func counts(label: String, home: Int, away: Int) -> ComparisonStat {
        ComparisonStat(
            label: label,
            homeValue: Double(home),
            awayValue: Double(away),
            homeText: "\(home)",
            awayText: "\(away)"
        )
    }

    static func percentages(
        label: String,
        home: Int,
        away: Int,
        style: ComparisonStatStyle
    ) -> ComparisonStat {
        ComparisonStat(
            label: label,
            homeValue: Double(home),
            awayValue: Double(away),
            homeText: "\(home)%",
            awayText: "\(away)%",
            style: style
        )
    }

    /// Share of the bar the home team fills. Falls back to an even split when
    /// neither team has registered anything.
    var homeFraction: Double {
        let total = homeValue + awayValue
        guard total > 0 else { return 0.5 }
        return homeValue / total
    }

    /// Fractions for `.nested` / `.keeping`, all measured against the combined totals so
    /// the segments line up across both sides of the row.
    private var combinedTotal: Double { homeTotal + awayTotal }

    var homeTotalFraction: Double {
        guard combinedTotal > 0 else { return 0.5 }
        return homeTotal / combinedTotal
    }

    var awayTotalFraction: Double {
        guard combinedTotal > 0 else { return 0.5 }
        return awayTotal / combinedTotal
    }

    var homeSubsetFraction: Double {
        guard combinedTotal > 0 else { return 0 }
        return homeValue / combinedTotal
    }

    var awaySubsetFraction: Double {
        guard combinedTotal > 0 else { return 0 }
        return awayValue / combinedTotal
    }

    var homeGlowFraction: Double {
        guard combinedTotal > 0 else { return 0 }
        return homeGlow / combinedTotal
    }

    var awayGlowFraction: Double {
        guard combinedTotal > 0 else { return 0 }
        return awayGlow / combinedTotal
    }

    /// Goals that got past the keeper — the grey remainder of a `.keeping` bar.
    var homeConcededFraction: Double {
        max(homeTotalFraction - homeSubsetFraction, 0)
    }

    var awayConcededFraction: Double {
        max(awayTotalFraction - awaySubsetFraction, 0)
    }

    static func subset(
        label: String,
        home: Int,
        homeOf: Int,
        away: Int,
        awayOf: Int
    ) -> ComparisonStat {
        ComparisonStat(
            label: label,
            homeValue: Double(home),
            awayValue: Double(away),
            homeText: "\(home)/\(homeOf)",
            awayText: "\(away)/\(awayOf)",
            style: .nested,
            homeTotal: Double(homeOf),
            awayTotal: Double(awayOf)
        )
    }

    /// One row for the keeper story: save rate leads the text, the bar is shots faced
    /// (saves + goals conceded), and big saves only appear in the copy when there was one.
    static func saves(
        label: String,
        homeSaves: Int,
        homeFaced: Int,
        homeBig: Int,
        awaySaves: Int,
        awayFaced: Int,
        awayBig: Int
    ) -> ComparisonStat {
        func rate(saves: Int, faced: Int) -> Int {
            guard faced > 0 else { return 0 }
            return Int((Double(saves) / Double(faced) * 100).rounded())
        }

        func text(saves: Int, faced: Int, big: Int) -> String {
            let rateText = "\(rate(saves: saves, faced: faced))%"
            if big > 0 {
                return "\(rateText) · \(saves) saves · \(big) big"
            }
            return "\(rateText) · \(saves) saves"
        }

        return ComparisonStat(
            label: label,
            homeValue: Double(homeSaves),
            awayValue: Double(awaySaves),
            homeText: text(saves: homeSaves, faced: homeFaced, big: homeBig),
            awayText: text(saves: awaySaves, faced: awayFaced, big: awayBig),
            style: .keeping,
            alwaysVisible: homeFaced > 0 || awayFaced > 0,
            homeTotal: Double(homeFaced),
            awayTotal: Double(awayFaced),
            homeGlow: Double(homeBig),
            awayGlow: Double(awayBig)
        )
    }
}

struct PressureChartPoint: Identifiable {
    let id = UUID()
    let matchSeconds: Int
    let value: Double

    var minuteLabel: String {
        let minutes = matchSeconds / 60
        let secs = matchSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
