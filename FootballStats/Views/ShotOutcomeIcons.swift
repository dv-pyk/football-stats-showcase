import SwiftUI

enum ShotOutcomeIconKind: Hashable {
    case goal
    case saved
    case miss
}

struct ShotOutcomeIcon: View {
    let kind: ShotOutcomeIconKind
    var difficulty: ShotDifficulty?

    var body: some View {
        DifficultyShotIcon(
            difficulty: difficulty ?? .normal,
            kind: kind
        )
    }
}

private struct DifficultyShotIcon: View {
    let difficulty: ShotDifficulty
    let kind: ShotOutcomeIconKind

    var body: some View {
        switch difficulty {
        case .easy:
            EasyShotIcon(kind: kind)
        case .normal:
            NormalShotIcon(kind: kind)
        case .hard:
            HardShotIcon(kind: kind)
        case .corner:
            CornerShotIcon(kind: kind)
        }
    }
}

// MARK: - Shared chrome

private extension ShotDifficulty {
    var iconLabel: String {
        switch self {
        case .easy: "Easy"
        case .normal: "Normal"
        case .hard: "Hard"
        case .corner: "Corner"
        }
    }

    var showsTopBanner: Bool {
        self == .easy || self == .hard
    }

    var bannerColor: Color {
        switch self {
        case .easy: Color(red: 0.15, green: 0.62, blue: 0.38)
        case .hard: Color(red: 0.78, green: 0.28, blue: 0.12)
        default: .clear
        }
    }
}

private extension ShotOutcomeIconKind {
    var iconLabel: String {
        switch self {
        case .goal: "Goal"
        case .saved: "Blocked"
        case .miss: "Miss"
        }
    }

    var normalCaptionLabel: String {
        switch self {
        case .goal: "Goal"
        case .saved: "On Target Attempt"
        case .miss: "Miss"
        }
    }
}

private struct ShotIconFrame<Content: View>: View {
    let difficulty: ShotDifficulty
    let kind: ShotOutcomeIconKind
    @ViewBuilder var content: () -> Content

    private var showsTopBanner: Bool { difficulty.showsTopBanner }

    var body: some View {
        ZStack(alignment: .bottom) {
            if kind == .goal {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(0.38))
            }

            content()
                .padding(.top, showsTopBanner ? 11 : 0)
                .padding(.bottom, 15)

            if showsTopBanner {
                VStack(spacing: 0) {
                    ShotDifficultyTopBanner(difficulty: difficulty)
                    Spacer(minLength: 0)
                }
            }

            ShotIconCaption(difficulty: difficulty, kind: kind)
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .clipped()
    }
}

private struct ShotDifficultyTopBanner: View {
    let difficulty: ShotDifficulty

    var body: some View {
        Text(difficulty.iconLabel.uppercased())
            .font(.system(size: 7, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(difficulty.bannerColor)
    }
}

private struct ShotIconCaption: View {
    let difficulty: ShotDifficulty
    let kind: ShotOutcomeIconKind

    private var captionText: String {
        if difficulty == .normal {
            return kind.normalCaptionLabel
        }
        if difficulty.showsTopBanner {
            return kind.iconLabel
        }
        if difficulty == .corner, kind == .saved {
            return "Corner Defended"
        }
        return "\(difficulty.iconLabel) \(kind.iconLabel)"
    }

    var body: some View {
        Text(captionText)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 3)
    }
}

private struct FootballBall: View {
    let size: CGFloat

    var body: some View {
        Text("⚽")
            .font(.system(size: size))
    }
}

private enum BlockerStyle {
    case keeper
    case leg
}

private struct ShotBlocker: View {
    let style: BlockerStyle

    var body: some View {
        switch style {
        case .keeper:
            Text("🧤")
                .font(.system(size: 22))
        case .leg:
            DefenderLeg()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 14, height: 18)
        }
    }
}

