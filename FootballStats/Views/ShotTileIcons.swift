import SwiftUI

/// Replacement artwork for the three shot-outcome columns (Goal / On target / Miss) across
/// the Normal, Easy and Hard rows — nine tiles drawn from one system.
///
/// Why this exists alongside `ShotOutcomeIcons.swift`: the shipped tiles were composed per
/// cell, so the three columns didn't share a drawing vocabulary and the middle column read
/// as three unrelated pictures. Here each ROW owns a stage (Normal = the goal in
/// perspective, Easy = a close-up of the net, Hard = bodies in the way) and each COLUMN
/// owns an event (in the net with the net pushed out / stopped on target / past the post),
/// so a glance at the silhouette alone places the tile in the grid.
///
/// Figures reuse the shipped `NeonKeeperFigure`, `NeonDivingKeeperFigure` and
/// `NeonWallFigure` outlines from `NeonKit.swift`; `NeonBlockerFigure` below is new and is
/// built from `NeonAnatomy.limb` with the same taper ratios (arms visibly thinner than
/// legs), per the icon rule in `CLAUDE.md`.
///
/// Colour: the column tint is unchanged (`LIVE_SCREEN_PRINCIPLES.md` §4) and the ball still
/// carries the current possessor's colour (§3, §7). The line art is dark ink rather than
/// neon glow because these tiles sit on a light column fill — a two-pass bloom needs a dark
/// ground to read as neon. Limb seams are stroked in the tile's own fill colour, which is
/// what separates overlapping limbs the way the glow does on the black set-piece tiles.

enum ShotTileKind: String, CaseIterable, Identifiable {
    case goal
    case onTarget
    case miss

    var id: String { rawValue }

    var columnColor: Color {
        switch self {
        case .goal: ShotTilePalette.goal
        case .onTarget: ShotTilePalette.onTarget
        case .miss: ShotTilePalette.miss
        }
    }

    /// Captions stay short because they're a confirmation, not the primary signal
    /// (`LIVE_SCREEN_PRINCIPLES.md` §1).
    func caption(for difficulty: ShotDifficulty) -> String {
        switch self {
        case .goal: "Goal"
        case .miss: "Miss"
        case .onTarget:
            switch difficulty {
            case .easy: "Big Save"
            case .hard: "Blocked"
            default: "Saved"
            }
        }
    }

    func accessibilityLabel(for difficulty: ShotDifficulty) -> String {
        switch self {
        case .goal: "\(difficulty.rawValue.capitalized) chance, goal"
        case .miss: "\(difficulty.rawValue.capitalized) chance, off target"
        case .onTarget:
            switch difficulty {
            case .easy: "Easy chance on target, big save by the keeper"
            case .hard: "Hard chance on target, blocked by a defender"
            default: "On target, saved by the keeper"
            }
        }
    }
}

enum ShotTilePalette {
    static let goal = Color(red: 0.192, green: 0.820, blue: 0.345)      // #31D158
    static let onTarget = Color(red: 0.996, green: 0.843, blue: 0.000)  // #FED700
    static let miss = Color(red: 0.557, green: 0.557, blue: 0.580)      // #8E8E94
    static let ink = Color(red: 0.090, green: 0.075, blue: 0.039)       // #17130A
    static let easyBanner = Color(red: 0.145, green: 0.620, blue: 0.380) // #259E61
    static let hardBanner = Color(red: 0.780, green: 0.278, blue: 0.118) // #C7471E

    static func ballColors(_ team: TeamSide) -> (light: Color, mid: Color, dark: Color) {
        team == .home
            ? (Color(red: 0.65, green: 1.00, blue: 0.77),
               Color(red: 0.192, green: 0.820, blue: 0.345),
               Color(red: 0.043, green: 0.353, blue: 0.133))
            : (Color(red: 1.00, green: 0.725, blue: 0.698),
               Color(red: 1.00, green: 0.271, blue: 0.227),
               Color(red: 0.478, green: 0.078, blue: 0.063))
    }
}

