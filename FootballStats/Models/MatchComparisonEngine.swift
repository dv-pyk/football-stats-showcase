import Foundation

enum MatchComparisonEngine {
    static func trendLines(
        for match: MatchState,
        in history: [SavedMatch],
        excludingSavedMatchId: UUID? = nil,
        maxPriorMatches: Int = 2
    ) -> [String] {
        let prior = history
            .filter { $0.match.homeTeamName == match.homeTeamName && $0.id != excludingSavedMatchId }
            .prefix(maxPriorMatches)
            .map(\.match)
            .reversed()

        let series = prior + [match]
        guard series.count >= 2 else { return [] }

        var lines: [String] = []
        let matchCount = series.count

        lines.append("Trend — last \(matchCount) \(match.homeTeamName) matches (oldest → newest):")

        if let trend = formattedTrend(series.map { $0.score(for: .home) }, label: "Goals scored") {
            lines.append(trend)
        }

        if let trend = formattedTrend(series.map { $0.score(for: .away) }, label: "Goals conceded") {
            lines.append(trend)
        }

        if let trend = formattedTrend(series.map { easyGoalsConceded(in: $0) }, label: "Easy goals conceded") {
            lines.append(trend)
        }

        let possession = series.map { PressureEngine.possessionPercentages(for: $0).home }
        if let trend = formattedTrend(possession, label: "Possession", suffix: "%") {
            lines.append(trend)
        }

        return lines
    }

    private static func easyGoalsConceded(in match: MatchState) -> Int {
        match.shots.filter {
            $0.team == .away && $0.difficulty == .easy && $0.outcome == .goal
        }.count
    }

    private static func formattedTrend<T: CustomStringConvertible>(
        _ values: [T],
        label: String,
        suffix: String = ""
    ) -> String? {
        guard values.count >= 2 else { return nil }
        let formatted = values.map { "\($0)\(suffix)" }.joined(separator: " → ")
        return "• \(label): \(formatted)"
    }
}
