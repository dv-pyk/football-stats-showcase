import SwiftUI

struct SummaryView: View {
    @ObservedObject var viewModel: MatchViewModel
    var historyStore: MatchHistoryStore?
    var rosterStore: RosterStore = RosterStore()
    /// `nil` for the live in-progress match; a saved match's id when this view is showing
    /// History review — that's what tells the credit-tap flow whether to also persist back
    /// to `MatchHistoryStore` (checking `historyStore`'s nullability alone isn't enough,
    /// since it's passed non-nil in both cases).
    var savedMatchID: UUID?
    @State private var sharePayload: SharePayload?
    @State private var creditRequest: ChartCreditRequest?

    /// Presenting from the payload rather than a separate boolean. With
    /// `sheet(isPresented:)` the content closure reads state captured before the tap's
    /// update landed, so the first share went out empty and every later one was a tap
    /// behind.
    fileprivate struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    /// A tap on the chart's credited row — either a goal or a big save slot. Both credit
    /// the same underlying `ShotEvent` (`MatchViewModel.creditShot`), just with a different
    /// picker mode (`PlayerCreditPickerView.isBigSave`).
    private enum ChartCreditRequest: Identifiable {
        case goal(GoalChartMarker)
        case bigSave(ShotTickMarker)

        var id: UUID {
            switch self {
            case .goal(let goal): goal.id
            case .bigSave(let tick): tick.id
            }
        }

        var isBigSave: Bool {
            if case .bigSave = self { true } else { false }
        }
    }

    private var chartLabels: (home: String, away: String) {
        viewModel.pressureChartLabels
    }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = max(geometry.size.width - 32, 280)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.match.goals.isEmpty {
                        SummaryCopyableCard(
                            title: "Goal Timeline",
                            copyText: viewModel.goalTimelineText(),
                            cardWidth: cardWidth
                        ) {
                            Text(viewModel.goalTimelineText())
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !viewModel.match.passes.isEmpty || !viewModel.match.shots.isEmpty || !viewModel.match.goals.isEmpty {
                        SummaryCopyableCard(
                            title: "Pressure Index",
                            copyText: viewModel.pressureIndexCopyText(),
                            cardWidth: cardWidth,
                            customImage: pressureChartImage
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                MatchTeamsLegend(
                                    homeName: chartLabels.home,
                                    awayName: chartLabels.away,
                                    font: .subheadline
                                )

                                ComparisonBarsView(
                                    stats: [viewModel.goalsStat],
                                    valueFont: .system(size: 22, weight: .bold, design: .rounded),
                                    labelFont: .system(size: 12, weight: .medium),
                                    barHeight: 6
                                )

                                ComparisonBarsView(
                                    stats: [viewModel.possessionStat],
                                    valueFont: .system(size: 11, weight: .semibold, design: .rounded),
                                    labelFont: .system(size: 10),
                                    barHeight: 3
                                )
                                .padding(.top, -4)

                                PossessionChartView(
                                    points: viewModel.pressureChartPoints,
                                    goalMarkers: viewModel.goalChartMarkers,
                                    shotTicks: viewModel.shotTickMarkers,
                                    style: .full,
                                    avatarImage: { rosterStore.avatarImage(for: $0) },
                                    initials: { rosterStore.player(withID: $0)?.displayInitials },
                                    onGoalTap: { goal in
                                        guard goal.team == .home else { return }
                                        creditRequest = .goal(goal)
                                    },
                                    onSaveTap: { tick in
                                        creditRequest = .bigSave(tick)
                                    }
                                )
                                .frame(height: 240)

                                if !viewModel.comparisonStats.isEmpty {
                                    Divider()
                                    ComparisonBarsView(stats: viewModel.comparisonStats)
                                }
                            }
                        }
                    }

                    ForEach(TeamSide.allCases, id: \.self) { team in
                        shotCard(for: team, cardWidth: cardWidth)
                    }

                    if !viewModel.standoutMoments.isEmpty {
                        SummaryCopyableCard(
                            title: "Standout Moments",
                            copyText: viewModel.standoutMomentsCopyText,
                            cardWidth: cardWidth
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(viewModel.standoutMoments.enumerated()), id: \.offset) { _, moment in
                                    Text("• \(moment)")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !viewModel.matchObservations.isEmpty {
                        SummaryCopyableCard(
                            title: "Observations — \(viewModel.match.homeTeamName)",
                            copyText: viewModel.observationsCopyText,
                            cardWidth: cardWidth
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(viewModel.matchObservations.enumerated()), id: \.offset) { _, observation in
                                    Text("• \(observation)")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Button {
                        sharePayload = makeSharePayload()
                    } label: {
                        Label("Copy / Share for WhatsApp", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .sheet(item: $creditRequest) { request in
            PlayerCreditPickerView(
                roster: rosterStore.roster(for: viewModel.match.homeTeamName) ?? TeamRoster(teamName: viewModel.match.homeTeamName, players: []),
                avatarImage: { rosterStore.avatarImage(for: $0) },
                isBigSave: request.isBigSave,
                onCredit: { playerID in creditShot(id: request.id, to: playerID) }
            )
            .presentationDetents([.medium, .large])
        }
    }

    /// Catch-up crediting from the chart tap (goal or big save) — same underlying mutation
    /// as the Live tab's immediate popups (`MatchViewModel.creditShot`), plus persisting
    /// back to `MatchHistoryStore` when this is a saved match being reviewed after the fact.
    private func creditShot(id: UUID, to playerID: UUID?) {
        viewModel.creditShot(id: id, playerID: playerID)
        if let savedMatchID {
            historyStore?.updateMatch(id: savedMatchID, match: viewModel.match)
        }
    }

    private func shotCard(for team: TeamSide, cardWidth: CGFloat) -> some View {
        let summary = viewModel.shotSummary(for: team)
        return SummaryCopyableCard(
            title: "\(summary.teamName) Shots",
            copyText: viewModel.shotSummaryText(for: team),
            cardWidth: cardWidth
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(summary.lines) { line in
                    if line.total > 0 {
                        Text("• \(line.difficulty.rawValue): \(line.total) (\(line.goals) goals, \(line.notOnTarget) not on target)")
                    }
                }
                Divider()
                Text("• Total: \(summary.totalAttempts) attempts, \(summary.totalGoals) goals")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pressureChartImage() -> UIImage? {
        let labels = chartLabels
        return PossessionChartRenderer.image(
            points: viewModel.pressureChartPoints,
            goalMarkers: viewModel.goalChartMarkers,
            shotTicks: viewModel.shotTickMarkers,
            goalsStat: viewModel.goalsStat,
            possessionStat: viewModel.possessionStat,
            comparisonStats: viewModel.comparisonStats,
            homeName: labels.home,
            awayName: labels.away,
            avatarImage: { rosterStore.avatarImage(for: $0) },
            initials: { rosterStore.player(withID: $0)?.displayInitials }
        )
    }

    private func makeSharePayload() -> SharePayload? {
        var items: [Any] = []
        if let chartImage = pressureChartImage() {
            items.append(chartImage)
        }
        let observations = viewModel.whatsAppSummary()
        if !observations.isEmpty {
            items.append(observations)
        }
        guard !items.isEmpty else { return nil }
        return SharePayload(items: items)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SummaryView(viewModel: MatchViewModel())
}