/// Drop-in replacement for `ShotOutcomeIcon` in the Live screen's shot rows.
/// The tile draws its own column-coloured capsule, so the call site does NOT need
/// `.buttonStyle(.borderedProminent).tint(color)` any more — see the handoff notes.
struct ShotTileIcon: View {
    let kind: ShotTileKind
    var difficulty: ShotDifficulty = .normal
    var possession: TeamSide = .home
    var showsCaption = true

    /// Everything is authored in this space and scaled to whatever the row hands us, so a
    /// row-height change can never double-scale the artwork the way the old
    /// `scaleEffect(minHeight / 64)` path could (`LIVE_SCREEN_PRINCIPLES.md` §6).
    private static let designSize = CGSize(width: 124.3, height: 80)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let unit = min(size.width / Self.designSize.width, size.height / Self.designSize.height)

            ZStack {
                Canvas { context, canvasSize in
                    context.scaleBy(
                        x: canvasSize.width / Self.designSize.width,
                        y: canvasSize.height / Self.designSize.height
                    )
                    draw(in: &context)
                }

                if let banner = bannerText {
                    VStack {
                        Text(banner)
                            .font(.system(size: 8 * unit, weight: .bold))
                            .kerning(0.8 * unit)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 13 * unit)
                            .background(bannerColor, in: RoundedRectangle(cornerRadius: 6 * unit))
                            .padding(.horizontal, 9 * unit)
                            .padding(.top, 3 * unit)
                        Spacer(minLength: 0)
                    }
                }

