import SwiftUI
import UIKit

// The Goal Map, shown inside the Summary tab's Pressure Index card: an isometric pitch with
// every placed goal drawn as a neon arc from where it was struck to where it crossed the
// line. Entry lives in `GoalPlacementSheet.swift`, opened by tapping a goal's ball on the
// pressure chart above it.

enum GoalMapPalette {
    /// Home green / away red, same as every other chart on the Summary tab.
    static func tint(for team: TeamSide) -> Color {
        team == .home ? NeonIconPalette.green : NeonIconPalette.red
    }

    /// The team colours again, deepened to read as *text* on white — the neon pair above is
    /// made for a dark stage and washes out against the exported image's white page.
    static func ink(for team: TeamSide) -> Color {
        team == .home
            ? Color(red: 0.09, green: 0.60, blue: 0.24)
            : Color(red: 0.82, green: 0.13, blue: 0.17)
    }

    /// The dark frame the pitch sits in. Deliberately neutral — no blue anywhere on this map.
    static let stageTop = Color(red: 0.07, green: 0.08, blue: 0.08)
    static let stageBottom = Color(red: 0.12, green: 0.13, blue: 0.12)
}

// MARK: - Surfaces

struct GoalMapSurfaceStyle {
    let near: Color
    let far: Color
    /// The darker repeat laid over the base: alternate mown bars, or the seams between boards.
    let tone: Color
    let line: Color
    let lineWidth: CGFloat
}

extension GoalMapSurface {
    var style: GoalMapSurfaceStyle {
        switch self {
        case .grass:
            // Greenish brown — the colour mown grass goes under a flat light, not lawn green,
            // which would fight the home team's green arcs.
            GoalMapSurfaceStyle(
                near: Color(red: 0.43, green: 0.48, blue: 0.26),
                far: Color(red: 0.32, green: 0.37, blue: 0.20),
                tone: Color.black.opacity(0.08),
                line: Color.white.opacity(0.8),
                lineWidth: 1
            )
        case .court:
            GoalMapSurfaceStyle(
                near: Color(red: 0.87, green: 0.70, blue: 0.48),
                far: Color(red: 0.76, green: 0.58, blue: 0.38),
                tone: Color(red: 0.42, green: 0.26, blue: 0.10).opacity(0.2),
                line: Color.white.opacity(0.95),
                lineWidth: 1.4
            )
        }
    }
}

/// Paints the playing surface and its texture. Shared by the isometric map and the flat
/// picker in the placement sheet — `map` takes pitch space (metres) to canvas points, so
/// the same drawing serves any camera.
enum GoalMapSurfaceRenderer {
    static func draw(
        _ context: inout GraphicsContext,
        spec: PitchSpec,
        surface: GoalMapSurface,
        map: (Double, Double) -> CGPoint
    ) {
        let style = surface.style
        let length = spec.length
        let width = spec.width

        var area = Path()
        area.addLines([map(0, 0), map(length, 0), map(length, width), map(0, width)])
        area.closeSubpath()
        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [style.near, style.far]),
                startPoint: map(0, 0),
                endPoint: map(length, width)
            )
        )

        switch surface {
        case .grass:
            // Mowing bars across the pitch, every other one darker — what makes the flat
            // shape read as a pitch receding into the distance.
            let bars = spec.stripeCount
            for bar in stride(from: 0, to: bars, by: 2) {
                let x0 = length * Double(bar) / Double(bars)
                let x1 = length * Double(bar + 1) / Double(bars)
                var strip = Path()
                strip.addLines([map(x0, 0), map(x1, 0), map(x1, width), map(x0, width)])
                strip.closeSubpath()
                context.fill(strip, with: .color(style.tone))
            }

        case .court:
            // Boards run the length of the court: a seam between each, and every other
            // board a shade darker.
            let boards = 18
            for board in 0..<boards {
                let y0 = width * Double(board) / Double(boards)
                let y1 = width * Double(board + 1) / Double(boards)

                if board % 2 == 0 {
                    var plank = Path()
                    plank.addLines([map(0, y0), map(length, y0), map(length, y1), map(0, y1)])
                    plank.closeSubpath()
                    context.fill(plank, with: .color(Color.black.opacity(0.035)))
                }

                if board > 0 {
                    var seam = Path()
                    seam.move(to: map(0, y0))
                    seam.addLine(to: map(length, y0))
                    context.stroke(seam, with: .color(style.tone), lineWidth: 0.7)
                }
            }
        }
    }
}

