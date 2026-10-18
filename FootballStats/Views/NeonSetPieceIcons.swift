import SwiftUI

/// Set-piece setup tiles: white chrome furniture with a possession-coloured ball. These
/// are capture-only taps — the tile shows the situation being set up, not an outcome, so
/// nothing here is colour-coded by result.
///
/// Layout note: the label sits *below* the artwork in a VStack rather than floating over
/// it. The earlier overlay version clipped the crossbar off every goal and left the label
/// sitting on top of the net, which is most of what made these read as unfinished.
struct NeonSetPieceIcon: View {
    let kind: SetPieceKind
    var possession: Color = NeonIconPalette.green
    var showsLabel = true

    private let chrome = NeonIconPalette.chrome

    var body: some View {
        VStack(spacing: 3) {
            artwork
                .frame(width: SetPieceMetrics.artboard.width, height: SetPieceMetrics.artboard.height)

            if showsLabel {
                Text(kind.shortLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityLabel(kind.accessibilityLabel)
    }

    @ViewBuilder
    private var artwork: some View {
        switch kind {
        case .corner:
            CornerSetup(chrome: chrome, ball: possession)
        case .penalty:
            PenaltySetup(chrome: chrome, ball: possession)
        case .freeKick:
            FreeKickSetup(chrome: chrome, ball: possession)
        }
    }
}

private enum SetPieceMetrics {
    static let artboard = CGSize(width: 100, height: 42)
    /// One weight for every piece of pitch furniture, so nothing looks timid next to
    /// anything else.
    static let lineWidth: CGFloat = 1.9
    static let figureLineWidth: CGFloat = 1.1
    static let ballSize: CGFloat = 13
}

// MARK: - Corner

private struct CornerSetup: View {
    let chrome: Color
    let ball: Color

    var body: some View {
        ZStack {
            CornerQuadrant()
                .stroke(
                    chrome,
                    style: StrokeStyle(
                        lineWidth: SetPieceMetrics.lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .neonBloom(chrome, radius: 2.4)

            GroundGlow(color: ball)
                .frame(width: 22, height: 6)
                .offset(x: 22, y: 11)

            // Resting on the goal line, just outside the quadrant.
            NeonBall(color: ball, size: SetPieceMetrics.ballSize)
                .offset(x: 22, y: 6)
        }
        .frame(width: SetPieceMetrics.artboard.width, height: SetPieceMetrics.artboard.height)
    }
}

/// Goal line and touchline meeting at the flag, with the quadrant arc between them. All
/// three share one vertex so the corner reads as a single object.
private struct CornerQuadrant: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        // A real V, not a kinked line — the earlier lines rose so gently that the corner
        // read as flat ground with a bend in it.
        let vertex = point(0.38, 0.92)
        let touchlineEnd = point(0.02, 0.42)
        let goalLineEnd = point(0.98, 0.58)

        path.move(to: touchlineEnd)
        path.addLine(to: vertex)
        path.addLine(to: goalLineEnd)

        // Quadrant: equidistant points along each line, arcing away from the vertex the
        // way a quarter circle actually would.
        let arcT: CGFloat = 0.35
        let arcLeft = CGPoint(
            x: vertex.x + (touchlineEnd.x - vertex.x) * arcT,
            y: vertex.y + (touchlineEnd.y - vertex.y) * arcT
        )
        let arcRight = CGPoint(
            x: vertex.x + (goalLineEnd.x - vertex.x) * arcT,
            y: vertex.y + (goalLineEnd.y - vertex.y) * arcT
        )
        let chordMid = CGPoint(x: (arcLeft.x + arcRight.x) / 2, y: (arcLeft.y + arcRight.y) / 2)
        let control = CGPoint(
            x: chordMid.x + (chordMid.x - vertex.x) * 0.55,
            y: chordMid.y + (chordMid.y - vertex.y) * 0.55
        )

        path.move(to: arcLeft)
        path.addQuadCurve(to: arcRight, control: control)

        // Pole and pennant rising from the vertex.
        let poleTop = point(0.38, 0.06)
        path.move(to: vertex)
        path.addLine(to: poleTop)

        path.move(to: poleTop)
        path.addLine(to: CGPoint(x: poleTop.x + rect.width * 0.21, y: poleTop.y + rect.height * 0.13))
        path.addQuadCurve(
            to: CGPoint(x: poleTop.x, y: poleTop.y + rect.height * 0.31),
            control: CGPoint(x: poleTop.x + rect.width * 0.09, y: poleTop.y + rect.height * 0.28)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Penalty

private struct PenaltySetup: View {
    let chrome: Color
    let ball: Color

    var body: some View {
        ZStack {
            NeonGoal(
                accent: chrome,
                netOpacity: 0.40,
                columns: 14,
                rows: 8,
                frameWidth: SetPieceMetrics.lineWidth
            )
            .frame(width: 76, height: 27)
            .offset(y: -6)

            NeonFigure(
                shape: NeonKeeperFigure(),
                color: chrome,
                lineWidth: SetPieceMetrics.figureLineWidth
            )
            .frame(width: 20, height: 22)
            .offset(y: -3)

            // Goal line the keeper stands on, so the figure is grounded.
            GoalLine()
                .stroke(chrome.opacity(0.55), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: 84, height: 1)
                .offset(y: 9)

            GroundGlow(color: ball)
                .frame(width: 22, height: 6)
                .offset(y: 20)

            NeonBall(color: ball, size: SetPieceMetrics.ballSize)
                .offset(y: 15)
        }
        .frame(width: SetPieceMetrics.artboard.width, height: SetPieceMetrics.artboard.height)
    }
}

// MARK: - Free kick

private struct FreeKickSetup: View {
    let chrome: Color
    let ball: Color

    var body: some View {
        ZStack {
            NeonGoal(
                accent: chrome,
                netOpacity: 0.40,
                columns: 14,
                rows: 8,
                frameWidth: SetPieceMetrics.lineWidth
            )
            .frame(width: 76, height: 27)
            .offset(y: -7)

            // Shoulder to shoulder — a gapped row reads as four bystanders, not a wall.
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    NeonFigure(
                        shape: NeonWallFigure(),
                        color: chrome,
                        lineWidth: SetPieceMetrics.figureLineWidth
                    )
                    .frame(width: 13, height: 23)
                }
            }
            .offset(y: -2)

            GroundGlow(color: ball)
                .frame(width: 22, height: 6)
                .offset(y: 20)

            NeonBall(color: ball, size: SetPieceMetrics.ballSize)
                .offset(y: 15)
        }
        .frame(width: SetPieceMetrics.artboard.width, height: SetPieceMetrics.artboard.height)
    }
}

// MARK: - Shared bits

private struct GoalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Soft pool of light under the ball so it sits on the pitch instead of floating.
private struct GroundGlow: View {
    let color: Color

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.45), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 12
                )
            )
            .blur(radius: 1.5)
    }
}

#Preview("Neon set pieces") {
    VStack(spacing: 10) {
        ForEach([NeonIconPalette.green, NeonIconPalette.red], id: \.self) { possession in
            HStack(spacing: 8) {
                ForEach(SetPieceKind.allCases) { kind in
                    NeonSetPieceIcon(kind: kind, possession: possession)
                        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    .padding()
    .background(Color.black)
}
