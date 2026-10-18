import SwiftUI

struct MatchHistoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MatchHistoryStore

    let savedMatchId: UUID
    @State private var match: MatchState

    init(store: MatchHistoryStore, savedMatch: SavedMatch) {
        self.store = store
        self.savedMatchId = savedMatch.id
        _match = State(initialValue: savedMatch.match)
    }

    var body: some View {
        NavigationStack {
            List {
                if !match.goals.isEmpty {
                    Section("Goals") {
                        ForEach(sortedGoals) { goal in
                            eventRow(title: goalTitle(goal), subtitle: nil)
                        }
                        .onDelete { offsets in
                            deleteGoals(at: offsets)
                        }
                    }
                }

                if !match.shots.isEmpty {
                    Section("Shots") {
                        ForEach(sortedShots) { shot in
                            eventRow(
                                title: shotTitle(shot),
                                subtitle: nil
                            )
                        }
                        .onDelete { offsets in
                            deleteShots(at: offsets)
                        }
                    }
                }

                if !match.passes.isEmpty {
                    Section("Passes & possession") {
                        ForEach(sortedPasses) { pass in
                            eventRow(
                                title: passTitle(pass),
                                subtitle: nil
                            )
                        }
                        .onDelete { offsets in
                            deletePasses(at: offsets)
                        }
                    }
                }

                if match.goals.isEmpty && match.shots.isEmpty && match.passes.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "tray",
                        description: Text("This match has nothing left to edit.")
                    )
                }
            }
            .navigationTitle("Edit Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateMatch(id: savedMatchId, match: match)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var sortedGoals: [GoalEvent] {
        match.goals
    }

    private var sortedShots: [ShotEvent] {
        match.shots.sorted { $0.matchSeconds < $1.matchSeconds }
    }

    private var sortedPasses: [PassEvent] {
        match.passes.sorted { $0.matchSeconds < $1.matchSeconds }
    }

    private func eventRow(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func goalTitle(_ goal: GoalEvent) -> String {
        let team = goal.team == .home ? match.homeTeamName : match.awayTeamName
        return "\(formattedClock(goal.matchSeconds)) · \(team) goal"
    }

    private func shotTitle(_ shot: ShotEvent) -> String {
        let team = shot.team == .home ? match.homeTeamName : match.awayTeamName
        return "\(formattedClock(shot.matchSeconds)) · \(team) · \(shot.difficulty.rawValue) · \(shot.outcome.rawValue)"
    }

    private func passTitle(_ pass: PassEvent) -> String {
        "\(formattedClock(pass.matchSeconds)) · \(pass.type.rawValue)"
    }

    private func formattedClock(_ seconds: Int) -> String {
        match.formattedClock(from: seconds)
    }

    /// A goal row is a view onto the shot that scored it — sharing its id — so deleting
    /// one deletes that shot. Removing the goal alone is what used to leave a match
    /// showing 2-2 while its shots still read 3-2.
    private func deleteGoals(at offsets: IndexSet) {
        let goals = sortedGoals
        for index in offsets {
            let goal = goals[index]
            match.shots.removeAll { $0.id == goal.id }
        }
    }

    private func deleteShots(at offsets: IndexSet) {
        let shots = sortedShots
        for index in offsets {
            let shot = shots[index]
            match.shots.removeAll { $0.id == shot.id }
        }
    }

    private func deletePasses(at offsets: IndexSet) {
        let passes = sortedPasses
        for index in offsets {
            let pass = passes[index]
            match.passes.removeAll { $0.id == pass.id }
        }
    }
}