private struct DefenderLeg: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 2, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct DefenderSilhouette: View {
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0.5) {
            Circle()
                .fill(Color.primary.opacity(0.8))
                .frame(width: 4 * scale, height: 4 * scale)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.8))
                .frame(width: 5 * scale, height: 8 * scale)
        }
    }
}

private struct GoalFrame: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 4
        let left = inset
        let right = rect.width - inset
        let top = inset
        let bottom = rect.height - 2

        path.move(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: top + 8))
        path.addLine(to: CGPoint(x: right, y: top + 8))
        path.addLine(to: CGPoint(x: right, y: bottom))
        return path
    }
}

private struct DashedShotPath: Shape {
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

// MARK: - Easy (ball very close to goal)

private struct EasyShotIcon: View {
    let kind: ShotOutcomeIconKind

    var body: some View {
        ShotIconFrame(difficulty: .easy, kind: kind) {
            ZStack {
                EasyGoalNetCorner()
                    .stroke(Color.primary.opacity(0.5), lineWidth: 1.2)
                    .frame(width: 44, height: 48)
                    .offset(x: 22, y: 2)

                EasyGoalPostCorner()
                    .stroke(Color.primary, lineWidth: 3)
                    .frame(width: 44, height: 48)
                    .offset(x: 22, y: 2)

                if kind == .saved {
                    ShotBlocker(style: .keeper)
                        .offset(x: 10, y: 2)
                }

                if kind == .miss {
                    DashedShotPath(
                        start: CGPoint(x: 6, y: 38),
                        end: CGPoint(x: 48, y: 2),
                        control: CGPoint(x: 34, y: 18)
                    )
                    .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }

                FootballBall(size: ballSize)
                    .offset(ballOffset)
            }
            .scaleEffect(1.18)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var ballSize: CGFloat {
        kind == .miss ? 22 : 36
    }

    private var ballOffset: CGSize {
        switch kind {
        case .goal: CGSize(width: 6, height: 4)
        case .saved: CGSize(width: -2, height: 8)
        case .miss: CGSize(width: 30, height: -10)
        }
    }

    private var accessibilityLabel: String {
        switch kind {
        case .goal: "Easy goal"
        case .saved: "Easy chance saved"
        case .miss: "Easy chance missed"
        }
    }
}

private struct EasyGoalNetCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let postX = rect.minX + 6
        let top = rect.minY + 4
        let bottom = rect.maxY

        for i in 0...4 {
            let x = postX + CGFloat(i) * (rect.maxX - postX) / 4
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottom))
        }
        for i in 0...5 {
            let y = top + CGFloat(i) * (bottom - top) / 5
            path.move(to: CGPoint(x: postX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX + 4, y: y))
        }
        return path
    }
}

private struct EasyGoalPostCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let postX = rect.minX + 6
        path.move(to: CGPoint(x: postX, y: rect.maxY))
        path.addLine(to: CGPoint(x: postX, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: postX - 5, y: rect.minY + 2))
        return path
    }
}

// MARK: - Normal (one defender between ball and goal)

private struct NormalShotIcon: View {
    let kind: ShotOutcomeIconKind

