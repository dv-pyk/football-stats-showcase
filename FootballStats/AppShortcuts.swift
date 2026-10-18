import AppIntents

struct FootballStatsShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordPossessionChangeIntent(),
            phrases: [
                "Possession change in \(.applicationName)",
                "Change possession in \(.applicationName)",
                "\(.applicationName) possession"
            ],
            shortTitle: "Possession",
            systemImageName: "arrow.left.arrow.right.circle.fill"
        )
    }
}
