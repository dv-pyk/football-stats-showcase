import SwiftUI
import UniformTypeIdentifiers

struct MatchHistoryView: View {
    @ObservedObject var store: MatchHistoryStore
    var rosterStore: RosterStore

    @State private var sharePayload: SharePayload?
    @State private var showImporter = false
    @State private var backupError: String?

    /// Same reason as the match summary: driving the sheet from a boolean let it
    /// present before the item state landed, so the first export shared nothing.
    fileprivate struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var groupedMatches: [(team: String, matches: [SavedMatch])] {
        let groups = Dictionary(grouping: store.matches, by: { $0.match.homeTeamName })
        return groups.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { team in
                let matches = (groups[team] ?? []).sorted { $0.match.kickoffDate > $1.match.kickoffDate }
                return (team: team, matches: matches)
            }
    }

    var body: some View {
        Group {
            if store.matches.isEmpty {
                ContentUnavailableView(
                    "No Matches Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finished matches are saved automatically when you hold the End button.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(groupedMatches, id: \.team) { group in
                            TeamHistoryRow(
                                team: group.team,
                                matches: group.matches,
                                dateFormatter: Self.dateFormatter,
                                store: store,
                                rosterStore: rosterStore
                            )
                        }

                        backupFooter
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        // Present after the menu has dismissed. Doing it in the same
                        // turn leaves UIKit's system gesture gate holding the tap for
                        // ~10s, which is the lag and the "gesture gate timed out" spam.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            exportBackup()
                        }
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.matches.isEmpty)

                    Button {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            showImporter = true
                        }
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "externaldrive")
                }
                .accessibilityLabel("Backup")
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importBackup(from: result)
        }
        .alert("Backup", isPresented: Binding(
            get: { store.lastBackupMessage != nil },
            set: { if !$0 { store.lastBackupMessage = nil } }
        )) {
            Button("OK") {
                store.lastBackupMessage = nil
            }
        } message: {
            Text(store.lastBackupMessage ?? "")
        }
        .alert("Backup Error", isPresented: Binding(
            get: { backupError != nil },
            set: { if !$0 { backupError = nil } }
        )) {
            Button("OK") {
                backupError = nil
            }
        } message: {
            Text(backupError ?? "")
        }
    }

    private var backupFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Saved on this device", systemImage: "iphone")
            Text("Use Export Backup to save to Files or iCloud Drive before reinstalling.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func exportBackup() {
        do {
            let url = try store.makeExportFile(rosters: rosterStore.backupRosters())
            sharePayload = SharePayload(items: [url])
        } catch {
            backupError = error.localizedDescription
        }
    }

    private func importBackup(from result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let rosters = try store.importBackup(from: url)
                rosterStore.mergeFromBackup(rosters)
            } catch {
                backupError = error.localizedDescription
            }
        case .failure(let error):
            backupError = error.localizedDescription
        }
    }
}

private struct TeamHistoryRow: View {
    let team: String
    let matches: [SavedMatch]
    let dateFormatter: DateFormatter
    @ObservedObject var store: MatchHistoryStore
    var rosterStore: RosterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(team)
                .font(.title3.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, saved in
                        NavigationLink {
                            MatchHistoryDetailView(store: store, rosterStore: rosterStore, savedMatch: saved)
                                .id(saved.id)
                        } label: {
                            MatchHistoryCard(
                                savedMatch: saved,
                                dateFormatter: dateFormatter,
                                isFeatured: index == 0
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(saved)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct MatchHistoryCard: View {
    let savedMatch: SavedMatch
    let dateFormatter: DateFormatter
    let isFeatured: Bool

    private var cardWidth: CGFloat { isFeatured ? 190 : 148 }
    private var scoreFont: Font { isFeatured ? .system(size: 34, weight: .bold) : .title2.bold() }

    /// Nil for a draw — a draw is neither a win nor a loss, so the card stays neutral
    /// rather than picking a side.
    private var resultColor: Color? {
        let home = savedMatch.match.score(for: .home)
        let away = savedMatch.match.score(for: .away)
        if home > away { return .green }
        if home < away { return .red }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isFeatured ? 10 : 6) {
            Text("vs \(savedMatch.match.awayTeamName)")
                .font(isFeatured ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: isFeatured ? 10 : 6) {
                Text("\(savedMatch.match.score(for: .home))")
                    .foregroundStyle(.green)
                Text("–")
                    .foregroundStyle(.secondary)
                Text("\(savedMatch.match.score(for: .away))")
                    .foregroundStyle(.red)
            }
            .font(scoreFont)
            .monospacedDigit()

            Text(dateFormatter.string(from: savedMatch.match.kickoffDate))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(isFeatured ? 16 : 12)
        .frame(width: cardWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: isFeatured ? 18 : 14))
        .overlay(
            // A quiet glow in the corner farthest from the text (top-leading, where the
            // team name/score/date sit) rather than a full wash, so the result reads
            // peripherally without competing with the score for attention. Sits on top of
            // the material (not behind it) so the tint isn't blurred away to nothing.
            RadialGradient(
                colors: [(resultColor ?? .clear).opacity(0.55), (resultColor ?? .clear).opacity(0)],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: isFeatured ? 150 : 115
            )
            .clipShape(RoundedRectangle(cornerRadius: isFeatured ? 18 : 14))
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isFeatured ? 18 : 14)
                .strokeBorder(isFeatured ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
        )
    }
}

struct MatchHistoryDetailView: View {
    @ObservedObject var store: MatchHistoryStore
    var rosterStore: RosterStore
    let savedMatch: SavedMatch
    @StateObject private var viewModel: MatchViewModel
    @State private var showingEdit = false

    init(store: MatchHistoryStore, rosterStore: RosterStore, savedMatch: SavedMatch) {
        self.store = store
        self.rosterStore = rosterStore
        self.savedMatch = savedMatch
        _viewModel = StateObject(
            wrappedValue: MatchViewModel(match: savedMatch.match, isReadOnly: true)
        )
    }

    var body: some View {
        SummaryView(
            viewModel: viewModel,
            historyStore: store,
            rosterStore: rosterStore,
            savedMatchID: savedMatch.id
        )
        .navigationTitle(savedMatch.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            MatchHistoryEditView(store: store, savedMatch: savedMatch)
        }
        .onChange(of: store.matches) { _, _ in
            refreshFromStore()
        }
    }

    private func refreshFromStore() {
        guard let updated = store.matches.first(where: { $0.id == savedMatch.id }) else { return }
        viewModel.match = updated.match
    }
}

#Preview {
    NavigationStack {
        MatchHistoryView(store: MatchHistoryStore(), rosterStore: RosterStore())
    }
}