    var body: some View {
        ShotIconFrame(difficulty: .normal, kind: kind) {
            ZStack {
                PitchPlane()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.55, blue: 0.28).opacity(0.35),
                                Color(red: 0.10, green: 0.38, blue: 0.20).opacity(0.2)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )

                PerspectiveLaneLines()
                    .stroke(.white.opacity(0.28), lineWidth: 0.8)

                DistantGoal3D()
                    .stroke(Color.primary.opacity(0.9), lineWidth: 1.4)

                DistantGoal3D()
                    .fill(Color.primary.opacity(0.08))

                GoalNetPerspective()
                    .stroke(Color.primary.opacity(0.35), lineWidth: 0.6)

                DefenderSilhouette()
                    .offset(x: 0, y: 4)

                shotPath
                    .stroke(
                        Color.primary.opacity(kind == .miss ? 0.35 : 0.5),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 2])
                    )

                if kind == .saved {
                    ShotBlocker(style: .keeper)
                        .offset(x: 0, y: -6)
                }

                FootballBall(size: 15)
                    .offset(ballOffset)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var shotPath: DashedShotPath {
        switch kind {
        case .goal:
            DashedShotPath(
                start: CGPoint(x: 26, y: 40),
                end: CGPoint(x: 28, y: 16),
                control: CGPoint(x: 32, y: 28)
            )
        case .saved:
            DashedShotPath(
                start: CGPoint(x: 26, y: 40),
                end: CGPoint(x: 28, y: 10),
                control: CGPoint(x: 30, y: 24)
            )
        case .miss:
            DashedShotPath(
                start: CGPoint(x: 26, y: 40),
                end: CGPoint(x: 50, y: 4),
                control: CGPoint(x: 42, y: 22)
            )
        }
    }

    private var ballOffset: CGSize {
        switch kind {
        case .goal: CGSize(width: -2, height: 12)
        case .saved: CGSize(width: -2, height: 14)
        case .miss: CGSize(width: 22, height: -12)
        }
    }

    private var accessibilityLabel: String {
        switch kind {
        case .goal: "Normal chance goal"
        case .saved: "Normal chance saved"
        case .miss: "Normal chance missed"
        }
    }
}

// MARK: - Hard (many defenders, longer distance)

private struct HardShotIcon: View {
    let kind: ShotOutcomeIconKind

    private let defenderOffsets: [CGSize] = [
        CGSize(width: -22, height: 10),
        CGSize(width: -12, height: 8),
        CGSize(width: -2, height: 10),
        CGSize(width: 8, height: 8),
        CGSize(width: 18, height: 10),
        CGSize(width: -17, height: 18),
        CGSize(width: 3, height: 16),
        CGSize(width: 22, height: 18)
    ]

    var body: some View {
        ShotIconFrame(difficulty: .hard, kind: kind) {
            ZStack {
                PitchPlane()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.50, blue: 0.26).opacity(0.4),
                                Color(red: 0.08, green: 0.32, blue: 0.18).opacity(0.15)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )

                LongRangePerspectiveLines()
                    .stroke(.white.opacity(0.22), lineWidth: 0.7)

                TinyDistantGoal3D()
                    .stroke(Color.primary.opacity(0.85), lineWidth: 1.1)

                TinyDistantGoal3D()
                    .fill(Color.primary.opacity(0.06))

                ForEach(defenderOffsets.indices, id: \.self) { index in
                    DefenderSilhouette(scale: index < 5 ? 1.0 : 0.85)
                        .offset(defenderOffsets[index])
                }

                if kind == .miss {
                    DashedShotPath(
                        start: CGPoint(x: 26, y: 44),
                        end: CGPoint(x: 52, y: 2),
                        control: CGPoint(x: 44, y: 20)
                    )
                    .stroke(
                        Color.primary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [4, 3])
                    )
                } else {
                    HardBallThroughDefendersPath()
                        .stroke(
                            Color.primary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [4, 3])
                        )
                }

                if kind == .saved {
                    ShotBlocker(style: .leg)
                        .offset(x: 2, y: -2)
                        .rotationEffect(.degrees(-25))
                }

                FootballBall(size: 12)
                    .offset(ballOffset)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var ballOffset: CGSize {
        switch kind {
        case .goal: CGSize(width: 3, height: 5)
        case .saved: CGSize(width: 0, height: 8)
        case .miss: CGSize(width: 24, height: -10)
        }
    }

    private var accessibilityLabel: String {
        switch kind {
        case .goal: "Hard to score goal"
        case .saved: "Hard chance saved"
        case .miss: "Hard chance missed"
        }
    }
}

// MARK: - Corner (flag on every outcome)

private struct CornerShotIcon: View {
    let kind: ShotOutcomeIconKind

