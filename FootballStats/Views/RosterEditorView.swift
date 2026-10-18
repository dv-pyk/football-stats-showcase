import SwiftUI

/// Reached only from `MatchSetupView`'s "Your team" section — there's no separate
/// roster-management screen (per the decided shape of this feature).
struct RosterEditorView: View {
    @ObservedObject var rosterStore: RosterStore
    let teamName: String

    @State private var editingPlayer: RosterPlayer?
    @State private var showingNewPlayer = false

    private var players: [RosterPlayer] {
        rosterStore.roster(for: teamName)?.players ?? []
    }

    var body: some View {
        List {
            if players.isEmpty {
                Section {
                    Text("No players yet. Add your squad so goals and big saves can be credited to a player.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(players) { player in
                        Button {
                            editingPlayer = player
                        } label: {
                            RosterPlayerRow(player: player, avatar: rosterStore.avatarImage(for: player.id))
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deletePlayers)
                }
            }

            Section {
                Button {
                    showingNewPlayer = true
                } label: {
                    Label("Add Player", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle(teamName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewPlayer) {
            NavigationStack {
                PlayerEditorView(rosterStore: rosterStore, teamName: teamName, existingPlayer: nil)
            }
        }
        .sheet(item: $editingPlayer) { player in
            NavigationStack {
                PlayerEditorView(rosterStore: rosterStore, teamName: teamName, existingPlayer: player)
            }
        }
    }

    private func deletePlayers(at offsets: IndexSet) {
        for index in offsets {
            rosterStore.deletePlayer(id: players[index].id, from: teamName)
        }
    }
}

/// Shown in place of a photo, in a plain gray circle, wherever a roster player has none —
/// the roster list, the credit picker. The pressure chart's credited-row badges use their
/// own team-tinted variant instead (`PossessionChartView.swift`), to match that screen's
/// colour language rather than this neutral list styling.
struct InitialsAvatarView: View {
    let initials: String
    var fontSize: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(
                Text(initials)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            )
    }
}

private struct RosterPlayerRow: View {
    let player: RosterPlayer
    let avatar: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    InitialsAvatarView(initials: player.displayInitials, fontSize: 16)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

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

            if player.isKeeper {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Keeper")
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        RosterEditorView(rosterStore: RosterStore(), teamName: PresetHomeTeam.defaultName)
    }
}
