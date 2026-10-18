import SwiftUI

// Geometry behind the Summary tab's Goal Map: real-world pitch proportions, the isometric
// camera that draws them, and the flight a shot takes through the air. Nothing here draws —
// `GoalMapView.swift` and `GoalPlacementSheet.swift` do the drawing.
//
// Two coordinate systems meet in this file:
//
// - **Attacking frame** — what `ShotPlacement` stores (`PitchPoint`, `GoalMouthPoint`). Always
//   "the scorer attacking the goal at x = 1", so both teams' goals mean the same thing.
// - **Pitch space** — metres, x along the length from the home goal line (0) to the away
//   goal line (`length`), y across from the near touchline (0) to the far one (`width`).
//   Home attack toward +x. Away goals are rotated 180° into it (`PitchSpec.groundPoint`).

struct Point3 {
    var x: Double
    var y: Double
    var z: Double
}

// MARK: - Pitch

struct PitchSpec {
    enum Kind {
        case outdoor
        case futsal
    }

    let kind: Kind
    let length: Double
    let width: Double
    let goalWidth: Double
    let goalHeight: Double
    /// How far the net runs back behind the goal line — drawing only.
    let goalDepth: Double
    let centreCircleRadius: Double
    /// How many bars the surface is striped into along its length. Each bar is one stripe of
    /// mown grass, or one run of floorboards on the court.
    let stripeCount: Int

    /// Standard proportions rather than anything measured: U13 pitches vary ground to
    /// ground, and a normalised placement doesn't care.
    ///
    /// The futsal courts played on are shorter than a regulation 40 m one, so it is drawn a bar
    /// shorter at each end: 8 bars of 4 m (32 m) instead of 10.
    static func make(for format: GameFormat) -> PitchSpec {
        switch format {
        case .outdoor:
            PitchSpec(
                kind: .outdoor, length: 105, width: 68,
                goalWidth: 7.32, goalHeight: 2.44, goalDepth: 2.0,
                centreCircleRadius: 9.15, stripeCount: 14
            )
        case .futsal:
            PitchSpec(
                kind: .futsal, length: 32, width: 20,
                goalWidth: 3, goalHeight: 2, goalDepth: 1.0,
                centreCircleRadius: 3, stripeCount: 8
            )
        }
    }

    // MARK: Attacking frame -> pitch space

    /// Where on the pitch an attacking-frame point lands. Home attack toward +x; away are
    /// turned 180° so the shooter's left stays the shooter's left from their own end.
    func groundPoint(of point: PitchPoint, team: TeamSide) -> CGPoint {
        switch team {
        case .home: CGPoint(x: length * point.x, y: width * point.y)
        case .away: CGPoint(x: length * (1 - point.x), y: width * (1 - point.y))
        }
    }

    /// Where in the goal mouth the ball crossed the line, in pitch space with height.
    func goalMouthPoint(_ point: GoalMouthPoint, team: TeamSide) -> Point3 {
        // Facing the goal, the left post is the +y side in the attacking frame.
        let attackY = 0.5 + (0.5 - point.x) * goalWidth / width
        let ground = groundPoint(of: PitchPoint(x: 1, y: attackY), team: team)
        return Point3(x: Double(ground.x), y: Double(ground.y), z: point.y * goalHeight)
    }

    // MARK: Markings

    struct Markings {
        var lines: [[CGPoint]]
        var spots: [CGPoint]
    }

