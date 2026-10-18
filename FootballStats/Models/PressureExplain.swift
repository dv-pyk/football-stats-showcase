import Foundation

/// A parallel, human-readable record of the same walk `PressureEngine.events(from:)`
/// performs — same weights, same inferred-steal logic, same decay. Nothing here changes what
/// the index scores; it only narrates it. Built for `PressureLaneView` and the ledger sheet
/// (HANDOFF-live-screen.md §3–4), which implement the BACKBURNER entry *"In-app feedback for
/// what the scoring logic is doing."*
extension PressureEngine {
    enum ExplainedKind {
        case pass(count: Int)          // rolled up per spell — contiguous same-team passes
        case steal(inferred: Bool)
        case turnoverNoSteal(gap: TimeInterval)
        case shot(ShotDifficulty, ShotOutcome)
        case setPiece(SetPieceKind)
        case goal
    }

    struct Explained: Identifiable {
        let id = UUID()
        let seconds: TimeInterval      // match clock, for the row's timestamp
        let team: TeamSide
        let kind: ExplainedKind
        let delta: Double              // signed, exactly as fed to value(at:)
        let reason: String?            // nil where the weight is self-evident (a pass)
        /// The underlying `PassEvent`/`ShotEvent`/`SetPieceEvent` id(s) this row is built
        /// from — one, except a rolled-up `.pass` group, which carries every member's id so
        /// the ledger can undo an individual tap without needing to re-derive it later.
        let eventIDs: [UUID]
    }

