import SwiftUI

enum PossessionChartStyle {
    case compact
    case full
}

/// Team identity is carried by `MatchTeamsLegend` above the chart rather than by
/// labels inside the plot, which collided with the pressure curve.
struct PossessionChartView: View {
    let points: [PressureChartPoint]
    let goalMarkers: [GoalChartMarker]
    let shotTicks: [ShotTickMarker]
    var style: PossessionChartStyle = .full
    /// Looked up per goal marker to show a credited player's face instead of the plain
    /// ball. Left `nil` (the default) for callers that don't have a roster to check —
    /// including the headless `PossessionChartRenderer.image(...)` share-image path, which
    /// builds its own `PossessionChartView` and never sets this.
    var avatarImage: ((UUID) -> UIImage?)?
    /// Looked up per credited player only when they have no photo, so the credited row can
    /// show initials instead of looking identical to an uncredited empty slot.
    var initials: ((UUID) -> String?)?
    /// Fires when a goal's slot in the credited row is tapped — `nil` (the default) leaves
    /// it inert.
    var onGoalTap: ((GoalChartMarker) -> Void)?
    /// Fires when a big save's slot in the credited row is tapped — `nil` leaves it inert.
    var onSaveTap: ((ShotTickMarker) -> Void)?

    init(
        points: [PressureChartPoint],
        goalMarkers: [GoalChartMarker] = [],
        shotTicks: [ShotTickMarker] = [],
        style: PossessionChartStyle = .full,
        avatarImage: ((UUID) -> UIImage?)? = nil,
        initials: ((UUID) -> String?)? = nil,
        onGoalTap: ((GoalChartMarker) -> Void)? = nil,
        onSaveTap: ((ShotTickMarker) -> Void)? = nil
    ) {
        self.points = points
        self.goalMarkers = goalMarkers
        self.shotTicks = shotTicks
        self.style = style
        self.avatarImage = avatarImage
        self.initials = initials
        self.onGoalTap = onGoalTap
        self.onSaveTap = onSaveTap
    }

    private func creditedAvatar(for playerID: UUID?) -> UIImage? {
        playerID.flatMap { avatarImage?($0) }
    }

    private func creditedInitials(for playerID: UUID?) -> String? {
        guard let playerID, creditedAvatar(for: playerID) == nil else { return nil }
        return initials?(playerID)
    }

    private var showsDecorations: Bool { style == .full }

