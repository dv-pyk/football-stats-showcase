import SwiftUI

/// Opened by tapping a goal's ball on the Summary tab's pressure chart. Three answers —
/// where the shot came from, where in the goal it went, and what shape of flight got it
/// there — with a live isometric preview pinned above so each tap shows up on the same map
/// the Summary tab will draw.
struct GoalPlacementSheet: View {
    let marker: GoalChartMarker
    let spec: PitchSpec
    let homeLabel: String
    let awayLabel: String
    let scorerName: String?
    /// The map's current surface and camera angle, so the preview looks like the map it will
    /// land on.
    let surface: GoalMapSurface
    let flipped: Bool
    /// `nil` clears the placement.
    let onSave: (ShotPlacement?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var origin: PitchPoint?
    @State private var goalMouth: GoalMouthPoint?
    @State private var trajectory: ShotTrajectory

    init(
        marker: GoalChartMarker,
        spec: PitchSpec,
        homeLabel: String,
        awayLabel: String,
        scorerName: String?,
        surface: GoalMapSurface,
        flipped: Bool,
        onSave: @escaping (ShotPlacement?) -> Void
    ) {
        self.marker = marker
        self.spec = spec
        self.homeLabel = homeLabel
        self.awayLabel = awayLabel
        self.scorerName = scorerName
        self.surface = surface
        self.flipped = flipped
        self.onSave = onSave
        _origin = State(initialValue: marker.placement?.origin)
        _goalMouth = State(initialValue: marker.placement?.goalMouth)
        _trajectory = State(initialValue: marker.placement?.trajectory ?? .straight)
    }

    private var tint: Color { GoalMapPalette.tint(for: marker.team) }

    private var canSave: Bool { origin != nil && goalMouth != nil }

    private var draft: GoalMapShot {
        GoalMapShot(
            id: marker.id,
            team: marker.team,
            origin: origin,
            goalMouth: goalMouth,
            trajectory: trajectory
        )
    }

    private var headline: String {
        let team = marker.team == .home ? homeLabel : awayLabel
        return [team, "\(marker.minuteLabel) \(marker.scoreLabel)", scorerName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        step(
                            1,
                            "Where was it shot from?",
                            isDone: origin != nil,
                            hint: "Tap the pitch. The goal you're attacking is on the right."
                        ) {
                            PitchPickerView(spec: spec, surface: surface, tint: tint, origin: $origin)
                        }

                        step(
                            2,
                            "Where did it go in?",
                            isDone: goalMouth != nil,
                            hint: "The goal as the shooter saw it — left post on the left."
                        ) {
                            GoalFacePickerView(spec: spec, tint: tint, goalMouth: $goalMouth)
                        }

                        step(3, "How did it get there?", isDone: true) {
                            TrajectoryPickerView(selection: $trajectory, tint: tint)
                        }

                        if marker.placement != nil {
                            Button(role: .destructive) {
                                onSave(nil)
                                dismiss()
                            } label: {
                                Label("Remove placement", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Place the Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // Pinned above the pickers, so kept small enough to leave them room.
            GoalMapPitchView(
                spec: spec,
                shots: [draft],
                homeLabel: homeLabel,
                awayLabel: awayLabel,
                surface: surface,
                flipped: flipped
            )
            .frame(maxWidth: 280)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func step<Content: View>(
        _ number: Int,
        _ title: String,
        isDone: Bool,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 20, height: 20)
                    .background(tint, in: Circle())
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            content()

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        guard let origin, let goalMouth else { return }
        onSave(ShotPlacement(origin: origin, goalMouth: goalMouth, trajectory: trajectory))
        dismiss()
    }
}

// MARK: - 1. Where it was shot from

/// A flat, top-down pitch rather than the isometric one: tapping a foreshortened trapezoid
/// would make the far half far less precise than the near half. Always drawn attacking left
/// to right, whichever team scored — the placement is stored in that same attacking frame.
private struct PitchPickerView: View {
    let spec: PitchSpec
    let surface: GoalMapSurface
    let tint: Color
    @Binding var origin: PitchPoint?

    private let cornerRadius: CGFloat = 10
    /// Keeps the goal line and touchlines inside the canvas, where a stroke isn't half clipped.
    private let margin: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Canvas { context, size in
                draw(&context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let pitch = pitchRect(in: size)
                    // A tap in the margin still means "right on the line".
                    origin = PitchPoint(
                        x: min(max(Double((value.location.x - pitch.minX) / pitch.width), 0), 1),
                        y: min(max(1 - Double((value.location.y - pitch.minY) / pitch.height), 0), 1)
                    )
                    HapticFeedback.selection()
                }
            )
        }
        .aspectRatio(spec.length / spec.width, contentMode: .fit)
        .background(
            LinearGradient(
                colors: [GoalMapPalette.stageTop, GoalMapPalette.stageBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("Pitch. Tap where the shot was taken from.")
    }

    /// The pitch at its true proportions, centred with a margin all round.
    private func pitchRect(in size: CGSize) -> CGRect {
        let scale = min(
            (size.width - 2 * margin) / CGFloat(spec.length),
            (size.height - 2 * margin) / CGFloat(spec.width)
        )
        let width = CGFloat(spec.length) * scale
        let height = CGFloat(spec.width) * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func screen(_ metres: CGPoint, in pitch: CGRect) -> CGPoint {
        CGPoint(
            x: pitch.minX + metres.x / CGFloat(spec.length) * pitch.width,
            y: pitch.maxY - metres.y / CGFloat(spec.width) * pitch.height
        )
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let pitch = pitchRect(in: size)
        let style = surface.style

        GoalMapSurfaceRenderer.draw(&context, spec: spec, surface: surface) { x, y in
            screen(CGPoint(x: x, y: y), in: pitch)
        }

        let markings = spec.markings
        for line in markings.lines {
            var path = Path()
            for (index, point) in line.enumerated() {
                let mapped = screen(point, in: pitch)
                if index == 0 {
                    path.move(to: mapped)
                } else {
                    path.addLine(to: mapped)
                }
            }
            context.stroke(
                path,
                with: .color(style.line),
                style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        for spot in markings.spots {
            let mapped = screen(spot, in: pitch)
            context.fill(
                Path(ellipseIn: CGRect(x: mapped.x - 1.5, y: mapped.y - 1.5, width: 3, height: 3)),
                with: .color(style.line)
            )
        }

        // The goal being attacked, lit in the scoring team's colour.
        let goalTop = screen(CGPoint(x: spec.length, y: spec.width / 2 + spec.goalWidth / 2), in: pitch)
        let goalBottom = screen(CGPoint(x: spec.length, y: spec.width / 2 - spec.goalWidth / 2), in: pitch)
        var goal = Path()
        goal.move(to: goalTop)
        goal.addLine(to: goalBottom)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.stroke(goal, with: .color(tint), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        context.stroke(goal, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        // Attack direction, quietly — same chevrons the basketball reference uses. Parked
        // between the centre circle and the penalty area so they don't sit on a marking.
        for index in 0..<3 {
            let x = pitch.minX + pitch.width * (0.58 + 0.05 * CGFloat(index))
            let midY = pitch.midY
            var chevron = Path()
            chevron.move(to: CGPoint(x: x, y: midY - 9))
            chevron.addLine(to: CGPoint(x: x + 7, y: midY))
            chevron.addLine(to: CGPoint(x: x, y: midY + 9))
            context.stroke(
                chevron,
                with: .color(tint.opacity(0.25 + 0.2 * Double(index))),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }

        guard let origin else { return }
        let ball = CGPoint(
            x: pitch.minX + origin.x * pitch.width,
            y: pitch.maxY - origin.y * pitch.height
        )

        var aim = Path()
        aim.move(to: ball)
        aim.addLine(to: CGPoint(x: pitch.maxX, y: pitch.midY))
        context.stroke(
            aim,
            with: .color(tint.opacity(0.45)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4])
        )

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.fill(Path(ellipseIn: dot(ball, 8)), with: .color(tint.opacity(0.9)))
        }
        context.fill(Path(ellipseIn: dot(ball, 5)), with: .color(.white))
        context.stroke(Path(ellipseIn: dot(ball, 7)), with: .color(tint), lineWidth: 2)
    }

    private func dot(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}

// MARK: - 2. Where it went in

private struct GoalFacePickerView: View {
    let spec: PitchSpec
    let tint: Color
    @Binding var goalMouth: GoalMouthPoint?

    private static let sideMargin: CGFloat = 0.08
    private static let topMargin: CGFloat = 0.10
    private static let bottomMargin: CGFloat = 0.07

    /// The goal's rectangle inside a canvas of this width — shared by drawing and tapping so
    /// the two can never disagree about where the post is.
    private func goalRect(width: CGFloat) -> CGRect {
        let goalWidth = width * (1 - 2 * Self.sideMargin)
        return CGRect(
            x: width * Self.sideMargin,
            y: width * Self.topMargin,
            width: goalWidth,
            height: goalWidth * CGFloat(spec.goalHeight / spec.goalWidth)
        )
    }

    private var aspectRatio: CGFloat {
        let goalHeight = (1 - 2 * Self.sideMargin) * CGFloat(spec.goalHeight / spec.goalWidth)
        return 1 / (Self.topMargin + goalHeight + Self.bottomMargin)
    }

    var body: some View {
        GeometryReader { geometry in
            let rect = goalRect(width: geometry.size.width)

            Canvas { context, size in
                draw(&context, size: size, goal: goalRect(width: size.width))
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    // A tap just outside the frame still means "the corner" — the ball was in.
                    goalMouth = GoalMouthPoint(
                        x: min(max(Double((value.location.x - rect.minX) / rect.width), 0), 1),
                        y: min(max(Double((rect.maxY - value.location.y) / rect.height), 0), 1)
                    )
                    HapticFeedback.selection()
                }
            )
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(
            LinearGradient(
                colors: [GoalMapPalette.stageTop, GoalMapPalette.stageBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Goal. Tap where the ball went in.")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, goal: CGRect) {
        // Ground.
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: goal.maxY))
        ground.addLine(to: CGPoint(x: size.width, y: goal.maxY))
        context.stroke(ground, with: .color(.white.opacity(0.35)), lineWidth: 1)

        // Net.
        context.fill(Path(goal), with: .color(.white.opacity(0.05)))
        var net = Path()
        let columns = 12
        for column in 1..<columns {
            let x = goal.minX + goal.width * CGFloat(column) / CGFloat(columns)
            net.move(to: CGPoint(x: x, y: goal.minY))
            net.addLine(to: CGPoint(x: x, y: goal.maxY))
        }
        let rows = max(Int((CGFloat(columns) * goal.height / goal.width).rounded()), 2)
        for row in 1..<rows {
            let y = goal.minY + goal.height * CGFloat(row) / CGFloat(rows)
            net.move(to: CGPoint(x: goal.minX, y: y))
            net.addLine(to: CGPoint(x: goal.maxX, y: y))
        }
        context.stroke(net, with: .color(.white.opacity(0.13)), lineWidth: 0.5)

        // Frame.
        var frame = Path()
        frame.move(to: CGPoint(x: goal.minX, y: goal.maxY))
        frame.addLine(to: CGPoint(x: goal.minX, y: goal.minY))
        frame.addLine(to: CGPoint(x: goal.maxX, y: goal.minY))
        frame.addLine(to: CGPoint(x: goal.maxX, y: goal.maxY))
        context.stroke(
            frame,
            with: .color(.white.opacity(0.95)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )

        guard let goalMouth else { return }
        let ball = CGPoint(
            x: goal.minX + goal.width * goalMouth.x,
            y: goal.maxY - goal.height * goalMouth.y
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.fill(Path(ellipseIn: dot(ball, 8)), with: .color(tint.opacity(0.9)))
        }
        context.fill(Path(ellipseIn: dot(ball, 5)), with: .color(.white))
        context.stroke(Path(ellipseIn: dot(ball, 7)), with: .color(tint), lineWidth: 2)
    }

    private func dot(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}

// MARK: - 3. Flight

private struct TrajectoryPickerView: View {
    @Binding var selection: ShotTrajectory
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ShotTrajectory.allCases) { option in
                let isSelected = option == selection

                Button {
                    selection = option
                    HapticFeedback.selection()
                } label: {
                    VStack(spacing: 6) {
                        TrajectoryGlyph(trajectory: option, tint: isSelected ? tint : .secondary)
                            .frame(height: 44)
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? tint.opacity(0.16) : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? tint : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// A side-on picture of each flight, drawn with the same curve `ShotFlight` uses so the
/// button promises exactly what the map will show.
private struct TrajectoryGlyph: View {
    let trajectory: ShotTrajectory
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 10
            let groundY = size.height - 4
            let start = CGPoint(x: inset, y: groundY)
            let end = CGPoint(x: size.width - inset, y: groundY - size.height * 0.35)
            let peak: CGFloat = switch trajectory {
            case .straight: 0
            case .arc: size.height * 0.30
            case .high: size.height * 0.62
            }

            var floor = Path()
            floor.move(to: CGPoint(x: 0, y: groundY))
            floor.addLine(to: CGPoint(x: size.width, y: groundY))
            context.stroke(floor, with: .color(.secondary.opacity(0.35)), lineWidth: 1)

            var path = Path()
            let steps = 32
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t - 4 * peak * t * (1 - t)
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(tint))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(tint))
        }
        .accessibilityHidden(true)
    }
}
