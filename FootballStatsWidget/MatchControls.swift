import AppIntents
import SwiftUI
import WidgetKit

struct RecordPossessionChangeControl: ControlWidget {
    static let kind = "com.footballstats.app.possession"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RecordPossessionChangeIntent()) {
                Label("Possession", systemImage: "arrow.left.arrow.right.circle.fill")
            }
        }
        .displayName("Possession Change")
        .description("Other team now has the ball — throw-in, goal kick, ball out, or any possession change.")
    }
}
