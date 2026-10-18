import AppIntents

enum MatchIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noActiveMatch
    case actionUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveMatch:
            "Open Football Stats and start a match first."
        case .actionUnavailable:
            "That action isn't available right now."
        }
    }
}

struct RecordPossessionChangeIntent: AppIntent {
    static var title: LocalizedStringResource = "Possession Change"
    static var description = IntentDescription("Records that the other team now has the ball — throw-in, goal kick, ball out, or any change in possession.")
    static var openAppWhenRun = false
    static var isDiscoverable = true

    func perform() async throws -> some IntentResult {
        switch ActiveMatchStore.shared.recordPossessionChange() {
        case .success:
            return .result()
        case .noActiveMatch:
            throw MatchIntentError.noActiveMatch
        case .noPossession, .actionUnavailable:
            throw MatchIntentError.actionUnavailable
        }
    }
}

struct RecordBallOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Ball Out of Play"
    static var description = IntentDescription("Records the ball going out of play and gives possession to the other team.")
    static var openAppWhenRun = false
    static var isDiscoverable = true

    func perform() async throws -> some IntentResult {
        switch ActiveMatchStore.shared.recordBallOut() {
        case .success:
            return .result()
        case .noActiveMatch:
            throw MatchIntentError.noActiveMatch
        case .noPossession, .actionUnavailable:
            throw MatchIntentError.actionUnavailable
        }
    }
}