    /// Same single walk as `events(from:)`, emitting an `Explained` per event. Cheap enough
    /// to recompute on demand — do NOT cache it on the match. Only covers the last
    /// `PressureWeight.lookbackSeconds`, matching the ledger's own "everything older has
    /// dropped out" scope.
    ///
    /// `rollUpPasses` merges contiguous same-team passes within a spell into one row (§4 — a
    /// real two-minute window is ~60 taps and almost all of them are passes) — the default,
    /// used everywhere except the ledger's "Every tap" view.
    static func explained(for match: MatchState, endingAt: TimeInterval, rollUpPasses: Bool = true) -> [Explained] {
        var raw: [Explained] = []

        for pass in match.passes {
            switch pass.type {
            case .ourPass:
                raw.append(Explained(seconds: TimeInterval(pass.matchSeconds), team: .home, kind: .pass(count: 1), delta: PressureWeight.pass, reason: nil, eventIDs: [pass.id]))
            case .theirPass:
                raw.append(Explained(seconds: TimeInterval(pass.matchSeconds), team: .away, kind: .pass(count: 1), delta: -PressureWeight.pass, reason: nil, eventIDs: [pass.id]))
            case .weIntercepted:
                raw.append(Explained(seconds: TimeInterval(pass.matchSeconds), team: .home, kind: .steal(inferred: false), delta: PressureWeight.intercept, reason: "Tapped as an interception", eventIDs: [pass.id]))
            case .theyIntercepted:
                raw.append(Explained(seconds: TimeInterval(pass.matchSeconds), team: .away, kind: .steal(inferred: false), delta: -PressureWeight.intercept, reason: "Tapped as an interception", eventIDs: [pass.id]))
            case .homeBallOut, .awayBallOut, .possessionToHome, .possessionToAway:
                break // resolved below, once we know whether each was claimed as a steal
            }
        }

        let stealWindow = PressureWeight.inferredStealWindowSeconds(rulesVersion: match.rulesVersion)
        let steals = explainedSteals(in: match.passes, stealWindowSeconds: stealWindow)
        let claimedSeconds = Set(steals.map(\.seconds))

        for steal in steals {
            let sign: Double = steal.team == .home ? 1 : -1
            let teamName = steal.team == .home ? match.homeTeamName : match.awayTeamName
            raw.append(Explained(
                seconds: TimeInterval(steal.seconds),
                team: steal.team,
                kind: .steal(inferred: true),
                delta: sign * PressureWeight.intercept,
                reason: "\(teamName) passed \(formatSeconds(TimeInterval(steal.gapSeconds)))s after the turnover, inside the \(stealWindow)s window",
                eventIDs: [steal.id]
            ))
        }

        for pass in match.passes {
            let isTurnoverType: Bool
            switch pass.type {
            case .possessionToHome, .possessionToAway, .homeBallOut, .awayBallOut: isTurnoverType = true
            default: isTurnoverType = false
            }
            guard isTurnoverType, !claimedSeconds.contains(pass.matchSeconds) else { continue }

            // Ball-out taps can never be claimed as a steal (see `inferredSteals`), so they
            // resolve immediately. A neutral possession-change tap only resolves once its
            // window has closed with nothing claiming it.
            let isBallOut = pass.type == .homeBallOut || pass.type == .awayBallOut
            let windowClosed = endingAt - TimeInterval(pass.matchSeconds) >= TimeInterval(stealWindow)
            guard isBallOut || windowClosed else { continue }

            let laterPass = match.passes.map(\.matchSeconds).filter { $0 > pass.matchSeconds }.min()
            let gap = TimeInterval((laterPass ?? Int(endingAt)) - pass.matchSeconds)
            raw.append(Explained(
                seconds: TimeInterval(pass.matchSeconds),
                team: gainingTeam(for: pass.type),
                kind: .turnoverNoSteal(gap: gap),
                delta: 0,
                reason: "No pass for \(formatSeconds(gap))s — read as ball out, not a steal",
                eventIDs: [pass.id]
            ))
        }

        for shot in match.shots {
            let sign: Double = shot.team == .home ? 1 : -1
            var weight: Double
            switch shot.outcome {
            case .goal: weight = PressureWeight.goal
            case .onTarget: weight = PressureWeight.shotOnTarget
            case .notOnTarget: weight = PressureWeight.shotOffTarget
            }
            if shot.difficulty == .corner {
                weight += PressureWeight.cornerBonus
            }
            let kind: ExplainedKind = shot.outcome == .goal ? .goal : .shot(shot.difficulty, shot.outcome)
            raw.append(Explained(
                seconds: TimeInterval(shot.matchSeconds),
                team: shot.team,
                kind: kind,
                delta: sign * weight,
                reason: fadeReason(matchSeconds: shot.matchSeconds, endingAt: endingAt, match: match),
                eventIDs: [shot.id]
            ))
        }

        for setPiece in match.setPieces {
            let sign: Double = setPiece.team == .home ? 1 : -1
            let reason = setPiece.kind == .penalty
                ? "Penalties convert far more often than a corner"
                : "Credited when you tapped it, not when it's taken"
            raw.append(Explained(
                seconds: TimeInterval(setPiece.matchSeconds),
                team: setPiece.team,
                kind: .setPiece(setPiece.kind),
                delta: sign * PressureWeight.setPieceWeight(for: setPiece.kind),
                reason: reason,
                eventIDs: [setPiece.id]
            ))
        }

        let inWindow = raw
            .filter { $0.seconds <= endingAt && endingAt - $0.seconds <= TimeInterval(PressureWeight.lookbackSeconds) }
            .sorted { $0.seconds < $1.seconds }

        return rollUpPasses ? groupPasses(inWindow) : inWindow
    }

    /// Merges adjacent same-team `.pass` entries into one row — see `explained(for:endingAt:)`.
    private static func groupPasses(_ entries: [Explained]) -> [Explained] {
        var merged: [Explained] = []

        for entry in entries {
            if case .pass(let count) = entry.kind,
               let last = merged.last,
               case .pass(let lastCount) = last.kind,
               last.team == entry.team {
                merged[merged.count - 1] = Explained(
                    seconds: last.seconds,
                    team: last.team,
                    kind: .pass(count: lastCount + count),
                    delta: last.delta + entry.delta,
                    reason: nil,
                    eventIDs: last.eventIDs + entry.eventIDs
                )
            } else {
                merged.append(entry)
            }
        }

        return merged
    }

