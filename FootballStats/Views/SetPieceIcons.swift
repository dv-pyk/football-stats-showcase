import SwiftUI

/// Setup-only set-piece tiles: white/silver chrome with a possession-coloured ball.
/// Easy / Normal / Hard attempt icons are intentionally left alone.
struct SetPieceSetupIcon: View {
    let kind: SetPieceKind
    var ballColor: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            chrome
                .padding(.bottom, 16)

            Text(kind.shortLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .clipped()
        .accessibilityLabel(kind.accessibilityLabel)
    }

    @ViewBuilder
    private var chrome: some View {
        switch kind {
        case .corner:
            CornerSetupGlyph(ballColor: ballColor)
        case .penalty:
            PenaltySetupGlyph(ballColor: ballColor)
        case .freeKick:
            FreeKickSetupGlyph(ballColor: ballColor)
        }
    }
}

// MARK: - Glyphs

private struct CornerSetupGlyph: View {
    let ballColor: Color

    private let chrome = Color.white.opacity(0.92)

    var body: some View {
        ZStack {
            // Touch lines meeting at the corner
            Path { path in
                path.move(to: CGPoint(x: 8, y: 52))
                path.addLine(to: CGPoint(x: 8, y: 28))
                path.move(to: CGPoint(x: 8, y: 52))
                path.addLine(to: CGPoint(x: 36, y: 52))
            }
            .stroke(chrome, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            // Corner arc
            Path { path in
                path.addArc(
                    center: CGPoint(x: 8, y: 52),
                    radius: 16,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(0),
                    clockwise: false
                )
            }
            .stroke(chrome, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Flag pole + white flag
            Path { path in
                path.move(to: CGPoint(x: 10, y: 50))
                path.addLine(to: CGPoint(x: 10, y: 22))
            }
            .stroke(chrome, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

            Path { path in
                path.move(to: CGPoint(x: 10, y: 22))
                path.addLine(to: CGPoint(x: 24, y: 27))
                path.addLine(to: CGPoint(x: 10, y: 32))
                path.closeSubpath()
            }
            .fill(chrome)

            PossessionBall(color: ballColor, size: 13)
                .position(x: 28, y: 44)
        }
        .frame(width: 64, height: 56)
    }
}

private struct PenaltySetupGlyph: View {
    let ballColor: Color

    private let chrome = Color.white.opacity(0.92)

    var body: some View {
        ZStack {
            // Distant goal
            Path { path in
                path.move(to: CGPoint(x: 18, y: 28))
                path.addLine(to: CGPoint(x: 22, y: 12))
                path.addLine(to: CGPoint(x: 42, y: 12))
                path.addLine(to: CGPoint(x: 46, y: 28))
            }
            .stroke(chrome, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))

            // Spot line
            Path { path in
                path.move(to: CGPoint(x: 16, y: 46))
                path.addLine(to: CGPoint(x: 48, y: 46))
            }
            .stroke(chrome.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            PossessionBall(color: ballColor, size: 14)
                .position(x: 32, y: 42)
        }
        .frame(width: 64, height: 56)
    }
}

private struct FreeKickSetupGlyph: View {
    let ballColor: Color

    private let chrome = Color.white.opacity(0.92)

    var body: some View {
        ZStack {
            // Goal behind the wall
            Path { path in
                path.move(to: CGPoint(x: 16, y: 30))
                path.addLine(to: CGPoint(x: 20, y: 10))
                path.addLine(to: CGPoint(x: 44, y: 10))
                path.addLine(to: CGPoint(x: 48, y: 30))
            }
            .stroke(chrome, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            // Hollow outline wall (not filled)
            ForEach(0..<4, id: \.self) { index in
                let x = 18 + CGFloat(index) * 9
                OutlinePlayer()
                    .stroke(chrome, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 18)
                    .position(x: x, y: 28)
            }

            PossessionBall(color: ballColor, size: 13)
                .position(x: 32, y: 46)
        }
        .frame(width: 64, height: 56)
    }
}

private struct OutlinePlayer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let head = CGRect(
            x: rect.midX - rect.width * 0.28,
            y: rect.minY,
            width: rect.width * 0.56,
            height: rect.width * 0.56
        )
        path.addEllipse(in: head)
        path.move(to: CGPoint(x: rect.midX, y: head.maxY + 0.5))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 1))
        path.move(to: CGPoint(x: rect.minX + 1, y: head.maxY + 4))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: head.maxY + 4))
        return path
    }
}

private struct PossessionBall: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: size + 6, height: size + 6)
                .blur(radius: 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [color, color.opacity(0.75), Color.black.opacity(0.85)],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .stroke(color.opacity(0.95), lineWidth: 1)
                .frame(width: size, height: size)

            // Simple panel seams so it reads as a ball, not a dot
            Path { path in
                let r = size / 2
                path.addEllipse(in: CGRect(x: r * 0.45, y: r * 0.35, width: r * 0.7, height: r * 0.55))
                path.move(to: CGPoint(x: r * 0.25, y: r * 1.05))
                path.addQuadCurve(
                    to: CGPoint(x: r * 1.75, y: r * 1.05),
                    control: CGPoint(x: r, y: r * 1.45)
                )
            }
            .stroke(Color.black.opacity(0.45), lineWidth: 0.8)
            .frame(width: size, height: size)
        }
        .shadow(color: color.opacity(0.75), radius: 3)
    }
}

#Preview("Set pieces") {
    HStack(spacing: 8) {
        SetPieceSetupIcon(kind: .corner, ballColor: .green)
        SetPieceSetupIcon(kind: .penalty, ballColor: .green)
        SetPieceSetupIcon(kind: .freeKick, ballColor: .green)
    }
    .padding()
    .background(Color.black)

    HStack(spacing: 8) {
        SetPieceSetupIcon(kind: .corner, ballColor: .red)
        SetPieceSetupIcon(kind: .penalty, ballColor: .red)
        SetPieceSetupIcon(kind: .freeKick, ballColor: .red)
    }
    .padding()
    .background(Color.black)
}