                if showsCaption {
                    VStack {
                        Spacer(minLength: 0)
                        NeonCaption(text: kind.caption(for: difficulty), accent: .white)
                            .padding(.bottom, 5 * unit)
                    }
                }
            }
            .background(kind.columnColor, in: Capsule())
            .clipShape(Capsule())
        }
        .accessibilityElement()
        .accessibilityLabel(kind.accessibilityLabel(for: difficulty))
    }

    private var bannerText: String? {
        switch difficulty {
        case .easy: "EASY"
        case .hard: "HARD"
        default: nil
        }
    }

    private var bannerColor: Color {
        difficulty == .easy ? ShotTilePalette.easyBanner : ShotTilePalette.hardBanner
    }

    // MARK: - Composition

    private func draw(in context: inout GraphicsContext) {
        let seam = kind.columnColor

        switch (difficulty, kind) {
        case (.easy, .goal):
            drawNet(&context, CGRect(x: 28, y: 8, width: 88, height: 56))
            drawBulge(&context, center: CGPoint(x: 74, y: 36), radius: CGSize(width: 18, height: 14))
            drawBall(&context, center: CGPoint(x: 74, y: 36), radius: 9.5)
            drawDashes(&context, path: curve(from: CGPoint(x: 8, y: 62), control: CGPoint(x: 34, y: 56), to: CGPoint(x: 58, y: 44)))

        case (.easy, .onTarget):
            drawNet(&context, CGRect(x: 40, y: 8, width: 78, height: 56))
            drawFigure(&context, NeonDivingKeeperFigure(), in: CGRect(x: 4, y: 16, width: 42, height: 42), seam: seam)
            drawBall(&context, center: CGPoint(x: 52, y: 26), radius: 8)
            drawArcs(&context, [(CGPoint(x: 74, y: 14), CGPoint(x: 84, y: 20), CGPoint(x: 90, y: 28)),
                                (CGPoint(x: 72, y: 26), CGPoint(x: 82, y: 30), CGPoint(x: 88, y: 37))])

        case (.easy, .miss):
            drawNet(&context, CGRect(x: 6, y: 8, width: 58, height: 56))
            drawDashes(&context, path: line(from: CGPoint(x: 68, y: 60), to: CGPoint(x: 104, y: 60)))
            drawBall(&context, center: CGPoint(x: 94, y: 50), radius: 9)

        case (.hard, .goal):
            drawGoal(&context, CGRect(x: 18, y: 8, width: 78, height: 42))
            drawWall(&context, seam: seam, y: 36, xs: [26, 46, 66], side: 32)
            drawBulge(&context, center: CGPoint(x: 83, y: 24), radius: CGSize(width: 10, height: 8))
            drawBall(&context, center: CGPoint(x: 83, y: 24), radius: 5.8)

        case (.hard, .onTarget):
            drawArcs(&context, [(CGPoint(x: 6, y: 68), CGPoint(x: 62, y: 68), CGPoint(x: 118, y: 68))])
            drawFigure(&context, NeonBlockerFigure(), in: CGRect(x: 14, y: 17, width: 46, height: 46), seam: seam)
            drawBall(&context, center: CGPoint(x: 66, y: 55), radius: 7)
            drawArcs(&context, [(CGPoint(x: 78, y: 46), CGPoint(x: 84, y: 56), CGPoint(x: 78, y: 66)),
                                (CGPoint(x: 85, y: 42), CGPoint(x: 93, y: 56), CGPoint(x: 85, y: 70))])

        case (.hard, .miss):
            drawGoal(&context, CGRect(x: 14, y: 8, width: 72, height: 40))
            drawWall(&context, seam: seam, y: 36, xs: [22, 42, 62], side: 32)
            drawDashes(&context, path: curve(from: CGPoint(x: 40, y: 74), control: CGPoint(x: 72, y: 48), to: CGPoint(x: 90, y: 34)))
            drawBall(&context, center: CGPoint(x: 98, y: 28), radius: 5.8)

        case (_, .goal):
            drawGoal(&context, CGRect(x: 24, y: 12, width: 76, height: 44))
            drawBulge(&context, center: CGPoint(x: 70, y: 38), radius: CGSize(width: 12, height: 9))
            drawBall(&context, center: CGPoint(x: 70, y: 38), radius: 6.5)
            drawDashes(&context, path: curve(from: CGPoint(x: 14, y: 70), control: CGPoint(x: 40, y: 62), to: CGPoint(x: 60, y: 44)))

        case (_, .onTarget):
            drawGoal(&context, CGRect(x: 24, y: 12, width: 76, height: 44))
            drawFigure(&context, NeonKeeperFigure(), in: CGRect(x: 48, y: 16, width: 38, height: 38), seam: seam)
            drawDashes(&context, path: curve(from: CGPoint(x: 6, y: 40), control: CGPoint(x: 20, y: 44), to: CGPoint(x: 30, y: 47)))
            drawBall(&context, center: CGPoint(x: 38, y: 50), radius: 6.5)

        case (_, .miss):
            drawGoal(&context, CGRect(x: 24, y: 12, width: 76, height: 44))
            drawDashes(&context, path: curve(from: CGPoint(x: 30, y: 74), control: CGPoint(x: 64, y: 44), to: CGPoint(x: 92, y: 28)))
            drawBall(&context, center: CGPoint(x: 100, y: 22), radius: 6.5)
        }
    }

    // MARK: - Pieces

    private func drawBall(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let colors = ShotTilePalette.ballColors(possession)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [colors.light, colors.mid, colors.dark]),
                center: CGPoint(x: center.x - radius * 0.36, y: center.y - radius * 0.48),
                startRadius: 0,
                endRadius: radius * 1.6
            )
        )
        context.fill(ballPanels(center: center, radius: radius), with: .color(.black.opacity(0.66)))
        context.stroke(Path(ellipseIn: rect), with: .color(colors.dark), lineWidth: radius * 0.09)
    }

    /// Same panel layout as `NeonBall`'s `BallPanels`: a pentagon at 0.33r with five
    /// surrounding patches at 0.80r, which is what makes it read as a football rather than
    /// a dot at 6pt.
    private func ballPanels(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in 0..<5 {
            let angle = Double(index) / 5 * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius * 0.33,
                y: center.y + sin(angle) * radius * 0.33
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()

        for index in 0..<5 {
            let angle = Double(index) / 5 * 2 * .pi - .pi / 2 + .pi / 5
            let cx = center.x + cos(angle) * radius * 0.80
            let cy = center.y + sin(angle) * radius * 0.80
            let r = radius * 0.17
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
        return path
    }

    /// Front frame, four struts to the back plane, and a sagging mesh — the same
    /// construction as `NeonGoal`, redrawn in ink weights that hold up on a light fill.
    private func drawGoal(_ context: inout GraphicsContext, _ rect: CGRect) {
        let inset = rect.width * 0.16
        let vInset = rect.height * 0.088
        let back = CGRect(x: rect.minX + inset, y: rect.minY + vInset,
                          width: rect.width - inset * 2, height: rect.height - vInset)
        let sag = back.height * 0.045

        var mesh = Path()
        for index in 0...9 {
            let x = back.minX + back.width * CGFloat(index) / 9
            mesh.move(to: CGPoint(x: x, y: back.minY))
            mesh.addLine(to: CGPoint(x: x, y: back.maxY))
        }
        for index in 0...5 {
            let y = back.minY + back.height * CGFloat(index) / 5
            mesh.move(to: CGPoint(x: back.minX, y: y))
            mesh.addQuadCurve(to: CGPoint(x: back.maxX, y: y),
                              control: CGPoint(x: back.midX, y: y + sag))
        }
        for index in 1...3 {
            let t = CGFloat(index) / 4
            mesh.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * t))
            mesh.addLine(to: CGPoint(x: back.minX, y: back.minY + back.height * t))
            mesh.move(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * t))
            mesh.addLine(to: CGPoint(x: back.maxX, y: back.minY + back.height * t))
        }
        context.stroke(mesh, with: .color(ShotTilePalette.ink.opacity(0.4)), lineWidth: 0.45)

        var posts = Path()
        posts.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        posts.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        posts.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        posts.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        posts.move(to: CGPoint(x: rect.minX, y: rect.minY))
        posts.addLine(to: CGPoint(x: back.minX, y: back.minY))
        posts.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        posts.addLine(to: CGPoint(x: back.maxX, y: back.minY))
        posts.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        posts.addLine(to: CGPoint(x: back.minX, y: rect.maxY))
        posts.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        posts.addLine(to: CGPoint(x: back.maxX, y: rect.maxY))
        context.stroke(posts, with: .color(ShotTilePalette.ink),
                       style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
    }

    private func drawNet(_ context: inout GraphicsContext, _ rect: CGRect) {
        var path = Path()
        for index in 0...10 {
            let x = rect.minX + rect.width * CGFloat(index) / 10
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for index in 0...6 {
            let y = rect.minY + rect.height * CGFloat(index) / 6
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(path, with: .color(ShotTilePalette.ink.opacity(0.38)), lineWidth: 0.55)
    }

    private func drawFigure<S: Shape>(_ context: inout GraphicsContext, _ shape: S, in rect: CGRect, seam: Color) {
        let path = shape.path(in: rect)
        context.fill(path, with: .color(ShotTilePalette.ink))
        // Seam in the tile's own fill colour: overlapping limbs separate the way the neon
        // glow separates them on the black set-piece artwork.
        context.stroke(path, with: .color(seam), style: StrokeStyle(lineWidth: 0.85, lineJoin: .round))
    }

    private func drawWall(_ context: inout GraphicsContext, seam: Color, y: CGFloat, xs: [CGFloat], side: CGFloat) {
        for x in xs {
            drawFigure(&context, NeonWallFigure(), in: CGRect(x: x, y: y, width: side, height: side), seam: seam)
        }
    }

    /// Concentric rings where the ball has pushed the net out — same idea as `NetBulge`,
    /// inlined here so it can be drawn inside the same `Canvas` pass.
    private func drawBulge(_ context: inout GraphicsContext, center: CGPoint, radius: CGSize) {
        for ring in 0..<3 {
            let k = 1 - CGFloat(ring) * 0.28
            let rect = CGRect(x: center.x - radius.width * k, y: center.y - radius.height * k,
                              width: radius.width * 2 * k, height: radius.height * 2 * k)
            context.stroke(Path(ellipseIn: rect),
                           with: .color(ShotTilePalette.ink.opacity(0.6 - Double(ring) * 0.16)),
                           lineWidth: 0.75)
        }
    }

    private func drawDashes(_ context: inout GraphicsContext, path: Path) {
        context.stroke(path, with: .color(ShotTilePalette.ink.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 2.6]))
    }

    private func drawArcs(_ context: inout GraphicsContext, _ arcs: [(CGPoint, CGPoint, CGPoint)]) {
        var path = Path()
        for arc in arcs {
            path.move(to: arc.0)
            path.addQuadCurve(to: arc.2, control: arc.1)
        }
        context.stroke(path, with: .color(ShotTilePalette.ink.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    private func curve(from start: CGPoint, control: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    private func line(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

/// Outfield defender with the near leg thrown out at the ball — the Hard row's
/// "on target, denied" figure. Built from `NeonAnatomy.limb` so the taper matches the
/// keeper and wall figures: arms noticeably thinner than legs, boot end thinner than thigh.
struct NeonBlockerFigure: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        let unit = rect.height
        let hip = point(0.42, 0.62)
        let shoulder = point(0.44, 0.30)

        path.addPath(NeonAnatomy.limb(from: shoulder, to: hip, startWidth: unit * 0.26, endWidth: unit * 0.22))
        path.addPath(NeonAnatomy.limb(from: shoulder, to: point(0.28, 0.46), startWidth: unit * 0.11, endWidth: unit * 0.09))
        path.addPath(NeonAnatomy.limb(from: shoulder, to: point(0.60, 0.44), startWidth: unit * 0.11, endWidth: unit * 0.09))
        path.addPath(NeonAnatomy.limb(from: hip, to: point(0.34, 0.86), startWidth: unit * 0.21, endWidth: unit * 0.15))
        path.addPath(NeonAnatomy.limb(from: point(0.34, 0.86), to: point(0.30, 0.97), startWidth: unit * 0.15, endWidth: unit * 0.11))
        path.addPath(NeonAnatomy.limb(from: hip, to: point(0.66, 0.74), startWidth: unit * 0.22, endWidth: unit * 0.16))
        path.addPath(NeonAnatomy.limb(from: point(0.66, 0.74), to: point(0.84, 0.80), startWidth: unit * 0.16, endWidth: unit * 0.12))

        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.325,
                y: rect.minY + rect.height * 0.005,
                width: rect.width * 0.23,
                height: rect.height * 0.25
            )
        )
        return path
    }
}

#Preview("Shot tiles — home") {
    VStack(spacing: 6) {
        ForEach([ShotDifficulty.normal, .easy, .hard], id: \.self) { difficulty in
            HStack(spacing: 8) {
                ForEach(ShotTileKind.allCases) { kind in
                    ShotTileIcon(kind: kind, difficulty: difficulty, possession: .home)
                        .frame(height: difficulty == .normal ? 80 : 78)
                }
            }
        }
    }
    .padding(12)
    .background(Color(white: 0.12))
}

#Preview("Shot tiles — away") {
    VStack(spacing: 6) {
        ForEach([ShotDifficulty.normal, .easy, .hard], id: \.self) { difficulty in
            HStack(spacing: 8) {
                ForEach(ShotTileKind.allCases) { kind in
                    ShotTileIcon(kind: kind, difficulty: difficulty, possession: .away)
                        .frame(height: difficulty == .normal ? 80 : 78)
                }
            }
        }
    }
    .padding(12)
    .background(Color(white: 0.12))
}
