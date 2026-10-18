import Foundation

enum TeamDisplayNames {
    /// Short names for preset teams (see `PresetHomeTeam`), e.g. "Lions U13": "Lions".
    static let presetShortNames: [String: String] = [:]

    static func full(_ name: String) -> String {
        name
    }

    static let maxShortLength = 16

    static func short(_ name: String) -> String {
        if let mapped = presetShortNames[name] {
            return mapped
        }
        if let parsed = parseParentheticalShort(name) {
            return parsed
        }
        if name.count <= maxShortLength {
            return name
        }
        return truncateAtWordBoundary(name, maxLength: maxShortLength)
    }

    static func versusTitle(home: String, away: String) -> String {
        "\(full(home)) vs \(full(away))"
    }

    /// Keeps as many whole words as fit so "Hillside United" stays intact rather than
    /// clipping mid-word to "Hillside Unite". Only a single over-long word is hard-cut.
    private static func truncateAtWordBoundary(_ name: String, maxLength: Int) -> String {
        var kept = ""
        for word in name.split(separator: " ") {
            let candidate = kept.isEmpty ? String(word) : "\(kept) \(word)"
            if candidate.count > maxLength { break }
            kept = candidate
        }
        return kept.isEmpty ? String(name.prefix(maxLength)) : kept
    }

    private static func parseParentheticalShort(_ name: String) -> String? {
        guard let open = name.firstIndex(of: "("),
              let close = name.lastIndex(of: ")"),
              open < close else {
            return nil
        }
        let start = name.index(after: open)
        let short = String(name[start..<close]).trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? nil : short
    }
}
