import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = MatchViewModel()
    @StateObject private var historyStore = MatchHistoryStore()
    @StateObject private var rosterStore = RosterStore()
    @State private var showingSetup = true

    var body: some View {
        NavigationStack {
            Group {
                if showingSetup {
                    MatchSetupView(
                        rosterStore: rosterStore,
                        homeName: viewModel.match.homeTeamName,
                        awayName: viewModel.match.awayTeamName
                    ) { home, away, gameFormat, kickoffTiming, kickoff in
                        viewModel.startNewMatch(home: home, away: away, kickoffTiming: kickoffTiming, gameFormat: gameFormat, kickoff: kickoff)
                        showingSetup = false
                    }
                } else {
                    TabView(selection: $viewModel.selectedTab) {
                        MatchHistoryView(store: historyStore, rosterStore: rosterStore)
                            .tag(MatchViewModel.MatchTab.history)

                        LiveMatchView(viewModel: viewModel, rosterStore: rosterStore, onEndAndSave: finishCurrentMatch)
                            .tag(MatchViewModel.MatchTab.live)

                        SummaryView(viewModel: viewModel, historyStore: historyStore, rosterStore: rosterStore)
                            .tag(MatchViewModel.MatchTab.summary)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .safeAreaInset(edge: .bottom) {
                        Picker("Section", selection: $viewModel.selectedTab) {
                            ForEach(MatchViewModel.MatchTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showingSetup || viewModel.selectedTab != .live ? .visible : .hidden, for: .navigationBar)
            .onAppear {
                if ActiveMatchStore.shared.load() != nil {
                    viewModel.resumePersistedMatchIfNeeded()
                    showingSetup = false
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || phase == .inactive {
                    viewModel.flushToStore()
                } else if phase == .active {
                    viewModel.syncFromActiveStoreIfNeeded()
                }
            }
            .toolbar {
                if showingSetup {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            MatchHistoryView(store: historyStore, rosterStore: rosterStore)
                        } label: {
                            Text("History")
                        }
                    }
                } else if viewModel.selectedTab == .summary {
                    ToolbarItem(placement: .principal) {
                        scoreAndClockHeader
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        if showingSetup { return "New Match" }
        switch viewModel.selectedTab {
        case .history: return "Match History"
        case .live: return ""
        case .summary: return ""
        }
    }

    private func finishCurrentMatch() {
        viewModel.finishMatch()
        historyStore.save(viewModel.match)
        showingSetup = true
    }

    private var scoreAndClockHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(viewModel.match.score(for: .home))")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .monospacedDigit()
            Text("–")
                .foregroundStyle(.secondary)
            Text("\(viewModel.match.score(for: .away))")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .monospacedDigit()
            Text(viewModel.match.currentClock)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview {
    ContentView()
}