// MARK: - Shots

/// One goal as the map draws it. Origin and goal-mouth are optional so the placement sheet
/// can preview a half-finished entry — the marker appears the moment the pitch is tapped,
/// the arc the moment the goal is.
struct GoalMapShot: Identifiable {
    let id: UUID
    let team: TeamSide
    var origin: PitchPoint?
    var goalMouth: GoalMouthPoint?
    var trajectory: ShotTrajectory
    var label: String?

    init(
        id: UUID = UUID(),
        team: TeamSide,
        origin: PitchPoint? = nil,
        goalMouth: GoalMouthPoint? = nil,
        trajectory: ShotTrajectory = .straight,
        label: String? = nil
    ) {
        self.id = id
        self.team = team
        self.origin = origin
        self.goalMouth = goalMouth
        self.trajectory = trajectory
        self.label = label
    }

    init(marker: GoalChartMarker, label: String? = nil) {
        self.init(
            id: marker.id,
            team: marker.team,
            origin: marker.placement?.origin,
            goalMouth: marker.placement?.goalMouth,
            trajectory: marker.placement?.trajectory ?? .straight,
            label: label
        )
    }
}

/// Everything needed to draw the map outside the live card — the Pressure Index card's copy
/// image and the WhatsApp share image carry the map this way.
struct GoalMapSnapshot {
    let spec: PitchSpec
    let shots: [GoalMapShot]
    let surface: GoalMapSurface
    let flipped: Bool
    let homeLabel: String
    let awayLabel: String

    /// Drawn `.plain`: these snapshots go onto a white image, where the app's dark stage
    /// reads as a black box.
    var pitchView: GoalMapPitchView {
        GoalMapPitchView(
            spec: spec,
            shots: shots,
            homeLabel: homeLabel,
            awayLabel: awayLabel,
            surface: surface,
            flipped: flipped,
            appearance: .plain
        )
    }
}

// MARK: - Pitch

struct GoalMapPitchView: View {
    let spec: PitchSpec
    let shots: [GoalMapShot]
    let homeLabel: String
    let awayLabel: String
    var surface: GoalMapSurface = .grass
    var flipped: Bool = false
    var appearance: Appearance = .stage

    /// `.stage` is the on-screen look: the pitch in a dark rounded box, with room above for
    /// the controls. `.plain` is for the exported image: no box, ink-coloured text and dark
    /// goal frames so it sits on white, and the empty sky above the pitch trimmed away.
    enum Appearance {
        case stage
        case plain
    }

    private enum GoalEnd {
        case left
        case right
    }

    private var isPlain: Bool { appearance == .plain }

    private var placedCount: Int {
        shots.filter { $0.origin != nil && $0.goalMouth != nil }.count
    }

    /// How much of the empty sky above the pitch can go, as a fraction of width. Only `.plain`
    /// trims: on screen the controls float up there. Everything scales with width, so the
    /// highest thing drawn (far touchline, goal frames, the peak of any arc) is found once at
    /// unit width and a small margin kept above it.
    private var topTrim: CGFloat {
        guard isPlain else { return 0 }

        let reference = IsoProjection(spec: spec, size: CGSize(width: 1, height: 1), flipped: flipped)
        let centre = spec.width / 2
        var highest = CGFloat.greatestFiniteMagnitude

        for x in [0.0, spec.length] {
            for y in [0.0, spec.width] {
                highest = min(highest, reference.point(x, y).y)
            }
            for y in [centre - spec.goalWidth / 2, centre + spec.goalWidth / 2] {
                highest = min(highest, reference.point(x, y, z: spec.goalHeight).y)
            }
        }
        for shot in shots {
            let flight = Flight(shot: shot, spec: spec, projection: reference)
            if let top = flight.arc.map(\.y).min() {
                highest = min(highest, top)
            }
        }

        return min(max(highest - 0.03, 0), IsoProjection.headroom)
    }

