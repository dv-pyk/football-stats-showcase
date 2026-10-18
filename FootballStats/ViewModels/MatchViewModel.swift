import Combine
import Foundation
import SwiftUI

@MainActor
final class MatchViewModel: ObservableObject {
    @Published var match: MatchState {
        didSet { refreshInterceptWindow() }
    }
    @Published var selectedTab: MatchTab = .live

    /// Set the moment a possession change is observed, so the pass button can briefly
    /// offer to log the follow-up as an interception. Cleared once the window lapses.
    @Published private(set) var interceptWindowStart: Date?

    /// Wall-clock time of the most recent notable pressure event — a shot, a set piece, or a
    /// steal window resolving one way or the other. Drives `PressureLaneView`'s brief
    /// highlight; ordinary passes don't touch it, only the things worth narrating do.
    @Published private(set) var lastNotableEventAt: Date?

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let isReadOnly: Bool
    private var storeAcknowledgedRevision: UInt64 = 0
    private var storeSyncTimer: Timer?
    /// True from `startNewMatch()` until `finishMatch()`. Guards `flushToStore()` so a
    /// scenePhase background/inactive transition after End & Save (but before the next
    /// match starts) can't re-persist the just-finished match into the shared store and
    /// have it get resumed as "active" on next launch.
    private var hasActiveMatch = false
    /// How many possession-change taps we've already reacted to. Count (not UUID) so a
    /// reload that remints pass ids doesn't look like a fresh steal window.
    private var lastSeenPossessionChangeCount = 0
    private var interceptWindowTask: Task<Void, Never>?

    enum MatchTab: String, CaseIterable, Identifiable {
        case history = "History"
        case live = "Live"
        case summary = "Summary"

        var id: String { rawValue }
    }

    init(match: MatchState = .empty, isReadOnly: Bool = false) {
        self.isReadOnly = isReadOnly
        if isReadOnly {
            self.match = match
        } else {
            let resumed = ActiveMatchStore.shared.load()
            self.match = resumed ?? match
            hasActiveMatch = resumed != nil
            storeAcknowledgedRevision = ActiveMatchStore.shared.latestRevision
        }

        // Seed the tracker so an already-recorded change on a resumed match doesn't get
        // mistaken for a fresh one the first time `match` mutates.
        lastSeenPossessionChangeCount = Self.possessionChangeCount(in: self.match.passes)

        guard !isReadOnly else { return }

        NotificationCenter.default.publisher(for: .activeMatchDidUpdateExternally)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromActiveStoreIfNeeded()
            }
            .store(in: &cancellables)

        ActiveMatchCrossProcessNotifier.startListening { [weak self] in
            self?.syncFromActiveStoreIfNeeded()
        }

