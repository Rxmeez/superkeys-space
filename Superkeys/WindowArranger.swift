import AppKit
import ApplicationServices

/// ✦ ↑ lays out the windows on the focused window's screen once: two side by
/// side, three as one large and two stacked, four as quarters. ✦ ⇧ arrow swaps
/// the focused window with its neighbour. Nothing re-arranges on its own.
@MainActor
final class WindowArranger {
    static let shared = WindowArranger()

    enum Direction { case left, right, up, down }

    private static let maxWindows = 4
    private let gap: CGFloat = 8

    /// What the last arrange did, so pressing ✦ ↑ again can undo it.
    private struct Placement {
        let window: AXWindow
        let original: CGRect
        var slot: CGRect
        var placed: CGRect
    }
    private var placements: [UInt32: Placement] = [:]

    // MARK: Arrange

    func arrange() {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return
        }
        // After ⌘W closes an app's last window the app stays in front with
        // nothing focused; arrange the screen under the pointer instead.
        let focused = AXWindow.focused()
        let focusedFrame = focused?.cocoaFrame
        guard let screen = focusedFrame.flatMap(AXWindow.screen(for:)) ?? Self.screenUnderPointer() else { return }

        var windows = Self.windows(on: screen)
        if restoreIfUnchanged(current: windows) { return }

        if let focusedID = focused?.windowID,
           let index = windows.firstIndex(where: { $0.windowID == focusedID }) {
            windows.insert(windows.remove(at: index), at: 0)
        }

        guard !windows.isEmpty else {
            AppState.shared.lastAction = "No windows to arrange"
            return
        }
        guard windows.count <= Self.maxWindows else {
            AppState.shared.lastAction = "Too many windows to arrange (\(windows.count))"
            HyperIndicator.shared.alert(badge: windows.count)
            return
        }

