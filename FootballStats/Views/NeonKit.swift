import SwiftUI

/// Shared drawing kit for the neon icon set: palette, bloom, ball, goal, and the figure
/// anatomy. Limbs are tapered outlines rather than plain strokes, which is what makes the
/// keeper and the wall read as bodies instead of stick figures at icon size.

enum NeonIconPalette {
    static let green = Color(red: 0.24, green: 0.96, blue: 0.40)
    static let red = Color(red: 1.00, green: 0.29, blue: 0.30)
    static let orange = Color(red: 1.00, green: 0.56, blue: 0.14)
    static let chrome = Color(red: 0.94, green: 0.97, blue: 1.00)
    static let grey = Color(white: 0.80)
}

extension View {
    /// Two-pass bloom: a tight core glow plus a wider halo, which is what makes a thin
    /// stroke read as neon rather than as a coloured line.
    func neonBloom(_ color: Color, radius: CGFloat = 2.5) -> some View {
        self
            .shadow(color: color.opacity(0.85), radius: radius)
            .shadow(color: color.opacity(0.40), radius: radius * 2.4)
    }
}

// MARK: - Anatomy

enum NeonAnatomy {
    /// A limb as a closed tapered outline with rounded caps, so it has real thickness.
    static func limb(
        from start: CGPoint,
        to end: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat
    ) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.0001, sqrt(dx * dx + dy * dy))
        let ux = dx / length
        let uy = dy / length
        let nx = -uy
        let ny = ux
        let halfStart = startWidth / 2
        let halfEnd = endWidth / 2

        let a = CGPoint(x: start.x + nx * halfStart, y: start.y + ny * halfStart)
        let b = CGPoint(x: end.x + nx * halfEnd, y: end.y + ny * halfEnd)
        let c = CGPoint(x: end.x - nx * halfEnd, y: end.y - ny * halfEnd)
        let d = CGPoint(x: start.x - nx * halfStart, y: start.y - ny * halfStart)

        path.move(to: a)
        path.addLine(to: b)
        path.addQuadCurve(
            to: c,
            control: CGPoint(x: end.x + ux * halfEnd * 1.35, y: end.y + uy * halfEnd * 1.35)
        )
        path.addLine(to: d)
        path.addQuadCurve(
            to: a,
            control: CGPoint(x: start.x - ux * halfStart * 1.35, y: start.y - uy * halfStart * 1.35)
        )
        path.closeSubpath()
        return path
    }

    /// Torso as a tapered barrel from shoulders down to hips.
    static func torso(
        shoulderLeft: CGPoint,
        shoulderRight: CGPoint,
        hipLeft: CGPoint,
        hipRight: CGPoint
    ) -> Path {
        var path = Path()
        path.move(to: shoulderLeft)
        path.addQuadCurve(
            to: shoulderRight,
            control: CGPoint(
                x: (shoulderLeft.x + shoulderRight.x) / 2,
                y: shoulderLeft.y - abs(shoulderRight.x - shoulderLeft.x) * 0.16
            )
        )
        path.addQuadCurve(
            to: hipRight,
            control: CGPoint(x: shoulderRight.x + (hipRight.x - shoulderRight.x) * 0.2, y: (shoulderRight.y + hipRight.y) / 2)
        )
        path.addLine(to: hipLeft)
        path.addQuadCurve(
            to: shoulderLeft,
            control: CGPoint(x: shoulderLeft.x + (hipLeft.x - shoulderLeft.x) * 0.2, y: (shoulderLeft.y + hipLeft.y) / 2)
        )
        path.closeSubpath()
        return path
    }
}

/// Keeper set to save: arms out and low, feet planted wide.
///
/// Drawn as one continuous silhouette outline rather than stacked limb shapes — overlapping
/// limbs leave internal seams where they cross, which is what made the earlier figures look
/// scrappy at icon size.
struct NeonKeeperFigure: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.37,
                y: rect.minY,
                width: rect.width * 0.26,
                height: rect.height * 0.20
            )
        )

        path.move(to: point(0.50, 0.62))
        path.addLine(to: point(0.42, 0.97))      // inside of left leg
        path.addLine(to: point(0.24, 0.97))      // left foot
        path.addLine(to: point(0.31, 0.57))      // outside of left leg up to the hip
        path.addLine(to: point(0.33, 0.36))      // left flank up to the armpit
        path.addLine(to: point(0.20, 0.52))      // inside of the outstretched left arm
        path.addLine(to: point(0.05, 0.58))      // left hand
        path.addLine(to: point(0.17, 0.34))      // back up the outside of the arm
        path.addLine(to: point(0.30, 0.22))      // left shoulder
        path.addLine(to: point(0.70, 0.22))      // across the shoulders
        path.addLine(to: point(0.83, 0.34))
        path.addLine(to: point(0.95, 0.58))      // right hand
        path.addLine(to: point(0.80, 0.52))
        path.addLine(to: point(0.67, 0.36))      // right armpit
        path.addLine(to: point(0.69, 0.57))      // right hip
        path.addLine(to: point(0.76, 0.97))      // right foot
        path.addLine(to: point(0.58, 0.97))
        path.closeSubpath()

        return path
    }
}

