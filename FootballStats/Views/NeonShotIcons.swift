import SwiftUI

/// Candidate replacement for `ShotOutcomeIcon`, in the same neon language as the app icon
/// and share card. Drawing primitives live in `NeonKit`.
///
/// Colour system:
///   - Goal column    → frame + net take the possession colour; ball is chrome white so it
///                      stays readable against a fully lit net.
///   - Blocked column → orange frame and orange blocker; ball keeps the possession colour.
///   - Miss column    → grey frame; ball keeps the possession colour, with a motion trail.

struct NeonShotIcon: View {
    let kind: ShotOutcomeIconKind
    var difficulty: ShotDifficulty = .normal
    /// Green when we have the ball, red when they do.
    var possession: Color = NeonIconPalette.green

    var body: some View {
        ZStack(alignment: .bottom) {
            artwork
                .frame(width: 104, height: 44)
                .padding(.bottom, 15)

            NeonCaption(text: captionText, accent: accent)
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .clipped()
        .accessibilityLabel(accessibilityLabel)
    }

    private var accent: Color {
        switch kind {
        case .goal: possession
        case .saved: NeonIconPalette.orange
        case .miss: NeonIconPalette.grey
        }
    }

    /// Chrome in the goal column keeps the ball from vanishing into a fully lit net.
    private var ballColor: Color {
        kind == .goal ? NeonIconPalette.chrome : possession
    }

    @ViewBuilder
    private var artwork: some View {
        switch difficulty {
        case .easy:
            NeonEasyArtwork(kind: kind, accent: accent, ballColor: ballColor)
        case .normal:
            NeonNormalArtwork(kind: kind, accent: accent, ballColor: ballColor)
        case .hard:
            NeonHardArtwork(kind: kind, accent: accent, ballColor: ballColor, possession: possession)
        case .corner:
            NeonNormalArtwork(kind: kind, accent: accent, ballColor: ballColor)
        }
    }

    private var captionText: String {
        let outcome: String
        switch kind {
        case .goal: outcome = "Goal"
        case .saved: outcome = difficulty == .hard ? "Blocked" : "Saved"
        case .miss: outcome = "Miss"
        }

        switch difficulty {
        case .normal: return kind == .saved ? "On Target" : outcome
        case .easy: return "Easy \(outcome)"
        case .hard: return "Hard \(outcome)"
        case .corner: return "Corner \(outcome)"
        }
    }

    private var accessibilityLabel: String {
        "\(difficulty) chance, \(kind)"
    }
}

// MARK: - Normal: goal front on, keeper set

private struct NeonNormalArtwork: View {
    let kind: ShotOutcomeIconKind
    let accent: Color
    let ballColor: Color

    var body: some View {
        ZStack {
            NeonGoal(accent: accent, netOpacity: kind == .goal ? 0.60 : 0.34)
                .frame(width: 64, height: 34)
                .offset(x: kind == .miss ? -16 : 0, y: -2)

            if kind == .goal {
                NetBulge(accent: accent)
                    .frame(width: 22, height: 18)
                    .offset(x: 8, y: 2)
            }

            if kind == .saved {
                NeonFigure(shape: NeonKeeperFigure(), color: NeonIconPalette.orange, lineWidth: 0.9)
                    .frame(width: 21, height: 27)
                    .offset(y: 3)
            }

            if kind == .miss {
                MotionTrail()
                    .stroke(ballColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 40, height: 24)
                    .offset(x: 18, y: -4)
            }

            NeonBall(color: ballColor, size: kind == .saved ? 11 : 12)
                .offset(ballOffset)
        }
    }

    private var ballOffset: CGSize {
        switch kind {
        case .goal: CGSize(width: 8, height: 2)
        // Held out to the side, clear of the body.
        case .saved: CGSize(width: 14, height: -6)
        case .miss: CGSize(width: 38, height: -13)
        }
    }
}

// MARK: - Easy: goal close and wide, keeper at full stretch

private struct NeonEasyArtwork: View {
    let kind: ShotOutcomeIconKind
    let accent: Color
    let ballColor: Color

    var body: some View {
        ZStack {
            NeonGoal(accent: accent, netOpacity: kind == .goal ? 0.64 : 0.32, depth: 0.20, columns: 15, rows: 9)
                .frame(width: 84, height: 40)
                .offset(x: kind == .miss ? -12 : 0, y: -3)

            if kind == .goal {
                NetBulge(accent: accent)
                    .frame(width: 26, height: 21)
                    .offset(x: -8, y: 2)
            }

            // Big save: keeper full stretch, ball still on target at the fingertips.
            if kind == .saved {
                NeonFigure(shape: NeonDivingKeeperFigure(), color: NeonIconPalette.orange, lineWidth: 0.9)
                    .frame(width: 48, height: 30)
                    .offset(x: -8, y: 1)
            }

            if kind == .miss {
                MotionTrail()
                    .stroke(ballColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 36, height: 16)
                    .offset(x: 22, y: 12)
            }

            NeonBall(color: ballColor, size: kind == .miss ? 12 : 13)
                .offset(ballOffset)
        }
    }