    var body: some View {
        ShotIconFrame(difficulty: .corner, kind: kind) {
            ZStack {
                CornerPitchPlane()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.17, green: 0.52, blue: 0.27).opacity(0.3),
                                Color(red: 0.09, green: 0.34, blue: 0.19).opacity(0.15)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )

                CornerKickArc()
                    .stroke(.white.opacity(0.85), lineWidth: 1.8)

                CornerTouchLine()
                    .stroke(.white.opacity(0.7), lineWidth: 1.2)

                CornerGoalPerspective()
                    .stroke(Color.primary.opacity(0.7), lineWidth: 1)

                if kind == .miss {
                    DashedShotPath(
                        start: CGPoint(x: 8, y: 40),
                        end: CGPoint(x: 50, y: 6),
                        control: CGPoint(x: 36, y: 16)
                    )
                    .stroke(
                        Color.primary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [3, 2])
                    )
                } else {
                    CornerBallPath()
                        .stroke(
                            Color.primary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [3, 2])
                        )
                }

                CornerFlag()
                    .scaleEffect(1.35)
                    .offset(x: -21, y: 15)

                if kind == .saved {
                    ShotBlocker(style: .keeper)
                        .offset(x: 10, y: -2)
                }

                FootballBall(size: 13)
                    .offset(ballOffset)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var ballOffset: CGSize {
        switch kind {
        case .goal: CGSize(width: -14, height: 10)
        case .saved: CGSize(width: 2, height: 0)
        case .miss: CGSize(width: 26, height: -12)
        }
    }

    private var accessibilityLabel: String {
        switch kind {
        case .goal: "Corner goal"
        case .saved: "Corner defended"
        case .miss: "Corner missed"
        }
    }
}

// MARK: - Shapes

private struct PitchPlane: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vanishing = CGPoint(x: rect.midX, y: rect.minY + 6)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: vanishing)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PerspectiveLaneLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vanishing = CGPoint(x: rect.midX, y: rect.minY + 8)

        path.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY))
        path.addLine(to: vanishing)
        path.move(to: CGPoint(x: rect.maxX - 4, y: rect.maxY))
        path.addLine(to: vanishing)
        path.move(to: CGPoint(x: rect.midX - 14, y: rect.maxY - 2))
        path.addLine(to: vanishing)
        path.move(to: CGPoint(x: rect.midX + 14, y: rect.maxY - 2))
        path.addLine(to: vanishing)

        return path
    }
}

private struct DistantGoal3D: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topY = rect.minY + 10
        let bottomY = rect.minY + 22
        let topHalfWidth: CGFloat = 9
        let bottomHalfWidth: CGFloat = 13
        let centerX = rect.midX

        path.move(to: CGPoint(x: centerX - bottomHalfWidth, y: bottomY))
        path.addLine(to: CGPoint(x: centerX - topHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX + topHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX + bottomHalfWidth, y: bottomY))
        path.closeSubpath()
        return path
    }
}

private struct GoalNetPerspective: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topY = rect.minY + 10
        let bottomY = rect.minY + 22
        let topHalfWidth: CGFloat = 9
        let bottomHalfWidth: CGFloat = 13
        let centerX = rect.midX

        for i in 1...2 {
            let t = CGFloat(i) / 3
            let y = topY + (bottomY - topY) * t
            let halfWidth = topHalfWidth + (bottomHalfWidth - topHalfWidth) * t
            path.move(to: CGPoint(x: centerX - halfWidth, y: y))
            path.addLine(to: CGPoint(x: centerX + halfWidth, y: y))
        }

        path.move(to: CGPoint(x: centerX, y: topY))
        path.addLine(to: CGPoint(x: centerX, y: bottomY))

        return path
    }
}

