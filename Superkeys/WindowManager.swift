import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    enum Target { case left, right, full }

    private let gap: CGFloat = 8
    private var previousFrames: [UInt32: CGRect] = [:]
    private var lastSnap: [UInt32: Target] = [:]

    func snap(_ target: Target) {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return
        }
        guard let window = AXWindow.focused(), let current = window.cocoaFrame else {
            AppState.shared.lastAction = "No window focused"
            return
        }
        guard let screen = AXWindow.screen(for: current) else { return }

        let id = window.windowID
        if lastSnap[id] == target, let previous = previousFrames[id] {
            window.setCocoaFrame(previous)
            lastSnap[id] = nil
            previousFrames[id] = nil
            AppState.shared.lastAction = "Restored"
            return
        }

        if lastSnap[id] == nil {
            previousFrames[id] = current
        }
        window.setCocoaFrame(frame(for: target, in: screen.visibleFrame))
        lastSnap[id] = target

        switch target {
        case .left: AppState.shared.lastAction = "Snapped left"
        case .right: AppState.shared.lastAction = "Snapped right"
        case .full: AppState.shared.lastAction = "Filled screen"
        }
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
}
