import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    enum Target { case left, right, full }
    enum Side { case left, right }

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
                guard let next = Self.neighbour(of: screen, toward: side) else {
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

    /// ✦ ⌥ ← / → moves the window to the next display in that direction as it
    /// is: the same size and place relative to the screen, so a snapped half
    /// stays a half.
    func throwWindow(_ side: Side) {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return
        }
        guard let window = Windows.focused(), let current = window.cocoaFrame,
              let screen = AXWindow.screen(for: current) else {
            AppState.shared.lastAction = "No window focused"
            return
        }
        guard let next = Self.neighbour(of: screen, toward: side) else {
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

    /// The nearest display entirely to the left or right of this one, as
    /// arranged in System Settings → Displays. Displays that share some height
    /// win over ones that are only diagonally beside it.
    static func neighbour(of screen: NSScreen, toward side: Side) -> NSScreen? {
        let here = screen.frame
        let candidates = NSScreen.screens.filter { other in
            other != screen && (side == .left ? other.frame.midX < here.minX + 1 : other.frame.midX > here.maxX - 1)
        }
        return candidates.min { a, b in
            func score(_ s: NSScreen) -> (Int, CGFloat) {
                let overlap = min(here.maxY, s.frame.maxY) - max(here.minY, s.frame.minY)
                let distance = side == .left ? here.minX - s.frame.maxX : s.frame.minX - here.maxX
                return (overlap > 0 ? 0 : 1, abs(distance))
            }
            let (sa, sb) = (score(a), score(b))
            return sa.0 != sb.0 ? sa.0 < sb.0 : sa.1 < sb.1
        }
    }

    /// Apps round frames to whole points and some honour a minimum size, so
    /// "already there" allows a little slack.
    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 12 && abs(a.minY - b.minY) < 12
            && abs(a.width - b.width) < 12 && abs(a.height - b.height) < 12
    }
}