    var body: some View {
        let trim = topTrim

        Canvas { context, size in
            let projection = IsoProjection(spec: spec, size: size, flipped: flipped, topTrim: trim)

            GoalMapSurfaceRenderer.draw(&context, spec: spec, surface: surface) { x, y in
                projection.point(x, y)
            }
            drawMarkings(&context, projection)
            drawGoal(&context, projection, end: .left)
            drawGoal(&context, projection, end: .right)

            let flights = shots.map { Flight(shot: $0, spec: spec, projection: projection) }
            for flight in flights { drawShadow(&context, flight) }
            for flight in flights { drawArc(&context, flight) }
            for flight in flights { drawMarkers(&context, flight) }
            drawLabels(&context, flights, canvasSize: size)
            drawTeamLabels(&context, projection)
        }
        .aspectRatio(1 / IsoProjection.aspectRatio(for: spec, topTrim: trim), contentMode: .fit)
        .background {
            if !isPlain {
                LinearGradient(
                    colors: [GoalMapPalette.stageTop, GoalMapPalette.stageBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isPlain ? 0 : 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goal map")
        .accessibilityValue("\(placedCount) goals placed")
    }

    // MARK: Per-shot layout

    /// A shot with everything already projected to canvas points, so each draw pass below
    /// is just strokes.
    private struct Flight {
        let shot: GoalMapShot
        let tint: Color
        let origin: CGPoint?
        let end: CGPoint?
        let arc: [CGPoint]
        let shadow: [CGPoint]

        init(shot: GoalMapShot, spec: PitchSpec, projection: IsoProjection) {
            self.shot = shot
            tint = GoalMapPalette.tint(for: shot.team)

            origin = shot.origin.map { projection.point(spec.groundPoint(of: $0, team: shot.team)) }
            end = shot.goalMouth.map { projection.point(spec.goalMouthPoint($0, team: shot.team)) }

            if let origin = shot.origin, let goalMouth = shot.goalMouth {
                let flight = ShotFlight(
                    team: shot.team,
                    placement: ShotPlacement(origin: origin, goalMouth: goalMouth, trajectory: shot.trajectory),
                    spec: spec
                )
                let samples = flight.samples()
                arc = samples.map { projection.point($0) }
                shadow = samples.map { projection.point($0.x, $0.y) }
            } else {
                arc = []
                shadow = []
            }
        }
    }

    // MARK: Pitch drawing

    private func drawMarkings(_ context: inout GraphicsContext, _ p: IsoProjection) {
        let markings = spec.markings
        let style = surface.style

        for line in markings.lines {
            var path = Path()
            for (index, point) in line.enumerated() {
                let screen = p.point(point)
                if index == 0 {
                    path.move(to: screen)
                } else {
                    path.addLine(to: screen)
                }
            }
            context.stroke(
                path,
                with: .color(style.line),
                style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }

        for spot in markings.spots {
            let centre = p.point(spot)
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - 1.7, y: centre.y - 1.1, width: 3.4, height: 2.2)),
                with: .color(style.line)
            )
        }
    }

    /// A wireframe goal: the net as a faint box running back off the pitch, the frame in
    /// bright white on the goal line.
    private func drawGoal(_ context: inout GraphicsContext, _ p: IsoProjection, end: GoalEnd) {
        let lineX: Double = end == .left ? 0 : spec.length
        let backX: Double = end == .left ? -spec.goalDepth : spec.length + spec.goalDepth
        let centre = spec.width / 2
        let nearY = centre - spec.goalWidth / 2
        let farY = centre + spec.goalWidth / 2
        let height = spec.goalHeight
        // The net slopes down toward the back, like a real goal's.
        let backHeight = height * 0.8

        let frontNearBase = p.point(lineX, nearY, z: 0)
        let frontNearTop = p.point(lineX, nearY, z: height)
        let frontFarTop = p.point(lineX, farY, z: height)
        let frontFarBase = p.point(lineX, farY, z: 0)
        let backNearBase = p.point(backX, nearY, z: 0)
        let backNearTop = p.point(backX, nearY, z: backHeight)
        let backFarTop = p.point(backX, farY, z: backHeight)
        let backFarBase = p.point(backX, farY, z: 0)

        let panels: [[CGPoint]] = [
            [backNearBase, backNearTop, backFarTop, backFarBase],
            [frontNearTop, frontFarTop, backFarTop, backNearTop],
            [frontNearBase, frontNearTop, backNearTop, backNearBase],
            [frontFarBase, frontFarTop, backFarTop, backFarBase]
        ]
        for panel in panels {
            var path = Path()
            path.addLines(panel)
            path.closeSubpath()
            context.fill(path, with: .color(isPlain ? Color.black.opacity(0.07) : Color.white.opacity(0.1)))
            context.stroke(
                path,
                with: .color(isPlain ? Color.black.opacity(0.3) : Color.white.opacity(0.4)),
                style: StrokeStyle(lineWidth: 0.6, lineJoin: .round)
            )
        }

        var frame = Path()
        frame.move(to: frontNearBase)
        frame.addLine(to: frontNearTop)
        frame.addLine(to: frontFarTop)
        frame.addLine(to: frontFarBase)
        // White posts on the dark stage, dark ones on the white page. Either way the other
        // colour edges them, so they stay readable where they cross the court.
        context.stroke(
            frame,
            with: .color(isPlain ? Color.white.opacity(0.75) : Color.black.opacity(0.35)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            frame,
            with: .color(isPlain ? Color(white: 0.16) : Color.white.opacity(0.98)),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )
    }

    // MARK: Shot drawing

    private func drawShadow(_ context: inout GraphicsContext, _ flight: Flight) {
        guard flight.shadow.count > 1 else { return }
        var path = Path()
        path.addLines(flight.shadow)
        context.stroke(
            path,
            with: .color(.black.opacity(0.32)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3])
        )
    }

    private func drawArc(_ context: inout GraphicsContext, _ flight: Flight) {
        guard let first = flight.arc.first, let last = flight.arc.last, flight.arc.count > 1 else { return }

        var path = Path()
        path.addLines(flight.arc)

        // Dark casing first: neon on a light court needs an edge to stand off from the boards.
        context.stroke(
            path,
            with: .color(.black.opacity(0.45)),
            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        )

        // The glow is the neon, and it only reads on a dark stage — on white it just smears.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.5))
            layer.stroke(
                path,
                with: .color(flight.tint.opacity(isPlain ? 0.3 : 0.7)),
                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
            )
        }

        // Faint at the boot, full strength at the net — reads as the ball travelling.
        let shading: GraphicsContext.Shading = hypot(last.x - first.x, last.y - first.y) > 1
            ? .linearGradient(
                Gradient(colors: [flight.tint.opacity(0.45), flight.tint]),
                startPoint: first,
                endPoint: last
            )
            : .color(flight.tint)
        context.stroke(
            path,
            with: shading,
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawMarkers(_ context: inout GraphicsContext, _ flight: Flight) {
        if let end = flight.end {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.5))
                layer.fill(Path(ellipseIn: dot(end, radius: 4.5)), with: .color(flight.tint.opacity(0.9)))
            }
            context.stroke(Path(ellipseIn: dot(end, radius: 3)), with: .color(.black.opacity(0.45)), lineWidth: 1)
            context.fill(Path(ellipseIn: dot(end, radius: 2.6)), with: .color(flight.tint))
            context.fill(Path(ellipseIn: dot(end, radius: 1.1)), with: .color(.white))
        }

        if let origin = flight.origin {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(Path(ellipseIn: dot(origin, radius: 5.5)), with: .color(flight.tint.opacity(0.85)))
            }
            context.stroke(Path(ellipseIn: dot(origin, radius: 5.6)), with: .color(.black.opacity(0.45)), lineWidth: 1.2)
            context.fill(Path(ellipseIn: dot(origin, radius: 3.4)), with: .color(.white))
            context.stroke(
                Path(ellipseIn: dot(origin, radius: 4.8)),
                with: .color(flight.tint),
                lineWidth: 1.4
            )
        }
    }

    private func dot(_ centre: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }

    /// Pills sit by the boot, nudged up or down until they clear every pill already placed —
    /// when two goals came from the same spot, one label steps aside instead of hiding the other.
    private func drawLabels(_ context: inout GraphicsContext, _ flights: [Flight], canvasSize: CGSize) {
        var placed: [CGRect] = []
        let offsets: [CGFloat] = [-13, 13, -25, 25, -37, 37]

        for flight in flights {
            guard let label = flight.shot.label, let origin = flight.origin else { continue }

            let text = context.resolve(
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
            let textSize = text.measure(in: CGSize(width: 200, height: 30))
            let pill = CGSize(width: textSize.width + 12, height: textSize.height + 5)
            let minX: CGFloat = 3
            let maxX = max(canvasSize.width - pill.width - 3, minX)
            let originX = min(max(origin.x - pill.width / 2, minX), maxX)

            var chosen: CGRect?
            for offset in offsets {
                let candidate = CGRect(
                    x: originX,
                    y: origin.y + offset - pill.height / 2,
                    width: pill.width,
                    height: pill.height
                )
                let insideCanvas = candidate.minY >= 2 && candidate.maxY <= canvasSize.height - 2
                if insideCanvas, !placed.contains(where: { $0.insetBy(dx: -2, dy: -1).intersects(candidate) }) {
                    chosen = candidate
                    break
                }
            }
            // Nothing clear? Still draw it at the first spot rather than silently dropping a name.
            let rect = chosen ?? CGRect(
                x: originX,
                y: origin.y + offsets[0] - pill.height / 2,
                width: pill.width,
                height: pill.height
            )
            placed.append(rect)

            let capsule = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            context.fill(capsule, with: .color(Color.black.opacity(0.78)))
            context.stroke(capsule, with: .color(flight.tint.opacity(0.9)), lineWidth: 0.8)
            context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    /// Under each end, the team that defends it, with an arrow for the way it attacks. Home
    /// defend the left end and attack right unless the view is flipped.
    private func drawTeamLabels(_ context: inout GraphicsContext, _ p: IsoProjection) {
        let left: (text: String, team: TeamSide) = flipped
            ? ("\(awayLabel) \u{25B6}", .away)
            : ("\(homeLabel) \u{25B6}", .home)
        let right: (text: String, team: TeamSide) = flipped
            ? ("\u{25C0} \(homeLabel)", .home)
            : ("\u{25C0} \(awayLabel)", .away)

        func labelColour(_ team: TeamSide) -> Color {
            isPlain ? GoalMapPalette.ink(for: team) : GoalMapPalette.tint(for: team)
        }

        let leftText = context.resolve(
            Text(left.text)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(labelColour(left.team))
        )
        context.draw(leftText, at: CGPoint(x: p.nearLeft.x, y: p.nearLeft.y + 10), anchor: .leading)

        let rightText = context.resolve(
            Text(right.text)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(labelColour(right.team))
        )
        context.draw(rightText, at: CGPoint(x: p.nearRight.x, y: p.nearRight.y + 10), anchor: .trailing)
    }
}

// MARK: - Labels and text

enum GoalMapLabels {
    /// "Alex Smith" -> "Alex S." — first names alone collide in a squad, full names don't fit.
    static func shortName(_ full: String) -> String {
        let words = full.split(separator: " ").filter { !$0.isEmpty }
        guard words.count >= 2, let initial = words.last?.first else { return full }
        return "\(words[0]) \(initial)."
    }

    static func scorerName(for marker: GoalChartMarker, playerName: (UUID) -> String?) -> String? {
        marker.creditedPlayerID.flatMap(playerName)
    }

    /// The credited scorer, or the minute when nobody is credited (every away goal, and any
    /// home goal not yet credited) — so a pill is never blank.
    static func pillLabel(for marker: GoalChartMarker, playerName: (UUID) -> String?) -> String {
        scorerName(for: marker, playerName: playerName).map(shortName) ?? marker.minuteLabel
    }

    /// One line per placed goal ("12' (1-0) Alex — top left, arc"), for the Pressure Index
    /// card's copied text. Empty when nothing is placed.
    static func copyText(
        markers: [GoalChartMarker],
        homeName: String,
        awayName: String,
        playerName: (UUID) -> String?
    ) -> String {
        markers.compactMap { marker -> String? in
            guard let placement = marker.placement else { return nil }
            let who = scorerName(for: marker, playerName: playerName)
                ?? (marker.team == .home ? homeName : awayName)
            return "\(marker.minuteLabel) (\(marker.scoreLabel)) \(who) — \(placement.goalMouth.zoneLabel), \(placement.trajectory.label.lowercased())"
        }
        .joined(separator: "\n")
    }
}

extension GoalMouthPoint {
    /// Which ninth of the goal, as the shooter saw it — "top left", "low centre", "centre".
    var zoneLabel: String {
        let horizontal = x < 1.0 / 3 ? "left" : (x > 2.0 / 3 ? "right" : "centre")
        let vertical = y < 1.0 / 3 ? "low" : (y > 2.0 / 3 ? "top" : "mid")

        switch (vertical, horizontal) {
        case ("mid", "centre"): return "centre"
        case ("mid", _): return "mid \(horizontal)"
        default: return "\(vertical) \(horizontal)"
        }
    }
}

// MARK: - Pressure Index section

/// The Goal Map as it sits inside the Pressure Index card: the pitch with its controls
/// floating over the empty sky above the far touchline, the way the basketball reference
/// puts Replay and Half Court on the court.
struct GoalMapSection: View {
    let markers: [GoalChartMarker]
    let spec: PitchSpec
    let surface: GoalMapSurface
    let flipped: Bool
    let homeLabel: String
    let awayLabel: String
    let playerName: (UUID) -> String?
    @Binding var showsNames: Bool
    let onFlip: () -> Void
    let onSurfaceChange: (GoalMapSurface) -> Void

    private var placedMarkers: [GoalChartMarker] {
        markers.filter { $0.placement != nil }
    }

    private var unplacedCount: Int {
        markers.count - placedMarkers.count
    }

    /// The Names control only earns its place once there is a name to show.
    private var hasNames: Bool {
        placedMarkers.contains { GoalMapLabels.scorerName(for: $0, playerName: playerName) != nil }
    }

    private var statusLine: String {
        placedMarkers.isEmpty ? "None placed yet" : "\(placedMarkers.count) of \(markers.count) placed"
    }

    private var hintLine: String? {
        if placedMarkers.isEmpty {
            return "Tap a goal's ⚽ on the chart above to place it."
        }
        switch unplacedCount {
        case 0: return nil
        case 1: return "1 goal isn't placed — tap its ⚽ on the chart above."
        default: return "\(unplacedCount) goals aren't placed — tap their ⚽ on the chart above."
        }
    }

    private var shots: [GoalMapShot] {
        placedMarkers.map { marker in
            GoalMapShot(
                marker: marker,
                label: showsNames ? GoalMapLabels.pillLabel(for: marker, playerName: playerName) : nil
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Goal Map")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .top) {
                GoalMapPitchView(
                    spec: spec,
                    shots: shots,
                    homeLabel: homeLabel,
                    awayLabel: awayLabel,
                    surface: surface,
                    flipped: flipped
                )

                HStack(alignment: .top, spacing: 6) {
                    StageChip(
                        title: "FLIP",
                        systemImage: "arrow.triangle.2.circlepath",
                        isOn: flipped,
                        accessibilityLabel: "Flip the map to the other touchline",
                        action: onFlip
                    )

                    if hasNames {
                        StageChip(
                            title: "NAMES",
                            systemImage: "person.fill",
                            isOn: showsNames,
                            accessibilityLabel: "Show scorers' names",
                            action: { showsNames.toggle() }
                        )
                    }

                    Spacer(minLength: 6)

                    StageChip(
                        title: surface.label.uppercased(),
                        systemImage: surface == .grass ? "leaf.fill" : "sportscourt.fill",
                        isOn: false,
                        accessibilityLabel: "Surface: \(surface.label). Tap to change.",
                        action: { onSurfaceChange(surface == .grass ? .court : .grass) }
                    )
                }
                .padding(8)
            }

            if let hintLine {
                Text(hintLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A dark pill that sits on the stage, in the style of the reference's Replay / Half Court.
private struct StageChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.92))
                .padding(.horizontal, 9)
                .frame(minHeight: 28)
                .background(Capsule().fill(isOn ? Color.white.opacity(0.92) : Color.black.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