        let vis = screen.visibleFrame
        placements = [:]
        for (window, slot) in zip(windows, slots(count: windows.count, in: vis)) {
            guard let original = window.cocoaFrame else { continue }
            let placed = place(window, in: slot, visible: vis)
            placements[window.windowID] = Placement(window: window, original: original, slot: slot, placed: placed)
        }
        AppState.shared.lastAction = "Arranged \(windows.count) window\(windows.count == 1 ? "" : "s")"
    }

    /// A second ✦ ↑ puts every window back, but only when it is the same set
    /// of windows and none has moved. A window opened or closed since means
    /// the screen changed, so arrange again instead of undoing.
    private func restoreIfUnchanged(current: [AXWindow]) -> Bool {
        guard !placements.isEmpty else { return false }
        let sameWindows = Set(current.map(\.windowID)) == Set(placements.keys)
        let unchanged = sameWindows && placements.values.allSatisfy { p in
            guard let now = p.window.cocoaFrame else { return false }
            return Self.close(now, p.placed)
        }
        defer { placements = [:] }
        guard unchanged else { return false }
        for p in placements.values { p.window.setCocoaFrame(p.original) }
        AppState.shared.lastAction = "Restored"
        return true
    }

    private func slots(count: Int, in vis: CGRect) -> [CGRect] {
        let area = vis.insetBy(dx: gap, dy: gap)
        let half = (area.width - gap) / 2
        let halfHeight = (area.height - gap) / 2
        let left = CGRect(x: area.minX, y: area.minY, width: half, height: area.height)
        let right = CGRect(x: area.maxX - half, y: area.minY, width: half, height: area.height)
        func top(_ column: CGRect) -> CGRect {
            CGRect(x: column.minX, y: area.maxY - halfHeight, width: column.width, height: halfHeight)
        }
        func bottom(_ column: CGRect) -> CGRect {
            CGRect(x: column.minX, y: area.minY, width: column.width, height: halfHeight)
        }
        switch count {
        case 1: return [area]
        case 2: return [left, right]
        case 3: return [left, top(right), bottom(right)]
        default: return [top(left), top(right), bottom(left), bottom(right)]
        }
    }

    /// Sets the frame, then checks what the app accepted. A window with a
    /// minimum size larger than its slot stays pinned to the slot's outer
    /// corner, so it overlaps inwards instead of running off the screen.
    @discardableResult
    private func place(_ window: AXWindow, in slot: CGRect, visible vis: CGRect) -> CGRect {
        window.setCocoaFrame(slot)
        guard let actual = window.cocoaFrame else { return slot }
        guard actual.width > slot.width + 1 || actual.height > slot.height + 1 else { return actual }

        let midX = vis.midX, midY = vis.midY
        var origin = slot.origin
        if actual.width > slot.width + 1, slot.midX > midX { origin.x = slot.maxX - actual.width }
        if actual.height > slot.height + 1, slot.midY >= midY { origin.y = slot.maxY - actual.height }
        origin.x = min(max(origin.x, vis.minX), vis.maxX - actual.width)
        origin.y = min(max(origin.y, vis.minY), vis.maxY - actual.height)
        let adjusted = CGRect(origin: origin, size: actual.size)
        window.setCocoaFrame(adjusted)
        return window.cocoaFrame ?? adjusted
    }

    // MARK: Swap

    func swap(_ direction: Direction) {
        guard Permissions.isTrusted else {
            Permissions.requestAccessibility()
            return
        }
        guard let focused = AXWindow.focused(), let frame = focused.cocoaFrame,
              let screen = AXWindow.screen(for: frame) else {
            AppState.shared.lastAction = "No window focused"
            return
        }
        let focusedID = focused.windowID
        let others = Self.windows(on: screen).filter { $0.windowID != focusedID }
        guard let neighbour = Self.neighbour(of: frame, in: others, toward: direction),
              let neighbourFrame = neighbour.cocoaFrame else {
            AppState.shared.lastAction = "Nothing to swap with"
            return
        }

        // Swap slots when both came from an arrange, so windows with a minimum
        // size don't drag their overlap along; otherwise swap frames.
        let neighbourID = neighbour.windowID
        let vis = screen.visibleFrame
        let a = placements[focusedID]?.slot ?? frame
        let b = placements[neighbourID]?.slot ?? neighbourFrame
        let placedFocused = place(focused, in: b, visible: vis)
        let placedNeighbour = place(neighbour, in: a, visible: vis)
        placements[focusedID]?.slot = b
        placements[focusedID]?.placed = placedFocused
        placements[neighbourID]?.slot = a
        placements[neighbourID]?.placed = placedNeighbour
        AppState.shared.lastAction = "Swapped windows"
    }

    /// The closest window past this one's edge in that direction that shares
    /// some of its span on the other axis. Ties go to the larger overlap, then
    /// to the upper or left-hand window.
    private static func neighbour(of frame: CGRect, in windows: [AXWindow], toward direction: Direction) -> AXWindow? {
        var best: (window: AXWindow, distance: CGFloat, overlap: CGFloat, tiebreak: CGFloat)?
        for window in windows {
            guard let other = window.cocoaFrame else { continue }
            let distance: CGFloat
            let overlap: CGFloat
            let tiebreak: CGFloat
            switch direction {
            case .left, .right:
                guard direction == .left ? other.midX < frame.minX : other.midX > frame.maxX else { continue }
                distance = direction == .left ? frame.minX - other.maxX : other.minX - frame.maxX
                overlap = min(frame.maxY, other.maxY) - max(frame.minY, other.minY)
                tiebreak = -other.maxY
            case .up, .down:
                guard direction == .up ? other.midY > frame.maxY : other.midY < frame.minY else { continue }
                distance = direction == .up ? other.minY - frame.maxY : frame.minY - other.maxY
                overlap = min(frame.maxX, other.maxX) - max(frame.minX, other.minX)
                tiebreak = other.minX
            }
            guard overlap > 0 else { continue }
            let d = max(distance, 0).rounded()
            if let b = best {
                if d > b.distance { continue }
                if d == b.distance {
                    if overlap < b.overlap - 1 { continue }
                    if abs(overlap - b.overlap) <= 1, tiebreak >= b.tiebreak { continue }
                }
            }
            best = (window, d, overlap, tiebreak)
        }
        return best?.window
    }

    // MARK: Finding windows

    /// Standard, resizable, visible windows mostly on this screen and on the
    /// current desktop, front to back.
    private static func windows(on screen: NSScreen) -> [AXWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var order: [(id: UInt32, pid: pid_t)] = []
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = entry[kCGWindowNumber as String] as? UInt32,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 120, bounds.height >= 80 else { continue }
            let cocoa = AXWindow.axToCocoa(bounds)
            guard AXWindow.screen(for: cocoa) == screen else { continue }
            order.append((id, pid))
        }

        var elements: [UInt32: AXWindow] = [:]
        for pid in Set(order.map(\.pid)) {
            for window in AXWindow.windows(of: pid) where window.isArrangeable {
                elements[window.windowID] = window
            }
        }
        return order.compactMap { elements[$0.id] }
    }

    private static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3
            && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }
}

extension AXWindow {
    static func windows(of pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        // An app that has stopped responding shouldn't freeze the chord.
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.map(AXWindow.init(element:))
    }

    /// A normal window that can be moved and resized: not a panel, sheet,
    /// minimised, or full screen.
    var isArrangeable: Bool {
        guard string(kAXSubroleAttribute) == (kAXStandardWindowSubrole as String),
              bool(kAXMinimizedAttribute) != true,
              bool("AXFullScreen") != true else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return true
    }

    private func string(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func bool(_ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