    var body: some View {
        GeometryReader { geometry in
            let layout = ChartLayout(
                size: geometry.size,
                points: points,
                goalMarkers: goalMarkers,
                showsTicks: showsDecorations && !shotTicks.isEmpty,
                showsAxis: showsDecorations
            )
            let segments = Self.coloredSegments(from: points)
            let lineWidth: CGFloat = style == .compact ? 1.5 : 2

            ZStack {
                Canvas { context, size in
                    var centerPath = Path()
                    centerPath.move(to: CGPoint(x: 0, y: layout.zeroY))
                    centerPath.addLine(to: CGPoint(x: size.width, y: layout.zeroY))
                    context.stroke(
                        centerPath,
                        with: .color(.secondary.opacity(style == .compact ? 0.4 : 0.6)),
                        style: StrokeStyle(lineWidth: 1, dash: style == .compact ? [3, 3] : [5, 4])
                    )

                    for segment in segments {
                        let coordinates = segment.points.map { layout.coordinate(for: $0) }
                        guard let first = coordinates.first else { continue }

                        var linePath = Path()
                        linePath.move(to: first)
                        for coordinate in coordinates.dropFirst() {
                            linePath.addLine(to: coordinate)
                        }

                        let color: Color = segment.isPositive ? .green : .red

                        if style == .full, coordinates.count >= 2 {
                            var fillPath = linePath
                            fillPath.addLine(to: CGPoint(x: coordinates.last!.x, y: layout.zeroY))
                            fillPath.addLine(to: CGPoint(x: first.x, y: layout.zeroY))
                            fillPath.closeSubpath()
                            context.fill(fillPath, with: .color(color.opacity(0.35)))
                        }

                        context.stroke(
                            linePath,
                            with: .color(color),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                    }

                    if layout.showsTicks {
                        drawShotTicks(in: &context, layout: layout)
                    }

                    if layout.showsAxis {
                        drawGoalNotches(in: &context, layout: layout, size: size)
                    }
                }

                ForEach(goalMarkers) { goal in
                    let above = goal.pressureValue >= 0
                    let anchor = layout.coordinate(
                        for: PressureChartPoint(matchSeconds: goal.matchSeconds, value: goal.pressureValue)
                    )
                    let ballSize: CGFloat = style == .compact ? 10 : 14
                    let offset: CGFloat = showsDecorations ? 19 : 12

                    // Purely visual — crediting now happens from the row below, not here,
                    // so the ball on the pressure line stays a single plain circle.
                    GoalBallBadge(
                        team: goal.team,
                        size: ballSize,
                        scoreLabel: showsDecorations ? goal.scoreLabel : nil,
                        scoreAbove: above
                    )
                    .position(
                        x: anchor.x,
                        y: layout.clampedMarkerY(anchor.y + (above ? -offset : offset))
                    )
                }

                // The tappable surface for crediting: one slot per home goal and one per
                // away big save (a face once credited, an empty dashed ring until then).
                if layout.showsTicks {
                    ForEach(goalMarkers.filter { $0.team == .home }) { goal in
                        CreditedSlotBadge(
                            avatar: creditedAvatar(for: goal.creditedPlayerID),
                            initials: creditedInitials(for: goal.creditedPlayerID),
                            tint: .green,
                            onTap: { onGoalTap?(goal) }
                        )
                        .position(x: layout.x(forSeconds: goal.matchSeconds), y: layout.creditedRowY)
                    }

                    // Green, not red — the away shot itself is red, but this slot credits
                    // *our* keeper, same as the goal slots credit our scorers.
                    ForEach(shotTicks.filter(\.isCreditableSave)) { tick in
                        CreditedSlotBadge(
                            avatar: creditedAvatar(for: tick.creditedPlayerID),
                            initials: creditedInitials(for: tick.creditedPlayerID),
                            tint: .green,
                            onTap: { onSaveTap?(tick) }
                        )
                        .position(x: layout.x(forSeconds: tick.matchSeconds), y: layout.creditedRowY)
                    }
                }

                if layout.showsAxis {
                    let axisLabels = Self.axisLabelPlacements(
                        goals: goalMarkers,
                        layout: layout
                    )
                    ForEach(axisLabels) { placement in
                        Text(placement.text)
                            .font(.system(
                                size: placement.isAnchor ? 7 : 8,
                                weight: placement.isAnchor ? .regular : .medium,
                                design: .rounded
                            ))
                            .foregroundStyle(placement.isAnchor ? Color.secondary.opacity(0.55) : .secondary)
                            .fixedSize()
                            .position(
                                x: placement.labelX,
                                y: layout.axisLabelY(row: placement.row)
                            )
                    }
                }

            }
        }
    }

    private func drawShotTicks(in context: inout GraphicsContext, layout: ChartLayout) {
        for tick in shotTicks {
            let x = layout.x(forSeconds: tick.matchSeconds)
            let isHome = tick.team == .home
            let top = isHome
                ? layout.plotRect.minY - ChartLayout.tickStripHeight
                : layout.plotRect.maxY + 2
            let height = tick.isGoal
                ? ChartLayout.tickStripHeight - 2
                : ChartLayout.tickStripHeight - 4

            // Every big save glows, in whichever team's colour actually took the shot. A
            // creditable one (away shot, our keeper) reaches down and stops exactly at its
            // face slot in the credited row — reads as the line being "caught" by the
            // avatar, not passing through it. One saved by the opposing keeper (our own
            // attempt) has no face to reach for, so it keeps the tick's normal short length.
            if tick.isBigSave {
                let startY = isHome ? top + (ChartLayout.tickStripHeight - 2 - height) : top
                let endY = tick.isCreditableSave
                    ? layout.creditedRowY
                    : (isHome ? top + ChartLayout.tickStripHeight - 2 : top + height)

                var glowPath = Path()
                glowPath.move(to: CGPoint(x: x, y: startY))
                glowPath.addLine(to: CGPoint(x: x, y: endY))

                let glowColor: Color = isHome ? .green : .red
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 2.5))
                    layer.stroke(glowPath, with: .color(glowColor.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                context.stroke(glowPath, with: .color(glowColor), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                continue
            }

            var path = Path()
            path.move(to: CGPoint(x: x, y: isHome ? top + (ChartLayout.tickStripHeight - 2 - height) : top))
            path.addLine(to: CGPoint(x: x, y: isHome ? top + ChartLayout.tickStripHeight - 2 : top + height))

            // Off-target attempts are dotted rather than faint, so they stay legible
            // while still reading as the lesser mark.
            let base: Color = isHome ? .green : .red
            context.stroke(
                path,
                with: .color(base.opacity(tick.isOnTarget ? 0.9 : 0.7)),
                style: StrokeStyle(
                    lineWidth: tick.isGoal ? 2.5 : 1.5,
                    lineCap: .butt,
                    dash: tick.isOnTarget ? [] : [1.5, 1.5]
                )
            )
        }
    }

    private func drawGoalNotches(in context: inout GraphicsContext, layout: ChartLayout, size: CGSize) {
        var axisPath = Path()
        axisPath.move(to: CGPoint(x: 0, y: layout.axisY))
        axisPath.addLine(to: CGPoint(x: size.width, y: layout.axisY))
        context.stroke(axisPath, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 0.5))

        // Notches hang below the axis line while shot ticks sit above it, so the two
        // rows stay distinguishable even though they share the team colours.
        for goal in goalMarkers {
            let x = layout.x(forSeconds: goal.matchSeconds)
            var notch = Path()
            notch.move(to: CGPoint(x: x, y: layout.axisY))
            notch.addLine(to: CGPoint(x: x, y: layout.axisY + 5))
            let color: Color = goal.team == .home ? .green : .red
            context.stroke(notch, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
        }
    }

    // MARK: - Axis label placement

    fileprivate struct AxisLabelPlacement: Identifiable {
        let id: String
        let text: String
        let labelX: CGFloat
        let row: Int
        let isAnchor: Bool
    }

    /// Faint kickoff / half / full-time markers give the long middle of a match a clock
    /// context. Goal minutes still win when they would collide.
    fileprivate static func timeAnchors(maxSeconds: Int) -> [(seconds: Int, label: String)] {
        guard maxSeconds > 0 else { return [] }

        var anchors: [(seconds: Int, label: String)] = [(0, "0'")]
        let half = 30 * 60
        // Only place 30' when there is clear space after kickoff and before FT.
        if maxSeconds >= half + 8 * 60 {
            anchors.append((half, "30'"))
        }
        anchors.append((maxSeconds, "FT"))
        return anchors
    }

    /// Anchors are placed first (faint), then goal minutes dodge them and each other.
    fileprivate static func axisLabelPlacements(
        goals: [GoalChartMarker],
        layout: ChartLayout
    ) -> [AxisLabelPlacement] {
        let labelWidth: CGFloat = 22
        var lastX: [CGFloat] = [-.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        var placements: [AxisLabelPlacement] = []
        var previousRow = 0

        func place(id: String, text: String, seconds: Int, isAnchor: Bool) {
            let rawX = layout.x(forSeconds: seconds)
            let x = min(max(rawX, labelWidth / 2), layout.size.width - labelWidth / 2)

            // Skip an anchor that would sit on top of an already-placed label (usually a
            // late goal near FT). Goal minutes never skip — they stagger to another row.
            if isAnchor, lastX.contains(where: { abs(x - $0) < labelWidth }) {
                return
            }

            let row: Int
            if let free = lastX.indices.first(where: { abs(x - lastX[$0]) >= labelWidth }) {
                row = free
            } else {
                row = (previousRow + 1) % lastX.count
            }

            lastX[row] = x
            previousRow = row
            placements.append(
                AxisLabelPlacement(id: id, text: text, labelX: x, row: row, isAnchor: isAnchor)
            )
        }

        for anchor in timeAnchors(maxSeconds: layout.maxSeconds) {
            // Prefer the goal minute when a goal lands almost on an anchor (e.g. 59' vs FT).
            let nearGoal = goals.contains { abs($0.matchSeconds - anchor.seconds) < 90 }
            if nearGoal { continue }
            place(id: "anchor-\(anchor.label)", text: anchor.label, seconds: anchor.seconds, isAnchor: true)
        }

        for goal in goals.sorted(by: { $0.matchSeconds < $1.matchSeconds }) {
            place(
                id: "goal-\(goal.id.uuidString)",
                text: goal.minuteLabel,
                seconds: goal.matchSeconds,
                isAnchor: false
            )
        }

        return placements
    }

    fileprivate struct ChartLayout {
        static let tickStripHeight: CGFloat = 11
        static let axisHeight: CGFloat = 32
        /// Every credited shot (goal or big save) shows its player's face in one row just
        /// below the tick strip — always reserved, so the chart's proportions don't shift
        /// depending on whether this particular match has any credited shots in it.
        static let creditedRowHeight: CGFloat = 22

        let size: CGSize
        let plotRect: CGRect
        let minSeconds: Int
        let maxSeconds: Int
        let maxAbs: Double
        let showsTicks: Bool
        let showsAxis: Bool

        init(
            size: CGSize,
            points: [PressureChartPoint],
            goalMarkers: [GoalChartMarker],
            showsTicks: Bool,
            showsAxis: Bool
        ) {
            self.size = size
            self.showsTicks = showsTicks
            self.showsAxis = showsAxis
            self.minSeconds = points.first?.matchSeconds ?? 0
            self.maxSeconds = max(
                points.last?.matchSeconds ?? 0,
                goalMarkers.map(\.matchSeconds).max() ?? 0,
                1
            )
            let pointMax = points.map { abs($0.value) }.max() ?? 0
            let markerMax = goalMarkers.map { abs($0.pressureValue) }.max() ?? 0
            self.maxAbs = max(pointMax, markerMax, 3)

            let strip = showsTicks ? Self.tickStripHeight : 0
            let creditedRow = showsTicks ? Self.creditedRowHeight : 0
            let axis = showsAxis ? Self.axisHeight : 0
            let plotHeight = max(size.height - (strip * 2) - creditedRow - axis, 40)
            self.plotRect = CGRect(x: 0, y: strip, width: size.width, height: plotHeight)
        }

        var zeroY: CGFloat { plotRect.midY }

        /// Space consumed below the plot area, so overlaid labels can keep clear of it.
        var bottomChrome: CGFloat {
            (showsTicks ? Self.tickStripHeight + Self.creditedRowHeight : 0) + (showsAxis ? Self.axisHeight : 0)
        }

        /// Vertical centre of the credited-shot face row, just below the tick strip.
        var creditedRowY: CGFloat {
            plotRect.maxY + Self.tickStripHeight + Self.creditedRowHeight / 2
        }

        var axisY: CGFloat {
            plotRect.maxY + (showsTicks ? Self.tickStripHeight + Self.creditedRowHeight : 0) + 7
        }

        func axisLabelY(row: Int) -> CGFloat {
            axisY + 10 + CGFloat(row) * 9
        }

        func x(forSeconds seconds: Int) -> CGFloat {
            let xRange = max(maxSeconds - minSeconds, 1)
            return size.width * CGFloat(seconds - minSeconds) / CGFloat(xRange)
        }

        func coordinate(for point: PressureChartPoint) -> CGPoint {
            let normalized = (maxAbs - point.value) / (2 * maxAbs)
            return CGPoint(
                x: x(forSeconds: point.matchSeconds),
                y: plotRect.minY + plotRect.height * CGFloat(normalized)
            )
        }

        func clampedMarkerY(_ y: CGFloat) -> CGFloat {
            min(max(y, plotRect.minY + 10), plotRect.maxY - 10)
        }
    }

    private struct ColoredPressureSegment: Identifiable {
        let id = UUID()
        let isPositive: Bool
        let points: [PressureChartPoint]
    }

    private static func coloredSegments(from points: [PressureChartPoint]) -> [ColoredPressureSegment] {
        guard let first = points.first else { return [] }

        var segments: [ColoredPressureSegment] = []
        var isPositive = first.value >= 0
        var currentPoints = [first]

        for index in 1..<points.count {
            let point = points[index]
            let pointIsPositive = point.value >= 0

            if pointIsPositive == isPositive {
                currentPoints.append(point)
                continue
            }

            let zeroPoint = zeroCrossing(between: points[index - 1], and: point)
            currentPoints.append(zeroPoint)
            segments.append(ColoredPressureSegment(isPositive: isPositive, points: currentPoints))
            isPositive = pointIsPositive
            currentPoints = [zeroPoint, point]
        }

        segments.append(ColoredPressureSegment(isPositive: isPositive, points: currentPoints))
        return segments
    }

    private static func zeroCrossing(between start: PressureChartPoint, and end: PressureChartPoint) -> PressureChartPoint {
        let total = abs(start.value) + abs(end.value)
        guard total > 0 else {
            return PressureChartPoint(matchSeconds: end.matchSeconds, value: 0)
        }

        let fraction = abs(start.value) / total
        let seconds = start.matchSeconds + Int((Double(end.matchSeconds - start.matchSeconds) * fraction).rounded())
        return PressureChartPoint(matchSeconds: seconds, value: 0)
    }
}

private struct GoalBallBadge: View {
    let team: TeamSide
    let size: CGFloat
    let scoreLabel: String?
    let scoreAbove: Bool

    private var tint: Color {
        // Match the rest of the card: home green, away red. Amber read as a third team.
        team == .home
            ? Color(red: 0.45, green: 1.0, blue: 0.5)
            : Color(red: 1.0, green: 0.38, blue: 0.38)
    }

    // Deliberately just the ball, centred on the pressure line where the goal happened —
    // who scored shows up in the credited-shot row below instead (see `PossessionChartView`
    // body), not paired onto this marker, so the marker stays one circle, not two.
    private var ball: some View {
        Text("⚽")
            .font(.system(size: size))
            .colorMultiply(tint)
    }

    private var score: some View {
        Group {
            if let scoreLabel {
                Text(scoreLabel)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(team == .home ? .green : .red)
                    .fixedSize()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if scoreAbove {
                score
                ball
            } else {
                ball
                score
            }
        }
    }
}

/// A cropped avatar in a team-tinted ring — shared by `GoalBallBadge` (next to the ball,
/// once a goal is credited) and the credited-big-save row in the tick strip below the plot.
/// No circular clip/ring — trying the credited-row faces plain, square, uncropped.
/// Cropped circular, same treatment as the roster photo picker/crop UI
/// (`PlayerEditorView.swift`'s `.clipShape(Circle())`) — square/uncropped was a one-off
/// experiment, not the final look.
private struct AvatarCircle: View {
    let image: UIImage
    let tint: Color
    let diameter: CGFloat

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(tint, lineWidth: 1))
    }
}

/// One slot in the credited row: the player's face once credited, their initials if
/// credited but photo-less, or an empty dashed ring (in the relevant team's colour) that's
/// still tappable to credit for the first time. Initials use the same tint as a photo would
/// so a credited-but-photo-less slot doesn't read as identical to an uncredited one.
private struct CreditedSlotBadge: View {
    let avatar: UIImage?
    let initials: String?
    let tint: Color
    let onTap: () -> Void

    var body: some View {
        ZStack {
            // The visible badge stays tiny; the tap target doesn't, per Apple's ~44pt
            // hit-area guidance.
            Color.clear
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())

            if let avatar {
                AvatarCircle(image: avatar, tint: tint, diameter: 16)
            } else if let initials {
                CreditedInitialsBadge(initials: initials, tint: tint, diameter: 16)
            } else {
                Circle()
                    .strokeBorder(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 14, height: 14)
            }
        }
        .onTapGesture(perform: onTap)
    }
}

/// Same footprint as `AvatarCircle`, for a credited player with no photo.
private struct CreditedInitialsBadge: View {
    let initials: String
    let tint: Color
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(tint.opacity(0.2))
            .overlay(Circle().strokeBorder(tint, lineWidth: 1))
            .overlay(
                Text(initials)
                    .font(.system(size: diameter * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            )
            .frame(width: diameter, height: diameter)
    }
}

/// Colour-codes the team names so green/red is unambiguous everywhere else in the card.
struct MatchTeamsLegend: View {
    let homeName: String
    let awayName: String
    var font: Font = .subheadline