    /// Every painted line as a polyline in pitch space, mirrored for both ends.
    var markings: Markings {
        let cx = length / 2
        let cy = width / 2

        var lines: [[CGPoint]] = [
            [pt(0, 0), pt(length, 0), pt(length, width), pt(0, width), pt(0, 0)],
            [pt(cx, 0), pt(cx, width)],
            Self.arc(centre: pt(cx, cy), radius: centreCircleRadius, from: 0, to: 360)
        ]
        var spots = [pt(cx, cy)]

        // Everything below is drawn for the x = 0 end, then mirrored onto the other.
        var endLines: [[CGPoint]] = []
        var endSpots: [CGPoint] = []

        switch kind {
        case .outdoor:
            let boxHalf = 20.16
            let sixHalf = 9.16
            let penaltyMark = 11.0
            let arcRadius = 9.15
            let boxDepth = 16.5
            let arcHalfAngle = acos((boxDepth - penaltyMark) / arcRadius) * 180 / .pi

            endLines = [
                [pt(0, cy - boxHalf), pt(boxDepth, cy - boxHalf), pt(boxDepth, cy + boxHalf), pt(0, cy + boxHalf)],
                [pt(0, cy - sixHalf), pt(5.5, cy - sixHalf), pt(5.5, cy + sixHalf), pt(0, cy + sixHalf)],
                Self.arc(centre: pt(penaltyMark, cy), radius: arcRadius, from: -arcHalfAngle, to: arcHalfAngle)
            ]
            endSpots = [pt(penaltyMark, cy)]

        case .futsal:
            let post = goalWidth / 2
            let radius = 6.0
            endLines = [
                Self.arc(centre: pt(0, cy + post), radius: radius, from: 0, to: 90),
                Self.arc(centre: pt(0, cy - post), radius: radius, from: -90, to: 0),
                [pt(radius, cy - post), pt(radius, cy + post)]
            ]
            endSpots = [pt(6, cy), pt(10, cy)]
        }

        for line in endLines {
            lines.append(line)
            lines.append(line.map { CGPoint(x: length - $0.x, y: $0.y) })
        }
        for spot in endSpots {
            spots.append(spot)
            spots.append(CGPoint(x: length - spot.x, y: spot.y))
        }

        return Markings(lines: lines, spots: spots)
    }

    private func pt(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    private static func arc(
        centre: CGPoint,
        radius: Double,
        from startDegrees: Double,
        to endDegrees: Double,
        steps: Int = 48
    ) -> [CGPoint] {
        (0...steps).map { step in
            let fraction = Double(step) / Double(steps)
            let angle = (startDegrees + (endDegrees - startDegrees) * fraction) * .pi / 180
            return CGPoint(
                x: Double(centre.x) + radius * cos(angle),
                y: Double(centre.y) + radius * sin(angle)
            )
        }
    }
}

// MARK: - Isometric camera

/// A fixed camera looking down the pitch from beside one touchline: the far touchline is
/// shorter and squashed (real perspective, so lines stay straight), and heights lift a point
/// up the screen with a deliberate vertical exaggeration — without it a 2.4 m goal is a few
/// pixels tall and every arc looks flat.
///
/// Sized entirely from the canvas width, so `aspectRatio(for:)` can hand layout a height
/// before any drawing happens.
///
/// `flipped` moves the camera to the opposite touchline: the pitch turns half a turn, so home
/// attack right-to-left and the near and far touchlines swap. It is a rotation, not a mirror
/// image, which is what keeps every shooter's left and right true.
struct IsoProjection {
    /// How hard the far touchline shrinks relative to the near one (0.25 -> far is 80%).
    private static let perspective: CGFloat = 0.25
    /// Screen depth of the pitch relative to its true depth — low is flatter.
    private static let tilt: CGFloat = 0.60
    static let verticalExaggeration: CGFloat = 1.7
    /// Room above the far touchline for goal frames and high balls, as a fraction of width.
    static let headroom: CGFloat = 0.17
    /// Room under the near touchline for the team labels.
    private static let footer: CGFloat = 0.07
    private static let sideMargin: CGFloat = 0.03

    let spec: PitchSpec
    let size: CGSize
    let flipped: Bool

    private let nearWidth: CGFloat
    private let centreX: CGFloat
    private let nearY: CGFloat
    private let groundDepth: CGFloat
    private let heightPerMetre: CGFloat

