import SwiftUI
import UIKit

// Offscreen harness: renders the share image from a real exported backup, so layout and
// pressure-index changes are judged against data the app actually produced. It replaced
// a synthetic generator that emitted no pass taps at all — a recording style that turned
// out never to occur in practice, which quietly invalidated any calibration tuned on it.
//
//   render <backup.json> <output.png> [opponent substring]
//
// With no opponent given it takes the most recently saved match.

let arguments = Array(CommandLine.arguments.dropFirst())

guard arguments.count >= 2 else {
    FileHandle.standardError.write(
        Data("usage: render <backup.json> <output.png> [opponent substring]\n".utf8)
    )
    exit(2)
}

let backupPath = arguments[0]
let outputPath = arguments[1]
let opponentFilter = arguments.count > 2 ? arguments[2].lowercased() : nil

guard let data = FileManager.default.contents(atPath: backupPath) else {
    FileHandle.standardError.write(Data("could not read \(backupPath)\n".utf8))
    exit(1)
}

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let saved: [SavedMatch]
do {
    saved = try decoder.decode([SavedMatch].self, from: data)
} catch {
    FileHandle.standardError.write(Data("could not decode backup: \(error)\n".utf8))
    exit(1)
}

let candidates = saved.sorted { $0.savedAt > $1.savedAt }
let chosen: SavedMatch? = {
    guard let opponentFilter else { return candidates.first }
    return candidates.first { $0.match.awayTeamName.lowercased().contains(opponentFilter) }
}()

guard let selected = chosen else {
    FileHandle.standardError.write(Data("no match found in \(backupPath)\n".utf8))
    exit(1)
}

let match = selected.match

func describe(_ match: MatchState) {
    let passCounts = Dictionary(grouping: match.passes, by: \.type)
        .mapValues(\.count)
        .sorted { $0.value > $1.value }

    print("\(match.homeTeamName) vs \(match.awayTeamName)")
    print("  saved \(selected.savedAt), \(match.elapsedSeconds)s elapsed, \(match.kickoffTimingMode.label) kickoff")
    print("  score \(match.score(for: .home))-\(match.score(for: .away)) from \(match.shots.count) shots and \(match.passes.count) taps")
    print("  taps: " + passCounts.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", "))

    let spells = PressureEngine.possessionSpells(for: match)
    let lengths = spells.map { $0.end - $0.start }.sorted()
    let median = lengths.isEmpty ? 0 : lengths[lengths.count / 2]
    let stealWindow = PressureWeight.inferredStealWindowSeconds(rulesVersion: match.rulesVersion)
    let steals = PressureEngine.inferredSteals(in: match.passes, stealWindowSeconds: stealWindow)
    let homeSteals = steals.filter { $0.team == .home }.count
    let awaySteals = steals.filter { $0.team == .away }.count
    print("  \(spells.count) possession spells, median \(median)s")
    print("  inferred steals: \(steals.count) (home \(homeSteals), away \(awaySteals), window \(stealWindow)s)")

    let possession = PressureEngine.possessionPercentages(for: match)
    print("  possession \(possession.home)% / \(possession.away)%")
}

describe(match)

let pressureEvents = PressureEngine.events(from: match)
print("pressure around each goal (T-10 / T / T+10 / T+30 / T+60):")
for goal in match.goals {
    let samples = [-10, 0, 10, 30, 60].map { offset in
        String(format: "%+5.1f", PressureEngine.value(at: goal.matchSeconds + offset, events: pressureEvents))
    }
    let scorer = goal.team == .home ? "home" : "away"
    print("  \(scorer) goal \(goal.matchSeconds / 60)':  \(samples.joined(separator: "  "))")
}

MainActor.assumeIsolated {
    let image = PossessionChartRenderer.image(
        points: PressureEngine.chartPoints(for: match),
        goalMarkers: PressureEngine.goalMarkers(for: match),
        shotTicks: PressureEngine.shotTicks(for: match),
        goalsStat: PressureEngine.goalsStat(for: match),
        possessionStat: PressureEngine.possessionStat(for: match),
        comparisonStats: PressureEngine.comparisonStats(for: match),
        homeName: match.homeTeamName,
        awayName: match.awayTeamName
    )

    guard let png = image?.pngData() else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }

    do {
        try png.write(to: URL(fileURLWithPath: outputPath))
        print("wrote \(png.count) bytes to \(outputPath)")
        for stat in [PressureEngine.goalsStat(for: match), PressureEngine.possessionStat(for: match)]
            + PressureEngine.comparisonStats(for: match) {
            print("  \(stat.homeText) | \(stat.label) | \(stat.awayText)")
        }

        print("observations:")
        for line in MatchObservationEngine.observations(for: match, ourTeam: .home) {
            print("  - \(line)")
        }
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
}
