import SwiftUI

/// Review-only screen: current shipped icons next to the neon candidates, in both
/// possession colours. Not reachable from the app — it is swapped in temporarily when
/// judging an icon revision, then swapped back out.
struct IconGalleryView: View {
    private let difficulties: [ShotDifficulty] = [.normal, .easy, .hard]
    private let kinds: [ShotOutcomeIconKind] = [.goal, .saved, .miss]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                shotTileSection

                artworkSetPieces

                setPieceSection

                magnifiedSetPieces

                section(
                    title: "NEW — ours (green)",
                    subtitle: "neon candidate",
                    accent: NeonIconPalette.green
                ) {
                    neonGrid(possession: NeonIconPalette.green)
                }

                section(
                    title: "NEW — theirs (red)",
                    subtitle: "neon candidate",
                    accent: NeonIconPalette.red
                ) {
                    neonGrid(possession: NeonIconPalette.red)
                }

                section(
                    title: "CURRENT — in the app today",
                    subtitle: "emoji + thin strokes",
                    accent: .gray
                ) {
                    currentGrid
                }
            }
            .padding(16)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            columnHeaders
            content()
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            ForEach(["GOAL", "BLOCKED", "MISS"], id: \.self) { title in
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var setPieceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SET PIECES — actual size")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(NeonIconPalette.chrome)

            ForEach([NeonIconPalette.green, NeonIconPalette.red], id: \.self) { possession in
                HStack(spacing: 8) {
                    ForEach(SetPieceKind.allCases) { kind in
                        NeonSetPieceIcon(kind: kind, possession: possession)
                            .background(
                                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    /// `ShotTileIcon` — HANDOFF-live-screen.md §1: one drawing system per row/column instead
    /// of nine unrelated pictures. Shown in both possession colours so the ball tint can be
    /// judged without starting a match.
    private var shotTileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHOT TILES — shipped")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(ShotTilePalette.goal)

            ForEach(TeamSide.allCases, id: \.self) { possession in
                VStack(alignment: .leading, spacing: 3) {
                    Text(possession == .home ? "ours" : "theirs")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(difficulties) { difficulty in
                            HStack(spacing: 8) {
                                ForEach(ShotTileKind.allCases) { kind in
                                    ShotTileIcon(kind: kind, difficulty: difficulty, possession: possession)
                                        .frame(height: difficulty == .normal ? 80 : 78)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The reference artwork shipped as assets, at three candidate row heights.
    private var artworkSetPieces: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SET PIECES — reference artwork")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(NeonIconPalette.green)

            ForEach([CGFloat(64), 84, 104], id: \.self) { height in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Int(height))pt row")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(SetPieceKind.allCases) { kind in
                            SetPieceArtIcon(kind: kind)
                                .frame(height: height)
                                // Black to match the artwork's own background, otherwise
                                // the image reads as a box pasted onto a lighter tile.
                                .background(
                                    RoundedRectangle(cornerRadius: 10).fill(Color.black)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }

    /// Same tiles blown up, purely so line weight and figure detail can be judged.
    private var magnifiedSetPieces: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SET PIECES — magnified")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(NeonIconPalette.chrome.opacity(0.7))

            ForEach(SetPieceKind.allCases) { kind in
                NeonSetPieceIcon(kind: kind)
                    .scaleEffect(2.6, anchor: .center)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            }
        }
    }

    private func neonGrid(possession: Color) -> some View {
        VStack(spacing: 6) {
            ForEach(difficulties) { difficulty in
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.self) { kind in
                        NeonShotIcon(kind: kind, difficulty: difficulty, possession: possession)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(white: 0.09))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    /// Shown on the tinted buttons the live screen actually uses today.
    private var currentGrid: some View {
        VStack(spacing: 6) {
            ForEach(difficulties) { difficulty in
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.self) { kind in
                        ShotOutcomeIcon(kind: kind, difficulty: difficulty)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(tint(for: kind))
                            )
                    }
                }
            }
        }
    }

    private func tint(for kind: ShotOutcomeIconKind) -> Color {
        switch kind {
        case .goal: .green
        case .saved: .yellow
        case .miss: .gray
        }
    }
}

#Preview {
    IconGalleryView()
}