    /// Height divided by width of the canvas that fits this pitch. `topTrim` (a fraction of
    /// width, at most `headroom`) is empty sky cut off the top — the exported image uses it so
    /// a match with no high balls doesn't carry a blank band above the pitch.
    static func aspectRatio(for spec: PitchSpec, topTrim: CGFloat = 0) -> CGFloat {
        let nearWidth = 1 - 2 * sideMargin
        let ground = tilt * CGFloat(spec.width / spec.length) * nearWidth
        return headroom - topTrim + ground + footer
    }

    init(spec: PitchSpec, size: CGSize, flipped: Bool = false, topTrim: CGFloat = 0) {
        self.spec = spec
        self.size = size
        self.flipped = flipped
        nearWidth = size.width * (1 - 2 * Self.sideMargin)
        centreX = size.width / 2
        groundDepth = Self.tilt * CGFloat(spec.width / spec.length) * nearWidth
        nearY = size.width * (Self.headroom - topTrim) + groundDepth
        heightPerMetre = nearWidth / CGFloat(spec.length) * Self.verticalExaggeration
    }

    /// Pitch space (metres, plus height) to canvas points.
    func point(_ x: Double, _ y: Double, z: Double = 0) -> CGPoint {
        screenPoint(
            flipped ? spec.length - x : x,
            flipped ? spec.width - y : y,
            z: z
        )
    }

    /// The camera itself, with no flip applied: near touchline at the bottom, x running left
    /// to right.
    private func screenPoint(_ x: Double, _ y: Double, z: Double = 0) -> CGPoint {
        let across = CGFloat(x / spec.length)
        let depth = CGFloat(y / spec.width)
        let scale = 1 / (1 + Self.perspective * depth)
        let farScale = 1 / (1 + Self.perspective)
        let rise = (1 - scale) / (1 - farScale)

        return CGPoint(
            x: centreX + (across - 0.5) * nearWidth * scale,
            y: nearY - groundDepth * rise - CGFloat(z) * heightPerMetre * scale
        )
    }

    func point(_ ground: CGPoint, z: Double = 0) -> CGPoint {
        point(Double(ground.x), Double(ground.y), z: z)
    }

    func point(_ p: Point3) -> CGPoint {
        point(p.x, p.y, z: p.z)
    }

    /// The bottom corners of the pitch *as drawn* — whatever end of the pitch they are.
    var nearLeft: CGPoint { screenPoint(0, 0) }
    var nearRight: CGPoint { screenPoint(spec.length, 0) }
}

// MARK: - Shot flight

/// The ball's path from boot to net. Straight is a flat line between the two points; arc and
/// high add a parabola on top, scaled with how far the shot travelled so a 30-metre lob
/// peaks higher than a 6-metre one.
struct ShotFlight {
    let start: Point3
    let end: Point3
    let peak: Double

    init(team: TeamSide, placement: ShotPlacement, spec: PitchSpec) {
        let ground = spec.groundPoint(of: placement.origin, team: team)
        // The ball starts a ball-radius off the grass, not buried in it.
        start = Point3(x: Double(ground.x), y: Double(ground.y), z: 0.12)
        end = spec.goalMouthPoint(placement.goalMouth, team: team)

        let distance = hypot(end.x - start.x, end.y - start.y)
        // Peaks are written for a full-size goal; shrink them for futsal's smaller one.
        let scale = spec.goalHeight / 2.44

        switch placement.trajectory {
        case .straight:
            peak = 0
        case .arc:
            peak = min(max(distance * 0.12, 1.2), 5.5) * scale
        case .high:
            peak = min(max(distance * 0.28, 3.0), 11) * scale
        }
    }

    func point(at t: Double) -> Point3 {
        Point3(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t,
            z: start.z * (1 - t) + end.z * t + 4 * peak * t * (1 - t)
        )
    }

    func samples(count: Int = 40) -> [Point3] {
        (0...count).map { point(at: Double($0) / Double(count)) }
    }
}
