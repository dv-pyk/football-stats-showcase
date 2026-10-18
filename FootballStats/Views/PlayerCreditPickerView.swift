import SwiftUI

/// Shared "credit this shot to a player" sheet — used both for the Live tab's immediate
/// popups (own-team goals and big saves) and Summary's tap-to-credit catch-up flow. The
/// caller supplies the roster to show and what happens when a player (or nil, "Do Later")
/// is picked; this view has no idea whether it's live or historical.
struct PlayerCreditPickerView: View {
    let roster: TeamRoster
    let avatarImage: (UUID) -> UIImage?
    var isBigSave: Bool = false
    /// `nil` means "Do Later" / clear the credit.
    let onCredit: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var orderedPlayers: [RosterPlayer] {
        let matches = roster.players.filter { player in
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return player.name.lowercased().contains(needle)
                || (player.jerseyNumber?.lowercased().contains(needle) ?? false)
        }

        guard isBigSave else {
            return matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        // Keeper first (pre-selected default) — everyone else stays one tap away to override.
        return matches.sorted { lhs, rhs in
            if lhs.isKeeper != rhs.isKeeper { return lhs.isKeeper }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedPlayers) { player in
                    Button {
                        onCredit(player.id)
                        dismiss()
                    } label: {
                        PlayerCreditRow(
                            player: player,
                            avatar: avatarImage(player.id),
                            isDefault: isBigSave && player.isKeeper
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Name or jersey number")
            .navigationTitle(isBigSave ? "Credit the Save" : "Credit the Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Do Later") {
                        onCredit(nil)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PlayerCreditRow: View {
    let player: RosterPlayer
    let avatar: UIImage?
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    InitialsAvatarView(initials: player.displayInitials, fontSize: 17)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(isDefault ? Color.accentColor : .clear, lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .foregroundStyle(.primary)
                if let jerseyNumber = player.jerseyNumber, !jerseyNumber.isEmpty {
                    Text("#\(jerseyNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isDefault {
                Text("Keeper")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    PlayerCreditPickerView(
        roster: TeamRoster(teamName: PresetHomeTeam.defaultName, players: [
            RosterPlayer(name: "Alex", jerseyNumber: "9"),
            RosterPlayer(name: "Sam", jerseyNumber: "1", isKeeper: true)
        ]),
        avatarImage: { _ in nil },
        isBigSave: true,
        onCredit: { _ in }
    )
}
