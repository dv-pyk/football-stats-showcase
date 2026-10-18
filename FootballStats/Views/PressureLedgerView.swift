import SwiftUI

/// The full history behind the reasoning lane (`PressureLaneView`) — every turning point in
/// the last two minutes, in plain language, with an undo on each row. Presented as a sheet
/// from the lane (HANDOFF-live-screen.md §4).
struct PressureLedgerView: View {
    @ObservedObject var viewModel: MatchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .turningPoints
    @State private var expandedGroupIDs: Set<UUID> = []

    private enum Mode: Hashable {
        case turningPoints
        case everyTap
    }

    private static let turningPointRowColor = Color(red: 0.173, green: 0.173, blue: 0.184) // #2C2C2E
    private static let passRowColor = Color(red: 0.141, green: 0.141, blue: 0.149)          // #242426
    private static let footerFill = Color(red: 0.109, green: 0.109, blue: 0.118)            // #1C1C1E

    var body: some View {
        NavigationStack {
            Group {
                if displayedRows.isEmpty {
                    ContentUnavailableView(
                        "Nothing in the last 2 minutes",
                        systemImage: "waveform.path.ecg",
                        description: Text("Turning points will show up here as they happen.")
                    )
                } else {
                    List {
                        ForEach(displayedRows) { entry in
                            row(for: entry)
                        }

                        Section {
                            footer
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.black)
            .safeAreaInset(edge: .top) { header }
            .navigationTitle("What the index is doing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 2 minutes — everything older has dropped out.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("View", selection: $mode) {
                Text("Turning points").tag(Mode.turningPoints)
                Text("Every tap (\(everyTap.count))").tag(Mode.everyTap)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Rows

    private func row(for entry: PressureEngine.Explained) -> some View {
        let isGroup = isExpandableGroup(entry)
        let isPass: Bool = {
            if case .pass = entry.kind { return true }
            return false
        }()

        return Button {
            if isGroup {
                expandedGroupIDs.insert(entry.id)
            } else {
                viewModel.removeExplained(entry)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(timeLabel(for: entry))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(for: entry))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let reason = entry.reason {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(PressureNarration.signedLabel(entry.delta))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PressureNarration.color(for: entry))
                    Image(systemName: isGroup ? "chevron.down" : "minus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(isPass ? Self.passRowColor : Self.turningPointRowColor)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Index now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", viewModel.currentPressure))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Text("Events fade to 40% over 2 minutes, then drop out")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Self.footerFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Data

    /// Newest first — the story of "what just happened" belongs at the top, not the bottom.
    private var turningPoints: [PressureEngine.Explained] {
        viewModel.explained(rollUpPasses: true).sorted { $0.seconds > $1.seconds }
    }

    private var everyTap: [PressureEngine.Explained] {
        viewModel.explained(rollUpPasses: false).sorted { $0.seconds > $1.seconds }
    }

    /// Turning points, except any group the user has tapped to expand is replaced by its
    /// individual taps — so one tap can never remove seven events at once (§4).
    private var displayedRows: [PressureEngine.Explained] {
        switch mode {
        case .everyTap:
            return everyTap
        case .turningPoints:
            return turningPoints.flatMap { entry -> [PressureEngine.Explained] in
                guard isExpandableGroup(entry), expandedGroupIDs.contains(entry.id) else {
                    return [entry]
                }
                let memberIDs = Set(entry.eventIDs)
                return everyTap.filter { member in
                    guard case .pass = member.kind, let id = member.eventIDs.first else { return false }
                    return memberIDs.contains(id)
                }
            }
        }
    }

    private func isExpandableGroup(_ entry: PressureEngine.Explained) -> Bool {
        if case .pass(let count) = entry.kind { return count > 1 }
        return false
    }

    private func rowTitle(for entry: PressureEngine.Explained) -> String {
        if case .pass(let count) = entry.kind, count > 1 {
            let team = entry.team == .home ? homeTeamName : awayTeamName
            return "\(count) passes — \(team) · \(spanSeconds(for: entry))s spell"
        }
        return PressureNarration.headline(for: entry, homeTeamName: homeTeamName, awayTeamName: awayTeamName)
    }

    private func spanSeconds(for entry: PressureEngine.Explained) -> Int {
        let memberIDs = Set(entry.eventIDs)
        let seconds = viewModel.match.passes.filter { memberIDs.contains($0.id) }.map(\.matchSeconds)
        guard let lo = seconds.min(), let hi = seconds.max() else { return 0 }
        return hi - lo
    }

    private func timeLabel(for entry: PressureEngine.Explained) -> String {
        viewModel.match.formattedClock(from: Int(entry.seconds))
    }

    private var homeTeamName: String { viewModel.match.homeTeamName }
    private var awayTeamName: String { viewModel.match.awayTeamName }
}

#Preview {
    PressureLedgerView(viewModel: MatchViewModel())
}