/// Keeper at full stretch, diving to the right: head leading, both arms reaching, legs
/// trailing with the top leg kicked up.
struct NeonDivingKeeperFigure: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        let unit = rect.height

        let hip = point(0.18, 0.74)
        let shoulder = point(0.48, 0.50)

        // Torso as one thick tapered limb along the dive axis — a separate torso quad
        // crossed the limbs and turned the pose into a tangle at icon size.
        path.addPath(NeonAnatomy.limb(from: shoulder, to: hip, startWidth: unit * 0.28, endWidth: unit * 0.24))

        // Head sits forward of the shoulder and is bracketed by the two arms, so it stays
        // legible instead of merging into the torso.
        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.52,
                y: rect.minY + rect.height * 0.27,
                width: rect.width * 0.16,
                height: rect.height * 0.26
            )
        )

        // Arms noticeably thinner than the legs, one passing above the head, one below.
        path.addPath(NeonAnatomy.limb(from: shoulder, to: point(0.66, 0.28), startWidth: unit * 0.13, endWidth: unit * 0.10))
        path.addPath(NeonAnatomy.limb(from: point(0.66, 0.28), to: point(0.87, 0.15), startWidth: unit * 0.10, endWidth: unit * 0.08))
        path.addPath(NeonAnatomy.limb(from: shoulder, to: point(0.68, 0.54), startWidth: unit * 0.12, endWidth: unit * 0.10))
        path.addPath(NeonAnatomy.limb(from: point(0.68, 0.54), to: point(0.89, 0.45), startWidth: unit * 0.10, endWidth: unit * 0.08))

        // Trailing legs: back leg kicked up, front leg swept low.
        path.addPath(NeonAnatomy.limb(from: hip, to: point(0.08, 0.58), startWidth: unit * 0.23, endWidth: unit * 0.17))
        path.addPath(NeonAnatomy.limb(from: point(0.08, 0.58), to: point(0.01, 0.43), startWidth: unit * 0.17, endWidth: unit * 0.12))
        path.addPath(NeonAnatomy.limb(from: hip, to: point(0.10, 0.89), startWidth: unit * 0.22, endWidth: unit * 0.16))
        path.addPath(NeonAnatomy.limb(from: point(0.10, 0.89), to: point(0.01, 0.98), startWidth: unit * 0.16, endWidth: unit * 0.11))

        return path
    }
}

/// Wall player: upright, arms hanging at the sides. One continuous silhouette, same
/// reasoning as `NeonKeeperFigure`.
struct NeonWallFigure: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.35,
                y: rect.minY,
                width: rect.width * 0.30,
                height: rect.height * 0.19
            )
        )

        path.move(to: point(0.50, 0.63))
        path.addLine(to: point(0.43, 0.97))      // inside of left leg
        path.addLine(to: point(0.27, 0.97))      // left foot
        path.addLine(to: point(0.30, 0.60))      // outside of left leg
        path.addLine(to: point(0.33, 0.40))      // left armpit
        path.addLine(to: point(0.28, 0.56))      // inside of hanging left arm
        path.addLine(to: point(0.16, 0.57))      // left hand
        path.addLine(to: point(0.18, 0.30))      // outside of left arm
        path.addLine(to: point(0.30, 0.22))      // left shoulder
        path.addLine(to: point(0.70, 0.22))      // across the shoulders
        path.addLine(to: point(0.82, 0.30))
        path.addLine(to: point(0.84, 0.57))      // right hand
        path.addLine(to: point(0.72, 0.56))
        path.addLine(to: point(0.67, 0.40))      // right armpit
        path.addLine(to: point(0.70, 0.60))      // right hip
        path.addLine(to: point(0.73, 0.97))      // right foot
        path.addLine(to: point(0.57, 0.97))
        path.closeSubpath()

        return path
    }
}

/// Renders any of the figure shapes with the standard neon treatment.
struct NeonFigure<S: Shape>: View {
    let shape: S
    var color: Color
    var lineWidth: CGFloat = 1.0
    var bloom: CGFloat = 2.0

