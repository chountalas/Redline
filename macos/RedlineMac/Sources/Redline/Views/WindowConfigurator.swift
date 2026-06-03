import AppKit
import SwiftUI

/// Blends the real macOS window chrome into the design's palette: a transparent titlebar
/// over a theme-colored window so the whole surface reads as one cohesive sheet (matching
/// the prototype's seamless top), and a light/dark chrome appearance that tracks the theme.
struct WindowConfigurator: NSViewRepresentable {
    var background: Color
    var isDark: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(background)
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
