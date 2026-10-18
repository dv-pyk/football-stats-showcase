import Foundation

enum ActiveMatchCrossProcessNotifier {
    private static let darwinName = "com.footballstats.app.activeMatchUpdated" as CFString
    private static let listenerBox = ListenerBox()

    static func post() {
        NotificationCenter.default.post(name: .activeMatchDidUpdateExternally, object: nil)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName),
            nil,
            nil,
            true
        )
    }

    static func startListening(handler: @escaping @MainActor () -> Void) {
        listenerBox.installIfNeeded(name: darwinName) {
            Task { @MainActor in
                handler()
            }
        }
    }
}

private final class ListenerBox {
    private var listener: DarwinNotificationListener?

    func installIfNeeded(name: CFString, handler: @escaping () -> Void) {
        guard listener == nil else { return }
        listener = DarwinNotificationListener(name: name, handler: handler)
    }
}

private final class DarwinNotificationListener {
    private let name: CFString
    private let handler: () -> Void

    init(name: CFString, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let listener = Unmanaged<DarwinNotificationListener>.fromOpaque(observer).takeUnretainedValue()
                listener.handler()
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
