import AppKit
import Combine
import ServiceManagement

/// Live Hyper and Meh Key state, kept apart from AppState so a key press only
/// re-renders the views that draw it.
@MainActor
final class HyperIndicator: ObservableObject {
    static let shared = HyperIndicator()
    @Published var held = false
    @Published var meh = false

    /// A quiet "that didn't work" on the menu bar icon: it turns red, shakes
    /// once, and shows a number badge for a moment. Used when ✦ ↑ finds more
    /// windows than it can arrange.
    @Published private(set) var alertBadge: Int?
    @Published private(set) var shakeOffset: CGFloat = 0
    private var alertTask: Task<Void, Never>?

    func alert(badge: Int) {
        alertTask?.cancel()
        alertBadge = badge
        alertTask = Task { @MainActor [weak self] in
            for x: CGFloat in [-3, 3, -2.5, 2.5, -1.5, 1.5, 0] {
                guard !Task.isCancelled else { return }
                self?.shakeOffset = x
                try? await Task.sleep(for: .milliseconds(40))
            }
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            self?.alertBadge = nil
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Status: Equatable {
        case on, paused, needsAccess, unavailable
    }

    @Published var lastAction = ""
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var tapRunning = false
    @Published private(set) var desktopShortcutsEnabled = false
    /// More than one display, and whether each has its own desktops.
    @Published private(set) var multipleDisplays = false
    @Published private(set) var separateSpaces = true
    @Published private(set) var launchAtLogin = false
    @Published private(set) var paused = false

    private static let cheatSheetKey = "showCheatSheet"
    @Published var showCheatSheet = UserDefaults.standard.object(forKey: cheatSheetKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showCheatSheet, forKey: Self.cheatSheetKey)
            if !showCheatSheet { CheatSheet.shared.dismiss() }
        }
    }

    var status: Status {
        if paused { return .paused }
        if !accessibilityTrusted { return .needsAccess }
        return tapRunning ? .on : .unavailable
    }

    private var retryTimer: Timer?
    private var requestedInputMonitoring = false
    private var observers: [NSObjectProtocol] = []

    func bootstrap() {
        _ = BindingsStore.shared
        MissionControlShortcuts.enable()
        SpaceManager.shared.trackDesktops()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if !Permissions.isTrusted { Permissions.requestAccessibility() }
        reconcile()
        observe()
    }

    /// Brings the event tap in line with permissions and the pause switch.
    func reconcile() {
        let trusted = Permissions.isTrusted
        if trusted && !paused && !HyperEventTap.shared.isRunning,
           !HyperEventTap.shared.start(), !requestedInputMonitoring {
            // Some Macs also want Input Monitoring before a tap can be created.
            requestedInputMonitoring = true
            Permissions.requestInputMonitoring()
        }
        update(\.accessibilityTrusted, trusted)
        update(\.tapRunning, HyperEventTap.shared.isRunning)
        update(\.desktopShortcutsEnabled, MissionControlShortcuts.allEnabled)
        update(\.multipleDisplays, NSScreen.screens.count > 1)
        update(\.separateSpaces, SpaceManager.displaysHaveSeparateSpaces)
        scheduleRetry()
    }

    /// Nothing changes on its own once the Hyper Key is running, so the timer
    /// only exists while waiting for the user to grant access.
    private func scheduleRetry() {
        let waiting = !paused && !(accessibilityTrusted && tapRunning)
        if !waiting {
            retryTimer?.invalidate()
            retryTimer = nil
        } else if retryTimer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in AppState.shared.pollAccess() }
            }
            // Lets macOS batch this with other wakeups instead of firing on the dot.
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            retryTimer = timer
        }
    }

    /// The accessibility notification normally triggers `reconcile()`. This is
    /// the fallback, and only runs the full check when something it can see
    /// has changed; a full pass costs several cross-process calls.
    private func pollAccess() {
        let trusted = Permissions.isTrusted
        if trusted != accessibilityTrusted || (trusted && !tapRunning) {
            reconcile()
        }
    }

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppState.shared.reconcile() }
        })
        // Plugging a display in or out changes which desktops ☾ can reach.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                AppState.shared.reconcile()
                SpaceManager.shared.trackDesktops()
            }
        })
        // Posted system-wide whenever any app's Accessibility access changes.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                AppState.shared.reconcile()
            }
        })
    }

    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        if value { HyperEventTap.shared.stop() }
        lastAction = ""
        reconcile()
    }

    func restart() {
        HyperEventTap.shared.stop()
        reconcile()
    }

    func shutdown() {
        retryTimer?.invalidate()
        HyperEventTap.shared.stop()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastAction = "Could not change login item"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Publishing an unchanged value still invalidates every observing view.
    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