    /// Same walk as `inferredSteals`, but also captures the measured gap between the
    /// turnover and the pass that claimed it, plus the turnover tap's own id, for the
    /// lane/ledger's reason text and undo.
    private static func explainedSteals(
        in passes: [PassEvent],
        stealWindowSeconds: Int
    ) -> [(seconds: Int, team: TeamSide, gapSeconds: Int, id: UUID)] {
        let ordered = passes.enumerated().sorted {
            if $0.element.matchSeconds != $1.element.matchSeconds {
                return $0.element.matchSeconds < $1.element.matchSeconds
            }
            return $0.offset < $1.offset
        }

        var claimed: Set<Int> = []
        var steals: [(seconds: Int, team: TeamSide, gapSeconds: Int, id: UUID)] = []

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
                        steals.append((prior.element.matchSeconds, team, gap, prior.element.id))
                    }
                    break priorSearch
                case .possessionToHome, .possessionToAway,
                     .weIntercepted, .theyIntercepted,
                     .homeBallOut, .awayBallOut:
                    break priorSearch
                case .ourPass, .theirPass:
                    continue priorSearch
                }
            }
        }

        return steals
    }

    /// "Faded to 82% by now", or "Drops out of the index at 25:12" once within 20s of the
    /// 120s cutoff — matches the decay `value(at:events:)` actually applies.
    private static func fadeReason(matchSeconds: Int, endingAt: TimeInterval, match: MatchState) -> String {
        let age = endingAt - TimeInterval(matchSeconds)
        let remaining = TimeInterval(PressureWeight.lookbackSeconds) - age

        if remaining <= 20 {
            let dropSeconds = matchSeconds + PressureWeight.lookbackSeconds
            return "Drops out of the index at \(match.formattedClock(from: dropSeconds))"
        }

        let fade = 1.0 - (age / TimeInterval(PressureWeight.lookbackSeconds)) * 0.6
        return "Faded to \(Int((fade * 100).rounded()))% by now"
    }

    private static func formatSeconds(_ value: TimeInterval) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    // MARK: - Live lane state

    struct PendingSteal {
        let team: TeamSide
        let remainingFraction: Double
    }

    /// The open possession-change whose steal window hasn't closed yet, if any. Deliberately
    /// takes the same inputs `MatchViewModel.interceptStrength(at:)` already threads through
    /// (wall-clock `windowStart`/`now`, not match-clock) and applies the identical formula,
    /// so the lane's bar and the Pass button's bar can never show two different countdowns
    /// for what is the same window.
    static func pendingSteal(
        windowStart: Date?,
        windowSeconds: Double,
        team: TeamSide,
        now: Date
    ) -> PendingSteal? {
        guard let windowStart else { return nil }
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed >= 0, elapsed <= windowSeconds else { return nil }
        return PendingSteal(team: team, remainingFraction: max(0, 1 - elapsed / windowSeconds))
    }

    /// Seconds since the last recorded tap of any kind (pass or shot — the same definition
    /// `possessionPercentages` uses internally), so the lane can say when the 25s+
    /// possession-% exclusion (`PressureWeight.possessionIdleGapSeconds`) has kicked in.
    /// This is deliberately possession-only: per `PRESSURE_INDEX.md`, the index itself has no
    /// stoppage concept, and this helper must not be used to change that — only to say it.
    static func idleGapSeconds(for match: MatchState, at seconds: Int) -> Int {
        var marks = Set(match.passes.map(\.matchSeconds))
        marks.formUnion(match.shots.map(\.matchSeconds))
        guard let last = marks.filter({ $0 <= seconds }).max() else { return seconds }
        return seconds - last
    }
}
