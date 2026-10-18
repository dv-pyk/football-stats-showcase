import SwiftUI

struct LiveMatchView: View {
    @ObservedObject var viewModel: MatchViewModel
    @ObservedObject var rosterStore: RosterStore
    var onEndAndSave: () -> Void
    @State private var showingPressureLedger = false
    @State private var creditRequest: CreditRequest?

    /// Which roster player a just-recorded shot should be credited to — carries enough
    /// identity for `.sheet(item:)` (a bare `Bool` can't distinguish goal vs. big save, or
    /// which shot). Own-team goals and big saves only; see `shotRow`.
    private enum CreditRequest: Identifiable {
        case goal(shotID: UUID)
        case bigSave(shotID: UUID)

        var id: UUID {
            switch self {
            case .goal(let id), .bigSave(let id): id
            }
        }

        var shotID: UUID { id }
        var isBigSave: Bool {
            if case .bigSave = self { true } else { false }
        }
    }

    private var hasHomeRoster: Bool {
        !(rosterStore.roster(for: viewModel.match.homeTeamName)?.players.isEmpty ?? true)
    }

    var body: some View {
        VStack(spacing: 6) {
            matchHeaderRow

            PressureMiniChartView(buckets: viewModel.recentPressureBuckets, height: 36)
                .padding(.horizontal, 4)
                .opacity(viewModel.idleGapSeconds >= 25 ? 0.35 : 1)

            pressureLane

            primaryShotSection

            Spacer(minLength: 0)

            passSection

            secondaryShotSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .sheet(isPresented: $showingPressureLedger) {
            PressureLedgerView(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .sheet(item: $creditRequest) { request in
            PlayerCreditPickerView(
                roster: rosterStore.roster(for: viewModel.match.homeTeamName) ?? TeamRoster(teamName: viewModel.match.homeTeamName, players: []),
                avatarImage: { rosterStore.avatarImage(for: $0) },
                isBigSave: request.isBigSave,
                onCredit: { playerID in
                    viewModel.creditShot(id: request.shotID, playerID: playerID)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var matchHeaderRow: some View {
        HStack(spacing: 8) {
            if viewModel.match.isRunning {
                Button("Pause") {
                    viewModel.toggleClock()
                }
                .fontWeight(.semibold)
            } else {
                Button("Start") {
                    viewModel.toggleClock()
                }
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(viewModel.match.score(for: .home))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                Text("–")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.match.score(for: .away))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                Text(viewModel.match.currentClock)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            HoldToEndButton(onEnd: onEndAndSave)
        }
    }

    private var pressureLane: some View {
        PressureLaneView(
            pendingSteal: { viewModel.pendingSteal(at: $0) },
            lastNotableEvent: viewModel.lastNotableExplained,
            lastNotableEventAt: viewModel.lastNotableEventAt,
            idleGapSeconds: viewModel.idleGapSeconds,
            currentIndex: viewModel.currentPressure,
            homeTeamName: TeamDisplayNames.short(viewModel.match.homeTeamName),
            awayTeamName: TeamDisplayNames.short(viewModel.match.awayTeamName),
            onTap: { showingPressureLedger = true }
        )
    }

    private var passSection: some View {
        let possession = viewModel.possessionPanelDisplay()
        let pass = viewModel.passButtonDisplay()

        return VStack(alignment: .leading, spacing: 6) {
            DiagonalPassSection(
                possessionLabel: possession.label,
                possessionColor: possession.color,
                passTitle: pass.title,
                interceptTitle: pass.interceptTitle,
                passColor: pass.color,
                isPassEnabled: pass.isEnabled,
                interceptWindowStart: viewModel.interceptWindowStart,
                interceptStrength: { viewModel.interceptStrength(at: $0) },
                onPass: { viewModel.recordPass(pass.type) }
            )
            .id("pass-\(viewModel.possessingTeam.rawValue)-\(viewModel.match.passes.count)")

            HStack {
                Button("Undo last pass") {
                    viewModel.undoLastPass()
                }
                .font(.caption)
                .disabled(viewModel.match.passes.isEmpty)

                Spacer()

                weightCaption("pass \(weightLabel(PressureWeight.pass)) · steal \(weightLabel(PressureWeight.intercept))")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var primaryShotSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Taller than the Easy/Hard rows below — Normal is the shot difficulty reached
            // for most often, so it should be the easiest target to hit, not the smallest.
            shotRow(for: .normal, buttonHeight: 80)

            HStack {
                Button("Undo last shot") {
                    viewModel.undoLastShot()
                }
                .font(.caption)
                .disabled(viewModel.match.shots.isEmpty)

                Spacer()

                weightCaption("on target \(weightLabel(PressureWeight.shotOnTarget)) · goal \(weightLabel(PressureWeight.goal))")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var secondaryShotSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            shotRow(for: .easy)
            shotRow(for: .hard)

            // Dedicated 18pt row — nothing else here explains that a set piece is credited
            // the instant it's tapped, independent of whatever shot follows (HANDOFF-live-screen.md §5).
            HStack {
                Text("Tap when won — shot is a separate tap")
                    .font(.system(size: 11))
                    .foregroundStyle(Self.setPieceHintColor)
                    .lineLimit(1)
                    .fixedSize()

                Spacer()

                weightCaption(
                    "pen \(weightLabel(PressureWeight.setPieceWeight(for: .penalty))) · "
                        + "corner/FK \(weightLabel(PressureWeight.setPieceWeight(for: .corner)))"
                )
            }
            .frame(height: 18)

            setPieceRow()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Weight captions

    /// Dim, single-line reminder of what a tap is worth to the pressure index — read from
    /// `PressureWeight` so it can never drift from what actually gets scored.
    private func weightCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Self.weightCaptionColor)
            .lineLimit(1)
            .fixedSize()
    }

    private func weightLabel(_ value: Double) -> String {
        let magnitude = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "+\(magnitude)"
    }

    private static let weightCaptionColor = Color(red: 0.282, green: 0.282, blue: 0.290) // #48484A
    private static let setPieceHintColor = Color(red: 0.557, green: 0.557, blue: 0.576)  // #8E8E93

    /// 80pt — the caption used to sit in its own row below the artwork (see
    /// `SetPieceArtIcon`); it's now an overlay instead, so the artwork renders at the same
    /// size as before inside a shorter tile rather than being shrunk to fit.
    private func setPieceRow(buttonHeight: CGFloat = 80) -> some View {
        HStack(spacing: 8) {
            ForEach(SetPieceKind.allCases) { kind in
                Button {
                    viewModel.recordSetPiece(kind)
                } label: {
                    SetPieceArtTile {
                        SetPieceArtIcon(kind: kind, possession: viewModel.possessingTeam)
                            .frame(height: buttonHeight)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shotRow(for difficulty: ShotDifficulty, buttonHeight: CGFloat = 64) -> some View {
        HStack(spacing: 8) {
            shotButton(.goal, difficulty, buttonHeight) {
                let team = viewModel.possessingTeam
                let shot = viewModel.addShot(team: team, difficulty: difficulty, outcome: .goal)
                if team == .home && hasHomeRoster {
                    creditRequest = .goal(shotID: shot.id)
                }
            }
            shotButton(.onTarget, difficulty, buttonHeight) {
                let team = viewModel.possessingTeam
                let shot = viewModel.addShot(team: team, difficulty: difficulty, outcome: .onTarget)
                if difficulty == .easy && team == .away && hasHomeRoster {
                    creditRequest = .bigSave(shotID: shot.id)
                }
            }
            shotButton(.miss, difficulty, buttonHeight) {
                viewModel.addShot(team: viewModel.possessingTeam, difficulty: difficulty, outcome: .notOnTarget)
            }
        }
    }

    /// `ShotTileIcon` draws its own column-coloured capsule, so unlike the old
    /// `ShotOutcomeButton` this needs no `.borderedProminent`/`.tint` wrapper — which is also
    /// what forced the old `scaleEffect(minHeight / 64)` double-scaling hack
    /// (`LIVE_SCREEN_PRINCIPLES.md` §6). The tile scales to whatever height it's given.
    private func shotButton(
        _ kind: ShotTileKind,
        _ difficulty: ShotDifficulty,
        _ height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ShotTileIcon(kind: kind, difficulty: difficulty, possession: viewModel.possessingTeam)
                .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(.plain)
    }
}

private enum DiagonalPassLayout {
    static let sectionHeight: CGFloat = 196
    static let topSplit: CGFloat = 0.66
    static let bottomSplit: CGFloat = 0.18
}

private struct DiagonalPassSection: View {
    let possessionLabel: String
    let possessionColor: Color
    let passTitle: String
    let interceptTitle: String
    let passColor: Color
    let isPassEnabled: Bool
    let interceptWindowStart: Date?
    let interceptStrength: (Date) -> Double
    let onPass: () -> Void

    /// Distinct accent while the steal window is open, so the temporary meaning of a tap
    /// reads at a glance rather than blending into the team colour.
    private let interceptColor = Color.blue

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: interceptWindowStart == nil)) { context in
                let strength = isPassEnabled ? interceptStrength(context.date) : 0

                ZStack {
                    possessionPanel(in: geometry.size)

                    Button(action: onPass) {
                        ZStack(alignment: .bottomTrailing) {
                            passColor.opacity(isPassEnabled ? 1 : 0.35)
                            interceptColor.opacity(strength)

                            ZStack(alignment: .bottomTrailing) {
                                Text(passTitle).opacity(1 - strength)
                                Text(interceptTitle).opacity(strength)
                            }
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                            .padding(.trailing, 22)
                            .padding(.bottom, 24)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(DiagonalPassRightShape())
                    }
                    .buttonStyle(.plain)
                    .clipShape(DiagonalPassRightShape())
                    .disabled(!isPassEnabled)

                    DiagonalPassDividerShape()
                        .stroke(Color.primary.opacity(0.22), lineWidth: 1.5)

                    if strength > 0 {
                        interceptCountdownBar(in: geometry.size, strength: strength)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
        }
        .frame(height: DiagonalPassLayout.sectionHeight)
    }

    /// A depleting bar along the button's bottom edge, in the same region the diagonal clip
    /// already exposes — a fading colour wash alone didn't give a legible read on exactly
    /// how much of the steal window was left, so this makes the countdown literal.
    private func interceptCountdownBar(in size: CGSize, strength: Double) -> some View {
        let bottomX = size.width * DiagonalPassLayout.bottomSplit
        let visibleWidth = size.width - bottomX

        return HStack(spacing: 0) {
            Color.clear.frame(width: bottomX)
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: max(0, visibleWidth * strength))
            Spacer(minLength: 0)
        }
        .frame(height: 5)
        .padding(.bottom, 4)
    }

    private func possessionPanel(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            possessionColor.opacity(0.18)

            VStack(alignment: .leading, spacing: 6) {
                Text("Possession")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(possessionLabel)
                    .font(.title.weight(.bold))
                    .foregroundStyle(possessionColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 16)
            .padding(.top, 18)
            .padding(.trailing, size.width * (1 - DiagonalPassLayout.topSplit) + 12)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(DiagonalPassLeftShape())
    }
}

private struct DiagonalPassLeftShape: Shape {
    func path(in rect: CGRect) -> Path {
        let topX = rect.minX + rect.width * DiagonalPassLayout.topSplit
        let bottomX = rect.minX + rect.width * DiagonalPassLayout.bottomSplit

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: topX, y: rect.minY))
        path.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DiagonalPassRightShape: Shape {
    func path(in rect: CGRect) -> Path {
        let topX = rect.minX + rect.width * DiagonalPassLayout.topSplit
        let bottomX = rect.minX + rect.width * DiagonalPassLayout.bottomSplit

        var path = Path()
        path.move(to: CGPoint(x: topX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DiagonalPassDividerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let topX = rect.minX + rect.width * DiagonalPassLayout.topSplit
        let bottomX = rect.minX + rect.width * DiagonalPassLayout.bottomSplit

        var path = Path()
        path.move(to: CGPoint(x: bottomX, y: rect.maxY))
        path.addLine(to: CGPoint(x: topX, y: rect.minY))
        return path
    }
}

#Preview {
    LiveMatchView(viewModel: MatchViewModel(), rosterStore: RosterStore(), onEndAndSave: {})
}

/// End & Save behind a press-and-hold, because it used to be a bare tap sitting one thumb's
/// width from Pause/Start — and a half-time reach for Start that landed here split a real
/// match into two records. The whole point of the guard is that no single tap, however
/// rushed or off-centre, can end a recording.
///
/// Two §1 rules shape the design: the label never changes (a "Hold to end" nudge swapped in
/// on a stray tap would resize the button and shift the score/clock beside it), and the time
/// budget is shown as a literal fill that sweeps the button rather than as a colour fade —
/// the same call the intercept countdown bar made.
private struct HoldToEndButton: View {
    let onEnd: () -> Void

    /// Long enough that no reflex tap survives it, short enough not to feel like a penalty
    /// at the final whistle.
    private static let holdSeconds: TimeInterval = 1.0
    /// Below this, a release reads as someone who meant to tap and expected it to work, so
    /// they get a shake telling them the gesture exists. A longer hold that stops short is
    /// a deliberate abort — the fill draining back is answer enough.
    private static let tapThresholdSeconds: TimeInterval = 0.25

    @State private var progress: CGFloat = 0
    @State private var pressStartedAt: Date?
    @State private var shakeNudge = 0

    var body: some View {
        Text("Hold to End")
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    // Neutral on purpose: green/red/orange are team identity and
                    // green/yellow/grey are shot outcomes (§3, §4). The app's accent is
                    // the same green as "us", so a tinted fill would have read as a team
                    // colour sweeping the header. The motion carries the meaning instead.
                    GeometryReader { geometry in
                        Capsule()
                            .fill(.secondary.opacity(0.45))
                            .frame(width: geometry.size.width * progress)
                    }
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .modifier(ShakeEffect(travel: shakeNudge))
            .onLongPressGesture(minimumDuration: Self.holdSeconds, maximumDistance: 50) {
                HapticFeedback.holdCommitted()
                progress = 0
                pressStartedAt = nil
                onEnd()
            } onPressingChanged: { isPressing in
                if isPressing {
                    pressStartedAt = Date()
                    HapticFeedback.holdStarted()
                    withAnimation(.linear(duration: Self.holdSeconds)) { progress = 1 }
                } else {
                    let heldFor = pressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    pressStartedAt = nil
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                    guard heldFor < Self.tapThresholdSeconds else { return }
                    withAnimation(.linear(duration: 0.3)) { shakeNudge += 1 }
                }
            }
            // No longer a `Button`, so the trait and the activation action have to be
            // restated. VoiceOver's activation is deliberate by construction, so it ends
            // the match outright rather than being asked to synthesise a one-second hold.
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("End and save match")
            .accessibilityHint("Press and hold for one second")
            .accessibilityAction { onEnd() }
    }
}

/// Shakes a view once per increment of `travel`, for telling someone a tap didn't take
/// without changing anything about the view's size or position at rest.
private struct ShakeEffect: GeometryEffect {
    /// Animating this from one whole number to the next walks `sin` through exactly
    /// `shakeCount` cycles, so the view lands back where it started every time.
    var animatableData: CGFloat

    private let shakeCount: CGFloat = 3
    private let amplitude: CGFloat = 5

    init(travel: Int) {
        animatableData = CGFloat(travel)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = amplitude * sin(animatableData * .pi * 2 * shakeCount)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
