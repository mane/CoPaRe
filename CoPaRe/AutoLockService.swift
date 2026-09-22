import AppKit
import Combine

/// Observes only this app's input and documented workspace events. No global
/// event tap, Accessibility permission, or private screen-lock notification.
@MainActor
final class AutoLockService {
    enum Reason { case inactivity, focusLoss, system }
    private let settings: SettingsStore
    private let requestLock: (Reason) -> Void
    private let now: () -> Date
    private var lastActivity: Date
    private var eventMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?

    init(settings: SettingsStore, now: @escaping () -> Date = Date.init, requestLock: @escaping (Reason) -> Void) {
        self.settings = settings
        self.now = now
        self.requestLock = requestLock
        lastActivity = now()
    }

    func start() {
        guard timer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.systemBecameUnavailable()
            }.store(in: &subscriptions)
        }
        // Focus loss also protects a visible CoPaRe window when the system lock
        // screen takes focus; it doesn't rely on undocumented distributed names.
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.systemBecameUnavailable(reason: .focusLoss)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.recordActivity()
            }.store(in: &subscriptions)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            self?.recordActivity()
            return event
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkInactivity() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func recordActivity() { lastActivity = now() }

    func checkInactivity() {
        guard settings.lockProtectionEnabled, let interval = settings.autoLockInterval.interval,
              now().timeIntervalSince(lastActivity) >= interval else { return }
        requestLock(.inactivity)
    }

    func systemBecameUnavailable(reason: Reason = .system) {
        guard settings.lockProtectionEnabled, settings.lockOnSystemEvents else { return }
        requestLock(reason)
    }

    isolated deinit {
        timer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