private struct LongRangePerspectiveLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vanishing = CGPoint(x: rect.midX, y: rect.minY + 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: vanishing)
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: vanishing)
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: vanishing)
        path.move(to: CGPoint(x: rect.minX + 10, y: rect.maxY - 4))
        path.addLine(to: vanishing)
        path.move(to: CGPoint(x: rect.maxX - 10, y: rect.maxY - 4))
        path.addLine(to: vanishing)

        return path
    }
}

private struct TinyDistantGoal3D: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topY = rect.minY + 5
        let bottomY = rect.minY + 11
        let topHalfWidth: CGFloat = 5
        let bottomHalfWidth: CGFloat = 7
        let centerX = rect.midX

        path.move(to: CGPoint(x: centerX - bottomHalfWidth, y: bottomY))
        path.addLine(to: CGPoint(x: centerX - topHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX + topHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX + bottomHalfWidth, y: bottomY))
        path.closeSubpath()
        return path
    }
}

private struct HardBallThroughDefendersPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.midX - 4, y: rect.maxY - 4)
        let gap = CGPoint(x: rect.midX + 2, y: rect.midY + 2)
        let end = CGPoint(x: rect.midX, y: rect.minY + 7)
        path.move(to: start)
        path.addQuadCurve(
            to: gap,
            control: CGPoint(x: rect.midX - 8, y: rect.maxY - 14)
        )
        path.addQuadCurve(
            to: end,
            control: CGPoint(x: rect.midX + 6, y: rect.midY - 8)
        )
        return path
    }
}

private struct CornerPitchPlane: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vanishing = CGPoint(x: rect.maxX - 8, y: rect.minY + 6)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: vanishing)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CornerKickArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = CGPoint(x: rect.minX - 2, y: rect.maxY + 2)
        path.addArc(
            center: corner,
            radius: 14,
            startAngle: .degrees(-80),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

private struct CornerFlag: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.primary.opacity(0.85))
                .frame(width: 2, height: 18)

            Path { path in
                path.move(to: CGPoint(x: 2, y: 1))
                path.addLine(to: CGPoint(x: 16, y: 6))
                path.addLine(to: CGPoint(x: 2, y: 11))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.yellow, Color.red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .offset(y: -16)
        }
        .frame(width: 18, height: 18)
    }
}

private struct CornerTouchLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 2, y: rect.maxY + 2))
        path.addLine(to: CGPoint(x: rect.minX - 2, y: rect.maxY - 18))
        path.move(to: CGPoint(x: rect.minX - 2, y: rect.maxY + 2))
        path.addLine(to: CGPoint(x: rect.minX + 16, y: rect.maxY + 2))
        return path
    }
}

private struct CornerGoalPerspective: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topY = rect.minY + 9
        let bottomY = rect.minY + 18
        let topHalfWidth: CGFloat = 7
        let bottomHalfWidth: CGFloat = 10
        let centerX = rect.midX + 6

        path.move(to: CGPoint(x: centerX - bottomHalfWidth, y: bottomY))
        path.addLine(to: CGPoint(x: centerX - topHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX + topHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX + bottomHalfWidth, y: bottomY))
        path.closeSubpath()
        return path
    }
}

private struct CornerBallPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX + 4, y: rect.maxY - 8)
        let end = CGPoint(x: rect.midX + 8, y: rect.minY + 14)
        path.move(to: start)
        path.addQuadCurve(
            to: end,
            control: CGPoint(x: rect.midX - 4, y: rect.midY - 6)
        )
        return path
    }
}

#Preview("All outcomes") {
    ScrollView {
        VStack(spacing: 8) {
            ForEach(ShotDifficulty.allCases) { difficulty in
                HStack(spacing: 8) {
                    ForEach(
                        [ShotOutcomeIconKind.goal, .saved, .miss],
                        id: \.self
                    ) { kind in
                        ShotOutcomeIcon(kind: kind, difficulty: difficulty)
                            .padding(4)
                            .background(kind == .goal ? Color.green.opacity(0.15) : Color.clear)
                    }
                }
            }
        }
        .padding()
    }
}
