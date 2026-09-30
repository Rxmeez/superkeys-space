import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    enum Target { case left, right, full }
    enum Side { case left, right }
    enum Direction {
        case left, right, up, down
        init(_ side: Side) { self = side == .left ? .left : .right }
    }

    private let gap: CGFloat = 8
    /// Frames to go back to, by window. Closed windows never say so, so this
    /// starts over once it holds more than a few dozen.
    private var previousFrames: [UInt32: CGRect] = [:] {
        didSet {
            if previousFrames.count > 64 { previousFrames = [:]; filled.removeAll() }
        }
    }
    private var filled: Set<UInt32> = []

    /// ✦ ← / → snap to a half; pressed again at the screen's edge, the window
    /// walks onto the neighbouring display's facing half. ✦ ↩ fills, and again
    /// restores the frame it had before, on whichever display that was.
    func snap(_ target: Target) {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return
        }
        guard let window = Windows.focused(), let current = window.cocoaFrame,
              let screen = AXWindow.screen(for: current) else {
            AppState.shared.lastAction = "No window focused"
            return
        }
        let id = window.windowID

        switch target {
        case .full:
            if filled.contains(id), let previous = previousFrames[id] {
                window.setCocoaFrame(previous)
                filled.remove(id)
                previousFrames[id] = nil
                AppState.shared.lastAction = "Restored"
                return
            }
            if previousFrames[id] == nil { previousFrames[id] = current }
            window.setCocoaFrame(frame(for: .full, in: screen.visibleFrame))
            filled.insert(id)
            AppState.shared.lastAction = "Filled screen"

        case .left, .right:
            let side: Side = target == .left ? .left : .right
            filled.remove(id)
            if previousFrames[id] == nil { previousFrames[id] = current }
            // Already on this edge: step onto the next display in that
            // direction, landing on the half that faces this one.
            if Self.close(current, frame(for: target, in: screen.visibleFrame)) {
                guard let next = Self.display(beside: screen, toward: side) else {
                    AppState.shared.lastAction = side == .left ? "Already at the left edge" : "Already at the right edge"
                    return
                }
                let facing: Target = side == .left ? .right : .left
                window.setCocoaFrame(frame(for: facing, in: next.visibleFrame))
                AppState.shared.lastAction = "Moved to \(next.localizedName)"
                return
            }
            window.setCocoaFrame(frame(for: target, in: screen.visibleFrame))
            AppState.shared.lastAction = side == .left ? "Snapped left" : "Snapped right"
        }
    }

    /// ☾ ↩, or an app's own key pressed while it's in front: bring the app's
    /// backmost window forward. Each press rotates the stack, so pressing
    /// again and again visits every window and comes back round. macOS only
    /// lists windows on the desktops showing now, so it cycles those.
    @discardableResult
    func cycleWindows(of app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) -> Bool {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return false
        }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let windows = AXWindow.windows(of: app.processIdentifier).filter(\.isCyclable)
        guard windows.count > 1, let next = windows.last else {
            AppState.shared.lastAction = "Only one \(app.localizedName ?? "") window here"
            return false
        }
        next.raise()
        AppState.shared.lastAction = "Next \(app.localizedName ?? "") window"
        return true
    }

    /// ✦ ⌥ arrow moves the window to the next display in that direction as it
    /// is: the same size and place relative to the screen, so a snapped half
    /// stays a half.
    func throwWindow(_ direction: Direction) {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return
        }
        guard let window = Windows.focused(), let current = window.cocoaFrame,
              let screen = AXWindow.screen(for: current) else {
            AppState.shared.lastAction = "No window focused"
            return
        }
        let next: NSScreen? = switch direction {
        case .left: Self.display(beside: screen, toward: .left)
        case .right: Self.display(beside: screen, toward: .right)
        case .up, .down: Self.neighbour(of: screen, toward: direction)
        }
        guard let next else {
            AppState.shared.lastAction = NSScreen.screens.count < 2 ? "Only one display" : "No display that way"
            return
        }
        let from = screen.visibleFrame, to = next.visibleFrame
        var moved = CGRect(
            x: to.minX + (current.minX - from.minX) / from.width * to.width,
            y: to.minY + (current.minY - from.minY) / from.height * to.height,
            width: current.width / from.width * to.width,
            height: current.height / from.height * to.height)
        moved = moved.intersection(to).isNull ? CGRect(origin: to.origin, size: moved.size) : moved
        window.setCocoaFrame(moved)
        filled.remove(window.windowID)
        AppState.shared.lastAction = "Moved to \(next.localizedName)"
    }

    private func frame(for target: Target, in vis: CGRect) -> CGRect {
        switch target {
        case .left:
            return CGRect(x: vis.minX + gap, y: vis.minY + gap, width: vis.width / 2 - gap * 1.5, height: vis.height - gap * 2)
        case .right:
            return CGRect(x: vis.midX + gap * 0.5, y: vis.minY + gap, width: vis.width / 2 - gap * 1.5, height: vis.height - gap * 2)
        case .full:
            return vis.insetBy(dx: gap, dy: gap)
        }
    }

    /// The display ← / → reach: the nearest one to that side, or, when none
    /// is, the nearest one stacked above or below, so displays arranged on
    /// top of each other are still a key away.
    static func display(beside screen: NSScreen, toward side: Side) -> NSScreen? {
        if let next = neighbour(of: screen, toward: Direction(side)) { return next }
        let frames = NSScreen.screens.map(\.frame)
        let stacked = [Direction.up, .down].compactMap { neighbour(of: screen.frame, among: frames, toward: $0) }
        let nearest = stacked.min { a, b in
            gap(screen.frame, frames[a]) < gap(screen.frame, frames[b])
        }
        return nearest.map { NSScreen.screens[$0] }
    }

    static func neighbour(of screen: NSScreen, toward direction: Direction) -> NSScreen? {
        neighbour(of: screen.frame, among: NSScreen.screens.map(\.frame), toward: direction)
            .map { NSScreen.screens[$0] }
    }

    /// The nearest display entirely in that direction from this one, as
    /// arranged in System Settings → Displays, by index into `displays`.
    /// Displays that line up with it win over ones only diagonally beside it.
    /// Frames are Cocoa's, so up is +y.
    static func neighbour(of here: CGRect, among displays: [CGRect], toward direction: Direction) -> Int? {
        let candidates = displays.indices.filter { i in
            let other = displays[i]
            guard other != here else { return false }
            switch direction {
            case .left: return other.midX < here.minX + 1
            case .right: return other.midX > here.maxX - 1
            case .down: return other.midY < here.minY + 1
            case .up: return other.midY > here.maxY - 1
            }
        }
        func score(_ i: Int) -> (Int, CGFloat) {
            let other = displays[i]
            let overlap = direction == .left || direction == .right
                ? min(here.maxY, other.maxY) - max(here.minY, other.minY)
                : min(here.maxX, other.maxX) - max(here.minX, other.minX)
            return (overlap > 0 ? 0 : 1, gap(here, other))
        }
        return candidates.min { score($0) < score($1) }
    }

    /// Distance between two displays' facing edges, or 0 where they touch.
    private static func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, a.minX - b.maxX, b.minX - a.maxX) + max(0, a.minY - b.maxY, b.minY - a.maxY)
    }

    /// Apps round frames to whole points and some honour a minimum size, so
    /// "already there" allows a little slack.
    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 12 && abs(a.minY - b.minY) < 12
            && abs(a.width - b.width) < 12 && abs(a.height - b.height) < 12
    }
}