    var body: some View {
        ZStack {
            shape.fill(Color.black.opacity(0.45))
            shape.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
        .neonBloom(color, radius: bloom)
    }
}

// MARK: - Ball

/// Glowing football: radial body, dark panels so it reads as a ball rather than a dot.
struct NeonBall: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color, color.opacity(0.62), Color.black.opacity(0.88)],
                        center: .topLeading,
                        startRadius: 0.5,
                        endRadius: size
                    )
                )

            BallPanels()
                .fill(Color.black.opacity(0.72))

            Circle()
                .stroke(color.opacity(0.95), lineWidth: max(0.7, size * 0.055))
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.85), radius: size * 0.30)
        .shadow(color: color.opacity(0.45), radius: size * 0.75)
    }
}

private struct BallPanels: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        var pentagon = Path()
        for index in 0..<5 {
            let angle = Double(index) / 5 * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: centre.x + cos(angle) * radius * 0.33,
                y: centre.y + sin(angle) * radius * 0.33
            )
            if index == 0 {
                pentagon.move(to: point)
            } else {
                pentagon.addLine(to: point)
            }
        }
        pentagon.closeSubpath()
        path.addPath(pentagon)

        for index in 0..<5 {
            let angle = Double(index) / 5 * 2 * .pi - .pi / 2 + .pi / 5
            let cx = centre.x + cos(angle) * radius * 0.80
            let cy = centre.y + sin(angle) * radius * 0.80
            path.addEllipse(
                in: CGRect(x: cx - radius * 0.16, y: cy - radius * 0.16,
                           width: radius * 0.32, height: radius * 0.32)
            )
        }
        return path
    }
}

// MARK: - Goal

struct NeonGoal: View {
    let accent: Color
    var netOpacity: Double = 0.45
    var depth: CGFloat = 0.16
    var columns = 13
    var rows = 8
    var frameWidth: CGFloat = 1.9

    var body: some View {
        ZStack {
            GoalNetMesh(depth: depth, columns: columns, rows: rows)
                .stroke(accent.opacity(netOpacity), lineWidth: 0.45)

            GoalPosts(depth: depth)
                .stroke(accent, style: StrokeStyle(lineWidth: frameWidth, lineCap: .round, lineJoin: .round))
                .neonBloom(accent, radius: 2.6)
        }
    }
}

/// Front frame plus the four struts running back to the rear plane.
private struct GoalPosts: Shape {
    var depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * depth
        let vInset = rect.height * depth * 0.55

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + vInset))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + vInset))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))

        return path
    }
}

/// Dense woven mesh: back plane with sagging horizontals, plus side-panel netting so the
/// goal reads with depth.
private struct GoalNetMesh: Shape {
    var depth: CGFloat
    var columns: Int
    var rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * depth
        let vInset = rect.height * depth * 0.55
        let back = CGRect(
            x: rect.minX + inset,
            y: rect.minY + vInset,
            width: rect.width - inset * 2,
            height: rect.height - vInset
        )
        let sag = back.height * 0.045

        for index in 0...columns {
            let x = back.minX + back.width * CGFloat(index) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: back.minY))
            path.addLine(to: CGPoint(x: x, y: back.maxY))
        }

        for index in 0...rows {
            let y = back.minY + back.height * CGFloat(index) / CGFloat(rows)
            path.move(to: CGPoint(x: back.minX, y: y))
            path.addQuadCurve(
                to: CGPoint(x: back.maxX, y: y),
                control: CGPoint(x: back.midX, y: y + sag)
            )
        }

        // Side netting: front post out to the back plane.
        for index in 1...3 {
            let t = CGFloat(index) / 4
            let frontY = rect.minY + (rect.maxY - rect.minY) * t
            let backY = back.minY + (back.maxY - back.minY) * t
            path.move(to: CGPoint(x: rect.minX, y: frontY))
            path.addLine(to: CGPoint(x: back.minX, y: backY))
            path.move(to: CGPoint(x: rect.maxX, y: frontY))
            path.addLine(to: CGPoint(x: back.maxX, y: backY))
        }

        return path
    }
}

/// Concentric rings where the ball has pushed the net out — sells "it went in".
struct NetBulge: View {
    let accent: Color

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Ellipse()
                    .stroke(accent.opacity(0.55 - Double(ring) * 0.15), lineWidth: 0.7)
                    .scaleEffect(1 - CGFloat(ring) * 0.28)
            }
        }
        .neonBloom(accent, radius: 1.6)
    }
}

/// Three tapering arcs trailing the ball.
struct MotionTrail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<3 {
            let drop = CGFloat(index) * rect.height * 0.22
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - drop))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - CGFloat(index) * rect.width * 0.12, y: rect.minY + drop),
                control: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY - drop * 1.4)
            )
        }
        return path
    }
}

/// Caption pill shared by the attempt and set-piece tiles.
struct NeonCaption: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.45), lineWidth: 0.8))
            .padding(.horizontal, 3)
    }
}
