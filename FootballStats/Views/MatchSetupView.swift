import SwiftUI

struct MatchSetupView: View {
    @ObservedObject var rosterStore: RosterStore
    @State private var homeName: String
    @State private var awayName: String
    @State private var gameFormat: GameFormat
    @State private var kickoffTiming: KickoffTimingMode = .live
    @State private var videoKickoffTime = Date()
    let onStart: (String, String, GameFormat, KickoffTimingMode, Date) -> Void

    init(
        rosterStore: RosterStore,
        homeName: String,
        awayName: String,
        onStart: @escaping (String, String, GameFormat, KickoffTimingMode, Date) -> Void
    ) {
        self.rosterStore = rosterStore
        _homeName = State(initialValue: homeName)
        _awayName = State(initialValue: awayName)
        _gameFormat = State(initialValue: PresetHomeTeam.defaultGameFormat(for: homeName))
        self.onStart = onStart
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Your team") {
                    ForEach(PresetHomeTeam.names, id: \.self) { preset in
                        Button {
                            homeName = preset
                            gameFormat = PresetHomeTeam.defaultGameFormat(for: preset)
                        } label: {
                            HStack {
                                Text(preset)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if homeName == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }

                    HStack {
                        TextField(PresetHomeTeam.names.isEmpty ? "Team name" : "Or type a custom name", text: $homeName)
                            .textInputAutocapitalization(.words)

                        if !homeName.isEmpty {
                            Button {
                                homeName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            // Plain style keeps the tap target on the icon instead of
                            // letting the whole form row swallow it.
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear home team name")
                        }
                    }

                    if !homeName.isEmpty {
                        NavigationLink {
                            RosterEditorView(rosterStore: rosterStore, teamName: homeName)
                        } label: {
                            Text(rosterLinkTitle)
                        }
                    }
                }

                Section("Opposition") {
                    HStack {
                        TextField("Opposition", text: $awayName)
                            .textInputAutocapitalization(.words)

                        if !awayName.isEmpty {
                            Button {
                                awayName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            // Plain style keeps the tap target on the icon instead of
                            // letting the whole form row swallow it.
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear opposition name")
                        }
                    }
                }

                Section {
                    Picker("Format", selection: $gameFormat) {
                        ForEach(GameFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Decides which thresholds \"standout moment\" call-outs use — Futsal runs shorter and scores much faster than Outdoor.")
                }

                Section {
                    Picker("Timing", selection: $kickoffTiming) {
                        ForEach(KickoffTimingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if kickoffTiming == .video {
                        DatePicker("Video replay kickoff", selection: $videoKickoffTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Kickoff")
                } footer: {
                    if kickoffTiming == .live {
                        Text("Goal timestamps use the real time when you tap Start on the match clock.")
                    } else {
                        Text("Goal timestamps follow the video's kickoff time (e.g. 13:01 1-0).")
                    }
                }
            }

            VStack(spacing: 10) {
                Button {
                    onStart(homeName, awayName, gameFormat, kickoffTiming, resolvedKickoffDate)
                } label: {
                    Text("Create Game")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Track goals, shots, passes and possession from the sideline. Finished matches are saved when you hold the End button. View them in History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.bar)
        }
    }

    private var rosterLinkTitle: String {
        guard let count = rosterStore.roster(for: homeName)?.players.count, count > 0 else {
            return "Set up roster"
        }
        return "Roster: \(count) player\(count == 1 ? "" : "s")"
    }

    private var resolvedKickoffDate: Date {
        switch kickoffTiming {
        case .live:
            Date()
        case .video:
            Self.kickoffDate(fromVideoTime: videoKickoffTime)
        }
    }

    private static func kickoffDate(fromVideoTime time: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: 0,
            of: Date()
        ) ?? time
    }
}

#Preview {
    NavigationStack {
        MatchSetupView(rosterStore: RosterStore(), homeName: PresetHomeTeam.defaultName, awayName: "Opposition") { _, _, _, _, _ in }
    }
}
