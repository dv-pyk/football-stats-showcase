import SwiftUI

/// The reasoning lane — narrates what `PressureEngine` just decided (or is still deciding)
/// in plain language, so the person tapping doesn't have to reverse-engineer the index from
/// the numbers afterward. Implements the BACKBURNER entry *"In-app feedback for what the
/// scoring logic is doing"* (HANDOFF-live-screen.md §3).
///
/// Fixed height, always present (`LIVE_SCREEN_PRINCIPLES.md` §1: nothing should reflow and
/// move a button the user is about to tap) — an appearing/disappearing lane would shift every
/// row below it every time the state changes.
struct PressureLaneView: View {
    let pendingSteal: (Date) -> PressureEngine.PendingSteal?
    let lastNotableEvent: PressureEngine.Explained?
    let lastNotableEventAt: Date?
    let idleGapSeconds: Int
    let currentIndex: Double
    let homeTeamName: String
    let awayTeamName: String
    var onTap: () -> Void = {}

    /// How long a freshly resolved event (steal, no-steal, set piece, shot/goal) keeps its
    /// coloured border before settling to the grey "otherwise" read. Only the steal case is
    /// pinned to a number in the handoff (1.2s) — every other kind shares it so "something
    /// just happened" reads with one consistent rhythm rather than a different duration per
    /// kind of tap.
    private static let highlightSeconds: TimeInterval = 1.2
    private static let quietThresholdSeconds = 25
    private static let stealColor = Color.blue
    private static let laneFill = Color(red: 0.109, green: 0.109, blue: 0.118) // #1C1C1E

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
            let state = laneState(at: context.date)

            HStack(spacing: 8) {
                Circle()
                    .fill(state.color)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.line)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subline = state.subline {
                        Text(subline)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let fraction = state.barFraction {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(state.color)
                                .frame(width: max(0, geometry.size.width * fraction), height: 3)
                        }
                        .frame(height: 3)
                    }
                }

                Spacer(minLength: 4)

                Text(state.deltaText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state.color)
                    .lineLimit(1)
                    .fixedSize()

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 20)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("INDEX")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(indexText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.laneFill, in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(state.color, lineWidth: 1)
            )
        }
        .frame(height: 38)
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .onTapGesture(perform: onTap)
    }

    // MARK: - State

    private struct VisualState {
        let color: Color
        let line: String
        let subline: String?
        let barFraction: Double?
        let deltaText: String
    }

    private func laneState(at now: Date) -> VisualState {
        if let pending = pendingSteal(now) {
            let teamName = pending.team == .home ? homeTeamName : awayTeamName
            let sign: Double = pending.team == .home ? 1 : -1
            return VisualState(
                color: Self.stealColor,
                line: "\(teamName) won it — watching for a steal",
                subline: nil,
                barFraction: pending.remainingFraction,
                deltaText: signedLabel(sign * PressureWeight.intercept) + "?"
            )
        }

        if let event = lastNotableEvent, isFresh(at: now) {
            return VisualState(
                color: PressureNarration.color(for: event),
                line: headline(for: event),
                subline: nil,
                barFraction: nil,
                deltaText: signedLabel(event.delta)
            )
        }

        if idleGapSeconds >= Self.quietThresholdSeconds {
            return VisualState(
                color: .gray,
                line: "Quiet \(formattedGap(idleGapSeconds)) — not counting toward possession",
                subline: "Pressure keeps fading",
                barFraction: nil,
                deltaText: indexText
            )
        }

        if let event = lastNotableEvent {
            return VisualState(
                color: .gray,
                line: headline(for: event),
                subline: nil,
                barFraction: nil,
                deltaText: signedLabel(event.delta)
            )
        }

        return VisualState(color: .gray, line: "No events yet", subline: nil, barFraction: nil, deltaText: indexText)
    }

    private func isFresh(at now: Date) -> Bool {
        guard let at = lastNotableEventAt else { return false }
        return now.timeIntervalSince(at) <= Self.highlightSeconds
    }

    private func headline(for event: PressureEngine.Explained) -> String {
        PressureNarration.headline(for: event, homeTeamName: homeTeamName, awayTeamName: awayTeamName)
    }

    private var indexText: String {
        String(format: "%.1f", currentIndex)
    }

    private func formattedGap(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func signedLabel(_ value: Double) -> String {
        PressureNarration.signedLabel(value)
    }
}

#Preview {
    VStack(spacing: 12) {
        PressureLaneView(
            pendingSteal: { _ in PressureEngine.PendingSteal(team: .away, remainingFraction: 0.6) },
            lastNotableEvent: nil,
            lastNotableEventAt: nil,
            idleGapSeconds: 4,
            currentIndex: 3.2,
            homeTeamName: "Z",
            awayTeamName: "Opp"
        )
        PressureLaneView(
            pendingSteal: { _ in nil },
            lastNotableEvent: PressureEngine.Explained(
                seconds: 600, team: .away, kind: .goal, delta: -8, reason: nil, eventIDs: []
            ),
            lastNotableEventAt: Date(),
            idleGapSeconds: 1,
            currentIndex: -6.65,
            homeTeamName: "Z",
            awayTeamName: "Opp"
        )
        PressureLaneView(
            pendingSteal: { _ in nil },
            lastNotableEvent: nil,
            lastNotableEventAt: nil,
            idleGapSeconds: 31,
            currentIndex: 1.1,
            homeTeamName: "Z",
            awayTeamName: "Opp"
        )
    }
    .padding()
    .background(Color.black)
}