    /// Both names take an equal share of the width so "vs" lands dead centre, lining up
    /// with the centred stat labels below.
    var body: some View {
        HStack(spacing: 6) {
            Text(homeName)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("vs")
                .foregroundStyle(.secondary)
            Text(awayName)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(font)
        .fontWeight(.medium)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

struct ComparisonBarsView: View {
    let stats: [ComparisonStat]
    var valueFont: Font = .system(size: 12, weight: .semibold, design: .rounded)
    var labelFont: Font = .system(size: 11)
    var barHeight: CGFloat = 5
    var rowSpacing: CGFloat = 9

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(stats) { stat in
                VStack(spacing: 3) {
                    ZStack {
                        HStack(spacing: 6) {
                            Text(stat.homeText)
                                .font(valueFont)
                                .foregroundStyle(.green)
                            Spacer(minLength: 4)
                            Text(stat.awayText)
                                .font(valueFont)
                                .foregroundStyle(.red)
                        }
                        Text(stat.label)
                            .font(labelFont)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        let gap: CGFloat = 2
                        let available = max(geometry.size.width - gap, 0)
                        switch stat.style {
                        case .share:
                            HStack(spacing: gap) {
                                Capsule()
                                    .fill(Color.green)
                                    .frame(width: available * CGFloat(stat.homeFraction))
                                Capsule()
                                    .fill(Color.red)
                            }
                        case .rate:
                            let half = available / 2
                            HStack(spacing: gap) {
                                gauge(width: half, fill: stat.homeValue / 100, color: .green, alignment: .leading)
                                gauge(width: half, fill: stat.awayValue / 100, color: .red, alignment: .trailing)
                            }
                        case .nested:
                            ZStack {
                                HStack(spacing: gap) {
                                    Capsule()
                                        .fill(Color.green.opacity(0.62))
                                        .frame(width: available * CGFloat(stat.homeTotalFraction))
                                    Capsule()
                                        .fill(Color.red.opacity(0.62))
                                }
                                HStack(spacing: 0) {
                                    highlight(width: available * CGFloat(stat.homeSubsetFraction), color: .green)
                                    Spacer(minLength: 0)
                                    highlight(width: available * CGFloat(stat.awaySubsetFraction), color: .red)
                                }
                            }
                        case .keeping:
                            // Saves sit on the outside edges; grey goals conceded meet at the
                            // centre gap — what got through sits between the two keepers.
                            ZStack {
                                HStack(spacing: gap) {
                                    HStack(spacing: 0) {
                                        Color.green.opacity(0.62)
                                            .frame(width: available * CGFloat(stat.homeSubsetFraction))
                                        Color.secondary.opacity(0.28)
                                            .frame(width: available * CGFloat(stat.homeConcededFraction))
                                    }
                                    .clipShape(Capsule())

                                    HStack(spacing: 0) {
                                        Color.secondary.opacity(0.28)
                                            .frame(width: available * CGFloat(stat.awayConcededFraction))
                                        Color.red.opacity(0.62)
                                            .frame(width: available * CGFloat(stat.awaySubsetFraction))
                                    }
                                    .clipShape(Capsule())
                                }
                                HStack(spacing: 0) {
                                    highlight(width: available * CGFloat(stat.homeGlowFraction), color: .green)
                                    Spacer(minLength: 0)
                                    highlight(width: available * CGFloat(stat.awayGlowFraction), color: .red)
                                }
                            }
                        }
                    }
                    .frame(height: barHeight)
                }
            }
        }
    }

    /// The lit subset of a `.nested` bar. Full saturation plus a same-colour halo makes
    /// it read as glowing against the dimmed total behind it.
    private func highlight(width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .shadow(color: color.opacity(0.85), radius: 2.5)
            .frame(width: width)
    }

    /// Independent percentage: the faint track shows the 100% extent so a long bar
    /// reads as "close to perfect" rather than "bigger share than the other team".
    private func gauge(
        width: CGFloat,
        fill: Double,
        color: Color,
        alignment: Alignment
    ) -> some View {
        ZStack(alignment: alignment) {
            Capsule()
                .fill(Color.secondary.opacity(0.18))
            Capsule()
                .fill(color)
                .frame(width: width * CGFloat(min(max(fill, 0), 1)))
        }
        .frame(width: width)
    }
}

@MainActor
enum PossessionChartRenderer {
    static func image(
        points: [PressureChartPoint],
        goalMarkers: [GoalChartMarker],
        shotTicks: [ShotTickMarker] = [],
        goalsStat: ComparisonStat? = nil,
        possessionStat: ComparisonStat? = nil,
        comparisonStats: [ComparisonStat] = [],
        homeName: String,
        awayName: String,
        width: CGFloat = 450,
        chartHeight: CGFloat = 330,
        avatarImage: ((UUID) -> UIImage?)? = nil,
        initials: ((UUID) -> String?)? = nil
    ) -> UIImage? {
        let card = VStack(alignment: .leading, spacing: 10) {
            MatchTeamsLegend(homeName: homeName, awayName: awayName, font: .title3)

            if goalsStat != nil || possessionStat != nil {
                VStack(spacing: 8) {
                    if let goalsStat {
                        ComparisonBarsView(
                            stats: [goalsStat],
                            valueFont: .system(size: 26, weight: .bold, design: .rounded),
                            labelFont: .system(size: 13, weight: .medium),
                            barHeight: 7
                        )
                    }

                    if let possessionStat {
                        ComparisonBarsView(
                            stats: [possessionStat],
                            valueFont: .system(size: 11, weight: .semibold, design: .rounded),
                            labelFont: .system(size: 10),
                            barHeight: 3
                        )
                    }
                }
            }

            PossessionChartView(
                points: points,
                goalMarkers: goalMarkers,
                shotTicks: shotTicks,
                style: .full,
                avatarImage: avatarImage,
                initials: initials
            )
            .frame(height: chartHeight)

            if !shotTicks.isEmpty {
                Text("Ticks above and below the chart are attempts — solid is on target, dotted is off target.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if !comparisonStats.isEmpty {
                Divider()
                ComparisonBarsView(stats: comparisonStats)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(width: width)
        .background(Color(.systemBackground))

        let renderer = ImageRenderer(content: card)
        renderer.isOpaque = true
        renderer.scale = 3
        return renderer.uiImage?.opaqueForClipboard()
    }
}
