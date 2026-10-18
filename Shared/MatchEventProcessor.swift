import Foundation

enum MatchEventProcessor {
    static func passType(for possession: TeamSide?) -> PassEventType {
        guard let possession else { return .ourPass }
        return possession == .home ? .ourPass : .theirPass
    }

    @discardableResult
    static func recordPass(in match: inout MatchState) -> Bool {
        let possession = PressureEngine.possessingTeam(in: match)
        let type = passType(for: possession)
        guard PressureEngine.canRecordPass(type, possession: possession) else {
            return false
        }
        match.passes.append(PassEvent(type: type, matchSeconds: match.elapsedSeconds))
        return true
    }

    @discardableResult
    static func recordBallOut(in match: inout MatchState) -> Bool {
        let possession = PressureEngine.possessingTeam(in: match)
        let type = PressureEngine.ballOutType(for: possession)
        guard PressureEngine.canRecordPass(type, possession: possession) else { return false }
        match.passes.append(PassEvent(type: type, matchSeconds: match.elapsedSeconds))
        return true
    }

    static func possessionChangeType(for possession: TeamSide?) -> PassEventType {
        switch possession {
        case .home:
            .possessionToAway
        case .away:
            .possessionToHome
        case .none:
            .possessionToHome
        }
    }

    @discardableResult
    static func recordPossessionChange(in match: inout MatchState) -> Bool {
        if !match.isRunning {
            match.currentPossession = match.currentPossession.opposite
            return true
        }

        let possession = PressureEngine.possessingTeam(in: match)
        let type = possessionChangeType(for: possession)
        guard PressureEngine.canRecordPass(type, possession: possession) else { return false }
        match.passes.append(PassEvent(type: type, matchSeconds: match.elapsedSeconds))
        return true
    }
}
