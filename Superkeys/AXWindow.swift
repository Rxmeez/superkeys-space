import AppKit
import ApplicationServices

struct AXWindow {
    let element: AXUIElement

    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXWindow(element: value as! AXUIElement)
    }

    var windowID: UInt32 {
        var id: UInt32 = 0
        guard let fn = SkyLightBridge.axGetWindow else { return 0 }
        return fn(element, &id) == 0 ? id : 0
    }

    /// Frame in Cocoa coordinates (origin bottom-left).
    var cocoaFrame: CGRect? {
        guard let position = readPoint(kAXPositionAttribute), let size = readSize(kAXSizeAttribute) else { return nil }
        return AXWindow.axToCocoa(CGRect(origin: position, size: size))
    }

    @discardableResult
    func setCocoaFrame(_ frame: CGRect) -> Bool {
        let ax = AXWindow.cocoaToAX(frame)
        var point = ax.origin
        var size = ax.size
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        // Size first so a shrinking window is not clamped by its old extent,
        // then position, then size again for windows that adjust after a move.
        let a = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let b = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue)
        let c = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return a == .success || b == .success || c == .success
    }

    private func readPoint(_ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private func readSize(_ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    // MARK: Coordinates

    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    }

    static func cocoaToAX(_ rect: CGRect) -> CGRect {
        guard let primary = primaryScreen else { return rect }
        return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axToCocoa(_ rect: CGRect) -> CGRect {
        guard let primary = primaryScreen else { return rect }
        return CGRect(x: rect.origin.x, y: primary.frame.maxY - rect.origin.y - rect.height, width: rect.width, height: rect.height)
    }

    /// Screen with the largest intersection with a Cocoa-space frame.
    static func screen(for cocoaFrame: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let i = screen.frame.intersection(cocoaFrame)
            let area = i.isNull ? 0 : i.width * i.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best ?? NSScreen.main
    }
}

/// A window Superkeys can move and resize. Other apps' windows go through the
/// Accessibility API; Superkeys' own go straight through AppKit, because an
/// Accessibility request to our own process would wait on the main thread
/// that is making it.
@MainActor
protocol ManagedWindow {
    var windowID: UInt32 { get }
    var cocoaFrame: CGRect? { get }
    @discardableResult func setCocoaFrame(_ frame: CGRect) -> Bool
}

extension AXWindow: ManagedWindow {}

/// One of Superkeys' own windows, such as Settings.
struct OwnWindow: ManagedWindow {
    let window: NSWindow

    var windowID: UInt32 { UInt32(window.windowNumber) }
    var cocoaFrame: CGRect? { window.frame }

    @discardableResult
    func setCocoaFrame(_ frame: CGRect) -> Bool {
        window.setFrame(frame, display: true)
        // Settings normally fits each tab; once placed it keeps this size.
        (window.windowController as? SettingsWindowController)?.keepCurrentSize()
        return true
    }

    /// Normal, visible, resizable windows. Panels such as the chord sheet are
    /// left alone.
    static func isArrangeable(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && !(window is NSPanel)
            && window.styleMask.contains(.titled) && window.styleMask.contains(.resizable)
            && !window.styleMask.contains(.fullScreen)
    }
}

enum Windows {
    /// The focused window of the frontmost app, whichever app that is.
    @MainActor
    static func focused() -> (any ManagedWindow)? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            return AXWindow.focused()
        }
        guard let key = NSApp.keyWindow ?? NSApp.mainWindow, OwnWindow.isArrangeable(key) else { return nil }
        return OwnWindow(window: key)
    }
}