        startStoreSyncTimer()
    }

    private func startStoreSyncTimer() {
        storeSyncTimer?.invalidate()
        storeSyncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromActiveStoreIfNeeded()
            }
        }
    }

    private func stopStoreSyncTimer() {
        storeSyncTimer?.invalidate()
        storeSyncTimer = nil
    }

    deinit {
        timer?.invalidate()
        storeSyncTimer?.invalidate()
    }

    // MARK: - Match lifecycle

    func startNewMatch(
        home: String,
        away: String,
        kickoffTiming: KickoffTimingMode = .live,
        gameFormat: GameFormat = .outdoor,
        kickoff: Date = Date()
    ) {
        pauseClock()
        match = MatchState(
            homeTeamName: home.isEmpty ? PresetHomeTeam.defaultName : home,
            awayTeamName: away.isEmpty ? "Opposition" : away,
            kickoffDate: kickoff,
            kickoffTimingMode: kickoffTiming,
            gameFormat: gameFormat,
            isRunning: false,
            elapsedSeconds: 0,
            shots: [],
            passes: [],
            currentPossession: .home,
            possessionBaseline: .home,
            possessionBaselineSeconds: 0,
            rulesVersion: MatchRulesVersion.current
        )
        selectedTab = .live
        hasActiveMatch = true
        persistMatch(force: true)
        startStoreSyncTimer()
    }

    func resumePersistedMatchIfNeeded() {
        syncFromActiveStoreIfNeeded()
    }

    func syncFromActiveStoreIfNeeded() {
        guard !isReadOnly else { return }

        let latestRevision = ActiveMatchStore.shared.latestRevision
        guard latestRevision > storeAcknowledgedRevision,
              let stored = ActiveMatchStore.shared.load() else {
            return
        }

        storeAcknowledgedRevision = ActiveMatchStore.shared.latestRevision
        guard stored != match else { return }
        match = stored
    }

    func flushToStore() {
        guard hasActiveMatch else { return }
        persistMatch(force: true)
    }

    func toggleClock() {
        if match.isRunning {
            pauseClock()
        } else {
            startClock()
        }
    }

    func startClock() {
        guard !match.isRunning else { return }
        applyMatchChange { match in
            if match.kickoffTimingMode == .live && match.elapsedSeconds == 0 {
                match.kickoffDate = Date()
            }
            match.possessionBaseline = match.currentPossession
            match.possessionBaselineSeconds = match.elapsedSeconds
            match.isRunning = true
        }
        persistMatch()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func pauseClock() {
        applyMatchChange { match in
            if match.isRunning {
                match.currentPossession = PressureEngine.possessingTeam(in: match)
            }
            match.isRunning = false
        }
        timer?.invalidate()
        timer = nil
        persistMatch()
    }

    func stopTimer() {
        pauseClock()
    }

    func finishMatch() {
        pauseClock()
        stopStoreSyncTimer()
        ActiveMatchStore.shared.clear()
        storeAcknowledgedRevision = 0
        hasActiveMatch = false
    }

    private func applyMatchChange(_ transform: (inout MatchState) -> Void, recordEvent: Bool = false) {
        var updated = match
        transform(&updated)
        match = updated
        if recordEvent {
            recordMatchEvent()
        }
    }

    private func tick() {
        applyMatchChange { $0.elapsedSeconds += 1 }
        if match.elapsedSeconds % 5 == 0 {
            persistMatch()
        }
    }

    private func persistMatch(force: Bool = false) {
        if force {
            ActiveMatchStore.shared.save(match)
            storeAcknowledgedRevision = ActiveMatchStore.shared.latestRevision
            return
        }

        if ActiveMatchStore.shared.saveFromApp(match, acknowledgedRevision: storeAcknowledgedRevision) {
            storeAcknowledgedRevision = ActiveMatchStore.shared.latestRevision
        } else {
            syncFromActiveStoreIfNeeded()
        }
    }

    private func recordMatchEvent() {
        persistMatch()
    }

    func adjustClock(by seconds: Int) {
        applyMatchChange({ $0.elapsedSeconds = max(0, $0.elapsedSeconds + seconds) }, recordEvent: true)
    }

    // MARK: - Shots

    @discardableResult
    func addShot(team: TeamSide, difficulty: ShotDifficulty, outcome: ShotOutcome) -> ShotEvent {
        let shot = ShotEvent(
            team: team,
            difficulty: difficulty,
            outcome: outcome,
            matchSeconds: match.elapsedSeconds
        )
        applyMatchChange({ match in
            match.shots.append(shot)
        }, recordEvent: true)
        lastNotableEventAt = Date()
        HapticFeedback.record()
        return shot
    }

    func undoLastShot() {
        applyMatchChange({ match in
            _ = match.shots.popLast()
        }, recordEvent: true)
    }

    /// Credits a goal or big save to a roster player, or clears the credit (`playerID: nil`).
    /// `id` is the `ShotEvent`'s id — safe to call whether `self` is the live match or a
    /// read-only historical one (`applyMatchChange` isn't gated by `isReadOnly`); the
    /// caller is responsible for persisting a historical match back to `MatchHistoryStore`.
    func creditShot(id: UUID, playerID: UUID?) {
        applyMatchChange({ match in
            guard let index = match.shots.firstIndex(where: { $0.id == id }) else { return }
            match.shots[index].creditedPlayerID = playerID
        }, recordEvent: true)
    }

    /// Records where a goal was shot from and where it went in, or clears it (`placement: nil`).
    /// `id` is the scoring `ShotEvent`'s id; same caller-persists contract as `creditShot`.
    func placeShot(id: UUID, placement: ShotPlacement?) {
        applyMatchChange({ match in
            guard let index = match.shots.firstIndex(where: { $0.id == id }) else { return }
            match.shots[index].placement = placement
        }, recordEvent: true)
    }

    /// Goal Map view settings — saved with the match (`MatchState.goalMapFlipped`), so the
    /// caller persists a reviewed history match the same way as for `placeShot`.
    func setGoalMapFlipped(_ flipped: Bool) {
        applyMatchChange({ $0.goalMapFlipped = flipped }, recordEvent: true)
    }

    func setGoalMapSurface(_ surface: GoalMapSurface) {
        applyMatchChange({ $0.goalMapSurface = surface }, recordEvent: true)
    }

    // MARK: - Set pieces

    func recordSetPiece(_ kind: SetPieceKind) {
        applyMatchChange({ match in
            match.setPieces.append(
                SetPieceEvent(
                    kind: kind,
                    team: possessingTeam,
                    matchSeconds: match.elapsedSeconds
                )
            )
        }, recordEvent: true)
        lastNotableEventAt = Date()
        HapticFeedback.record()
    }

    // MARK: - Passes & pressure

    var ballPossession: TeamSide? {
        PressureEngine.possessingTeam(in: match)
    }

    var shootingTeam: TeamSide? {
        ballPossession
    }

    func shootingTeamName(for team: TeamSide) -> String {
        team.label(homeName: match.homeTeamName, awayName: match.awayTeamName)
    }

    var currentPressure: Double {
        PressureEngine.currentPressure(from: match)
    }

    func canRecordPass(_ type: PassEventType) -> Bool {
        PressureEngine.canRecordPass(type, possession: ballPossession)
    }

    func recordPass(_ type: PassEventType) {
        guard canRecordPass(type) else { return }
        applyMatchChange({ match in
            match.passes.append(PassEvent(type: type, matchSeconds: match.elapsedSeconds))
        }, recordEvent: true)
        // A tap during the steal window has already claimed the intercept — snap the
        // button back to Pass rather than leaving "Intercept" up for the leftover time.
        if type == .ourPass || type == .theirPass {
            clearInterceptWindow(resolved: true)
        }
        HapticFeedback.record()
    }

    func recordBallOut() {
        guard let possession = ballPossession else { return }
        recordPass(PressureEngine.ballOutType(for: possession))
    }

    func recordPossessionChange() {
        let type = MatchEventProcessor.possessionChangeType(for: possessingTeam)
        recordPass(type)
    }

    // MARK: - Intercept affordance

    /// How long after a possession change a pass still reads as a steal. Mirrors the
    /// engine's inference window so the button's promise matches what the chart records.
    var interceptWindowSeconds: Double {
        Double(PressureWeight.inferredStealWindowSeconds(rulesVersion: match.rulesVersion))
    }

    /// How strongly the pass button should present as "Intercept" right now: 1 the instant
    /// the window opens, easing linearly to 0 across the *entire* window rather than
    /// holding at full strength and only fading over a short tail. Driven from a passed-in
    /// `now` so the view can animate it with a timeline.
    func interceptStrength(at now: Date) -> Double {
        guard let start = interceptWindowStart else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 0, elapsed <= interceptWindowSeconds else { return 0 }

        return max(0, 1 - elapsed / interceptWindowSeconds)
    }

    // MARK: - Pressure lane

    /// The open possession-change whose steal window hasn't closed yet, if any — same clock
    /// as `interceptStrength(at:)` so `PressureLaneView`'s bar and the Pass button's bar
    /// deplete together (HANDOFF-live-screen.md §3).
    func pendingSteal(at now: Date) -> PressureEngine.PendingSteal? {
        PressureEngine.pendingSteal(
            windowStart: interceptWindowStart,
            windowSeconds: interceptWindowSeconds,
            team: possessingTeam,
            now: now
        )
    }

    /// The most recent turning-point event worth narrating in the lane — skips plain passes,
    /// which are rolled up rather than shown on their own (`PressureEngine.explained`).
    var lastNotableExplained: PressureEngine.Explained? {
        PressureEngine.explained(for: match, endingAt: TimeInterval(match.elapsedSeconds))
            .last { entry in
                if case .pass = entry.kind { return false }
                return true
            }
    }

    /// Seconds since the last recorded tap of any kind, for the lane's "Quiet 0:31" state.
    var idleGapSeconds: Int {
        PressureEngine.idleGapSeconds(for: match, at: match.elapsedSeconds)
    }

    /// The full narration for `PressureLedgerView`. `rollUpPasses: false` is the sheet's
    /// "Every tap" view — see `PressureEngine.explained(for:endingAt:rollUpPasses:)`.
    func explained(rollUpPasses: Bool) -> [PressureEngine.Explained] {
        PressureEngine.explained(for: match, endingAt: TimeInterval(match.elapsedSeconds), rollUpPasses: rollUpPasses)
    }

    /// Removes the specific tap(s) behind one ledger row and recomputes — routed through
    /// `applyMatchChange` like `undoLastShot`/`undoLastPass` so the App Group store and the
    /// widget stay in sync rather than being mutated out from under them.
    func removeExplained(_ entry: PressureEngine.Explained) {
        switch entry.kind {
        case .pass, .steal, .turnoverNoSteal:
            removePasses(ids: entry.eventIDs)
        case .shot, .goal:
            removeShots(ids: entry.eventIDs)
        case .setPiece:
            removeSetPieces(ids: entry.eventIDs)
        }
    }

    private func removePasses(ids: [UUID]) {
        let idSet = Set(ids)
        applyMatchChange({ match in
            match.passes.removeAll { idSet.contains($0.id) }
        }, recordEvent: true)
    }

    private func removeShots(ids: [UUID]) {
        let idSet = Set(ids)
        applyMatchChange({ match in
            match.shots.removeAll { idSet.contains($0.id) }
        }, recordEvent: true)
    }

    private func removeSetPieces(ids: [UUID]) {
        let idSet = Set(ids)
        applyMatchChange({ match in
            match.setPieces.removeAll { idSet.contains($0.id) }
        }, recordEvent: true)
    }

    private static func possessionChangeCount(in passes: [PassEvent]) -> Int {
        passes.reduce(0) { count, pass in
            (pass.type == .possessionToHome || pass.type == .possessionToAway) ? count + 1 : count
        }
    }

    /// `resolved` marks a window that was actually open closing one way or another (a
    /// confirming pass, or the timeout firing with nothing) — the moment `PressureLaneView`
    /// should treat as a fresh notable event. The undo-driven cleanup in
    /// `refreshInterceptWindow` below isn't a narrated event, so it leaves this false.
    private func clearInterceptWindow(resolved: Bool = false) {
        if resolved, interceptWindowStart != nil {
            lastNotableEventAt = Date()
        }
        interceptWindowTask?.cancel()
        interceptWindowTask = nil
        interceptWindowStart = nil
    }

    private func refreshInterceptWindow() {
        guard !isReadOnly else { return }

        let count = Self.possessionChangeCount(in: match.passes)
        guard count != lastSeenPossessionChangeCount else { return }
        let gained = count > lastSeenPossessionChangeCount
        lastSeenPossessionChangeCount = count

        guard gained else {
            clearInterceptWindow()
            return
        }

        interceptWindowStart = Date()
        interceptWindowTask?.cancel()
        let nanoseconds = UInt64((interceptWindowSeconds + 0.4) * 1_000_000_000)
        interceptWindowTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.clearInterceptWindow(resolved: true) }
        }
    }

    var possessingTeam: TeamSide {
        ballPossession ?? .home
    }

    func possessionPanelDisplay() -> (label: String, color: Color) {
        let team = possessingTeam
        return (
            shortTeamName(shootingTeamName(for: team)),
            team == .home ? .green : .orange
        )
    }

    func passButtonDisplay() -> (type: PassEventType, title: String, interceptTitle: String, color: Color, isEnabled: Bool) {
        let team = possessingTeam
        switch team {
        case .home:
            return (
                .ourPass,
                "\(shortTeamName(match.homeTeamName))\nPass",
                "\(shortTeamName(match.homeTeamName))\nIntercept",
                .green,
                canRecordPass(.ourPass)
            )
        case .away:
            return (
                .theirPass,
                "\(shortTeamName(match.awayTeamName))\nPass",
                "\(shortTeamName(match.awayTeamName))\nIntercept",
                .orange,
                canRecordPass(.theirPass)
            )
        }
    }

    private func shortTeamName(_ name: String) -> String {
        TeamDisplayNames.short(name)
    }

    private func fullTeamName(_ name: String) -> String {
        TeamDisplayNames.full(name)
    }

    func canRecordBallOut() -> Bool {
        ballPossession != nil
    }

    func ballOutButtonTitle() -> String {
        guard let possession = ballPossession else { return "Out of Play" }
        let loser = shootingTeamName(for: possession)
        let winner = shootingTeamName(for: possession == .home ? .away : .home)
        return "Out of Play\n\(loser) → \(winner)"
    }

    func undoLastPass() {
        applyMatchChange({ match in
            _ = match.passes.popLast()
        }, recordEvent: true)
    }

    // MARK: - Summaries

    func goalTimelineText() -> String {
        let kickoff = match.kickoffDate
        var homeScore = 0
        var awayScore = 0
        var lines: [String] = []

        for goal in match.goals {
            switch goal.team {
            case .home: homeScore += 1
            case .away: awayScore += 1
            }
            let goalTime = kickoff.addingTimeInterval(TimeInterval(goal.matchSeconds))
            let timeString = Self.timeFormatter.string(from: goalTime)
            lines.append("\(timeString) \(homeScore)-\(awayScore)")
        }

        return lines.joined(separator: "\n")
    }

    var matchObservations: [String] {
        MatchObservationEngine.observations(for: match, ourTeam: .home)
    }

    var standoutMoments: [String] {
        StandoutMomentEngine.moments(for: match)
    }

    var standoutMomentsCopyText: String {
        standoutMoments.map { "• \($0)" }.joined(separator: "\n")
    }

    func shotSummaryText(for team: TeamSide) -> String {
        let summary = shotSummary(for: team)
        var lines: [String] = []
        for line in summary.lines where line.total > 0 {
            lines.append(
                "• \(line.difficulty.rawValue): \(line.total) (\(line.goals) goals, \(line.notOnTarget) not on target)"
            )
        }
        lines.append("• Total: \(summary.totalAttempts) attempts, \(summary.totalGoals) goals")
        return lines.joined(separator: "\n")
    }

    var observationsCopyText: String {
        matchObservations.map { "• \($0)" }.joined(separator: "\n")
    }

    func pressureIndexCopyText() -> String {
        let homeScore = match.score(for: .home)
        let awayScore = match.score(for: .away)
        return """
        \(TeamDisplayNames.versusTitle(home: match.homeTeamName, away: match.awayTeamName))
        Score: \(homeScore)-\(awayScore) at \(match.currentClock)
        """
    }

    func shotSummary(for team: TeamSide) -> TeamShotSummary {
        let teamShots = match.shots.filter { $0.team == team }
        let teamName = fullTeamName(team.label(homeName: match.homeTeamName, awayName: match.awayTeamName))

        let lines = ShotDifficulty.allCases.map { difficulty in
            let filtered = teamShots.filter { $0.difficulty == difficulty }
            return ShotSummaryLine(
                difficulty: difficulty,
                total: filtered.count,
                goals: filtered.filter { $0.outcome == .goal }.count,
                notOnTarget: filtered.filter { $0.outcome == .notOnTarget }.count
            )
        }

        return TeamShotSummary(
            teamName: teamName,
            lines: lines,
            totalAttempts: teamShots.count,
            totalGoals: teamShots.filter { $0.outcome == .goal }.count
        )
    }

    /// The score, timeline and shot breakdown all live in the shared image now, so the
    /// accompanying text is standout moments (the headline, if any) plus observations.
    /// The image itself doesn't show standout moments yet — text only for now.
    func whatsAppSummary() -> String {
        var sections: [String] = []

        if !standoutMoments.isEmpty {
            sections.append((["Standout Moments"] + standoutMoments.map { "• \($0)" }).joined(separator: "\n"))
        }

        if !matchObservations.isEmpty {
            sections.append((["Observations — \(fullTeamName(match.homeTeamName))"] + matchObservations.map { "• \($0)" }).joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    /// Possession now appears in the comparison bars, so the in-chart labels stay
    /// as plain team names.
    var pressureChartLabels: (home: String, away: String) {
        (fullTeamName(match.homeTeamName), fullTeamName(match.awayTeamName))
    }

    var pressureChartPoints: [PressureChartPoint] {
        PressureEngine.chartPoints(for: match)
    }

    var goalChartMarkers: [GoalChartMarker] {
        PressureEngine.goalMarkers(for: match)
    }

    var shotTickMarkers: [ShotTickMarker] {
        PressureEngine.shotTicks(for: match)
    }

    var comparisonStats: [ComparisonStat] {
        PressureEngine.comparisonStats(for: match)
    }

    var goalsStat: ComparisonStat {
        PressureEngine.goalsStat(for: match)
    }

    var possessionStat: ComparisonStat {
        PressureEngine.possessionStat(for: match)
    }

    var recentPressureBuckets: [Double] {
        PressureEngine.recentPressureBuckets(for: match)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
