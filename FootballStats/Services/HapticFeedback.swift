import UIKit

enum HapticFeedback {
    static func record() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// A light tick the instant a press-and-hold registers, so the gesture is felt to have
    /// started before its progress fill has visibly moved.
    static func holdStarted() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Fires when a held action actually commits. Deliberately not `record()` — ending the
    /// match shouldn't feel like just another tap.
    static func holdCommitted() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
