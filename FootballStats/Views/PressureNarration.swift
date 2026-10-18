import SwiftUI

/// Shared narration formatting for `PressureEngine.Explained`, used by both
/// `PressureLaneView` (the live one-line summary) and `PressureLedgerView` (the full
/// history) so the two can never describe the same event differently.
enum PressureNarration {
    static func headline(for event: PressureEngine.Explained, homeTeamName: String, awayTeamName: String) -> String {
        let teamName = event.team == .home ? homeTeamName : awayTeamName

        switch event.kind {
        case .steal:
            return "Steal — \(teamName) won it back"
        case .turnoverNoSteal:
            return "Ball out — no steal credited"
        case .setPiece(let kind):
            return "\(kind.shortLabel) won — \(magnitudeLabel(event.delta)) now, shot counts separately"
        case .goal:
            return "Goal — \(teamName)"
        case .shot(_, let outcome):
            switch outcome {
            case .onTarget: return "On target — \(teamName)"
            case .notOnTarget: return "Miss — \(teamName)"
            case .goal: return "Goal — \(teamName)"
            }
        case .pass(let count):
            return count == 1 ? "Pass — \(teamName)" : "\(count) passes — \(teamName)"
        }
    }

    /// The colour a state/row should carry — momentary team-identity red (not the ambient
    /// possession-panel orange, per `LIVE_SCREEN_PRINCIPLES.md` §3) for a shot or goal, the
    /// shared Saved/Blocked yellow for a set piece, blue for a steal.
    static func color(for event: PressureEngine.Explained) -> Color {
        switch event.kind {
        case .steal: return .blue
        case .turnoverNoSteal: return .gray
        case .setPiece: return ShotTilePalette.onTarget
        case .goal, .shot: return event.team == .home ? .green : .red
        case .pass: return .gray
        }
    }

    static func magnitudeLabel(_ value: Double) -> String {
        let magnitude = value.magnitude
        let formatted = magnitude.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", magnitude)
            : String(format: "%.1f", magnitude)
        return "+\(formatted)"
    }

    static func signedLabel(_ value: Double) -> String {
        guard value != 0 else { return "0" }
        return value < 0 ? "-\(magnitudeLabel(value).dropFirst())" : magnitudeLabel(value)
    }
}
