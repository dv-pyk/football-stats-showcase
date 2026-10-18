import SwiftUI
import UIKit

/// Set-piece tiles rendered from the neon artwork in the asset catalog rather than drawn
/// in SwiftUI. The artwork is the reference the owner signed off on, so we ship it directly
/// instead of approximating it with vector paths.
///
/// The tile background must be pure black: the artwork carries its own black background,
/// so on a lighter tile the image reads as a rectangle pasted on top. `SetPieceArtTile`
/// applies that, and the live screen and gallery both go through it.
struct SetPieceArtIcon: View {
    let kind: SetPieceKind
    var possession: TeamSide = .home
    var showsLabel = true

    var body: some View {
        // Caption overlays the artwork's bottom edge instead of sitting in its own row below
        // it, so the artwork can render at full size in a shorter tile rather than being
        // squeezed to make room for a label underneath.
        ZStack(alignment: .bottom) {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)

            if showsLabel {
                NeonCaption(text: kind.shortLabel, accent: .white)
                    .padding(.bottom, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(kind.accessibilityLabel)
    }

    private var baseAssetName: String {
        switch kind {
        case .corner: "SetPieceCorner"
        case .penalty: "SetPiecePenalty"
        case .freeKick: "SetPieceFreeKick"
        }
    }

    /// Away artwork ships for all three kinds (`SetPieceCornerAway`, `SetPiecePenaltyAway`,
    /// `SetPieceFreeKickAway`). Falls back to the green artwork if a future kind is added
    /// without its away counterpart, so the row never renders blank.
    private var assetName: String {
        guard possession == .away else { return baseAssetName }
        let awayName = baseAssetName + "Away"
        return UIImage(named: awayName) != nil ? awayName : baseAssetName
    }
}

/// Black tile the artwork sits on, so the image edge is invisible.
struct SetPieceArtTile<Content: View>: View {
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }
}

#Preview("Set piece artwork") {
    VStack(spacing: 12) {
        ForEach([TeamSide.home, .away], id: \.self) { side in
            HStack(spacing: 8) {
                ForEach(SetPieceKind.allCases) { kind in
                    SetPieceArtTile {
                        SetPieceArtIcon(kind: kind, possession: side)
                            .frame(height: 80)
                    }
                }
            }
        }
    }
    .padding()
    .background(Color(white: 0.12))
}