    private var ballOffset: CGSize {
        switch kind {
        case .goal: CGSize(width: -8, height: 2)
        case .saved: CGSize(width: 22, height: -11)
        case .miss: CGSize(width: 42, height: 14)
        }
    }
}

// MARK: - Hard: distance, a wall of defenders, boot block

private struct NeonHardArtwork: View {
    let kind: ShotOutcomeIconKind
    let accent: Color
    let ballColor: Color
    let possession: Color

    var body: some View {
        ZStack {
            if kind == .saved {
                bootBlock
            } else {
                distanceShot
            }
        }
    }

    /// Goal + miss share the long-range framing: small goal, wall of bodies in front.
    private var distanceShot: some View {
        ZStack {
            NeonGoal(accent: accent, netOpacity: kind == .goal ? 0.56 : 0.30, depth: 0.14, columns: 10, rows: 6, frameWidth: 1.6)
                .frame(width: 54, height: 27)
                .offset(x: kind == .miss ? -14 : 0, y: -8)

            if kind == .goal {
                // Keeper goes the wrong way — the ball is already in the far corner.
                NeonFigure(shape: NeonDivingKeeperFigure(), color: NeonIconPalette.orange, lineWidth: 0.8, bloom: 1.6)
                    .frame(width: 32, height: 18)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: -8, y: -7)
            }

            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { _ in
                    NeonFigure(
                        shape: NeonWallFigure(),
                        color: NeonIconPalette.grey.opacity(0.9),
                        lineWidth: 0.7,
                        bloom: 1.2
                    )
                    .frame(width: 11, height: 22)
                }
            }
            .offset(x: kind == .miss ? -14 : 0, y: 8)

            if kind == .miss {
                MotionTrail()
                    .stroke(ballColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 38, height: 22)
                    .offset(x: 20, y: -6)
            }

            NeonBall(color: ballColor, size: 11)
                .offset(ballOffset)
        }
    }

    /// Hard "blocked" is a defender's foot, never the keeper — attacker boot in the
    /// possession colour meeting an orange defender boot on the ball.
    private var bootBlock: some View {
        ZStack {
            boot(color: possession, rotation: 18)
                .offset(x: -21, y: -1)

            boot(color: NeonIconPalette.orange, rotation: -18)
                .scaleEffect(x: -1, y: 1)
                .offset(x: 21, y: -1)

            NeonBall(color: possession, size: 15)
                .offset(y: 2)
        }
    }

    private func boot(color: Color, rotation: Double) -> some View {
        NeonFigure(shape: BootShape(), color: color, lineWidth: 1.0)
            .frame(width: 24, height: 26)
            .rotationEffect(.degrees(rotation))
    }

    private var ballOffset: CGSize {
        switch kind {
        case .goal: CGSize(width: 19, height: -16)
        case .miss: CGSize(width: 36, height: -15)
        case .saved: .zero
        }
    }
}

/// Shin and boot, toe pointing right; mirrored for the opposing foot.
private struct BootShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        let shinLeft = rect.minX + width * 0.24
        let shinRight = rect.minX + width * 0.54
        let ankle = rect.minY + height * 0.56
        let soleTop = rect.maxY - height * 0.20
        let sole = rect.maxY - height * 0.04

        path.move(to: CGPoint(x: shinLeft, y: rect.minY + height * 0.04))
        path.addLine(to: CGPoint(x: shinRight, y: rect.minY + height * 0.04))
        path.addLine(to: CGPoint(x: shinRight, y: ankle))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - width * 0.02, y: soleTop),
            control: CGPoint(x: rect.maxX - width * 0.10, y: ankle + height * 0.02)
        )
        path.addLine(to: CGPoint(x: rect.maxX - width * 0.06, y: sole))
        path.addLine(to: CGPoint(x: shinLeft - width * 0.10, y: sole))
        path.addQuadCurve(
            to: CGPoint(x: shinLeft, y: ankle),
            control: CGPoint(x: shinLeft - width * 0.16, y: ankle + height * 0.10)
        )
        path.closeSubpath()

        return path
    }
}

#Preview("Neon attempts") {
    VStack(spacing: 10) {
        ForEach([ShotDifficulty.normal, .easy, .hard]) { difficulty in
            HStack(spacing: 8) {
                ForEach([ShotOutcomeIconKind.goal, .saved, .miss], id: \.self) { kind in
                    NeonShotIcon(kind: kind, difficulty: difficulty)
                        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    .padding()
    .background(Color.black)
}
