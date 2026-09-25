import AppKit
import SwiftUI

enum Glyph {
    /// The Hyper Key's mark in plain text.
    static let hyper = "✦"
    /// The Meh Key's mark in plain text.
    static let meh = "☾"

    /// On keycaps and in the menu bar the marks are drawn as SF Symbols, which
    /// stay crisp at every size.
    static func symbol(for glyph: String) -> String? {
        switch glyph {
        case hyper: "sparkle"
        case meh: "moon.fill"
        default: nil
        }
    }
}

/// Each layer key has its own hint of colour: warm amber for ✦, moonlight
/// indigo for ☾. Everything else keeps the system accent.
enum Accent {
    static let hyper = dynamic(light: (0.90, 0.50, 0.00), dark: (1.00, 0.72, 0.30))
    static let meh = dynamic(light: (0.35, 0.33, 0.90), dark: (0.64, 0.64, 1.00))

    static func color(for glyph: String) -> Color? {
        switch glyph {
        case Glyph.hyper: hyper
        case Glyph.meh: meh
        default: nil
        }
    }

    /// The lit face of a held key: a soft top-to-bottom sheen of the accent.
    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)
    }

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        let accent = Accent.color(for: text)
        label
            .foregroundStyle(accent ?? .primary)
            .frame(minWidth: 22)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    if let accent {
                        RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.14))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(accent?.opacity(0.45) ?? Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

extension KeyCap {
    @ViewBuilder private var label: some View {
        if let symbol = Glyph.symbol(for: text) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
        } else {
            // Single keys in the system font, where O and 0 look different;
            // longer labels like "1–9" keep the monospaced keycap look.
            Text(text)
                .font(text.count == 1 ? .system(size: 11.5, weight: .semibold)
                                      : .system(size: 11, weight: .medium, design: .monospaced))
        }
    }
}

/// ✦ O, or a group: ✦ O then P.
struct SequenceCombo: View {
    let label: String
    let then: String?

    var body: some View {
        HStack(spacing: 5) {
            KeyCombo(keys: [Glyph.hyper, label])
            if let then {
                Text("then")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                KeyCap(text: then)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(then.map { "Hyper \(label), then \($0)" } ?? "Hyper \(label)")
    }
}

struct KeyCombo: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Liquid Glass where macOS has it (26 and later), a HUD blur before that.
/// The glass view is looked up at run time, so the app still builds with
/// older SDKs and still runs on macOS 14.
struct GlassBackground: NSViewRepresentable {
    var tint: NSColor?
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if let glass = (NSClassFromString("NSGlassEffectView") as? NSView.Type)?.init() {
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        return blur
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard !(view is NSVisualEffectView) else { return }
        view.setValue(cornerRadius, forKey: "cornerRadius")
        view.setValue(tint, forKey: "tintColor")
    }
}
