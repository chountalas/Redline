import AppKit
import SwiftUI

// MARK: - Color helpers
//
// The v2 design system is built on CSS custom properties and `color-mix(in srgb, …)`.
// SwiftUI has no color-mix, so we replicate it: a straight component-wise lerp in the
// sRGB space (CSS mixes the gamma-encoded coordinates, not linearized ones).

extension Color {
    /// Build a Color from a `#rrggbb` hex string (the form used throughout the design CSS).
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// `color-mix(in srgb, a percent%, b)` — `a` contributes `percent`, `b` the remainder.
func rlMix(_ a: Color, _ b: Color, _ percent: Double) -> Color {
    let t = max(0, min(1, percent))
    let na = NSColor(a).usingColorSpace(.sRGB) ?? .black
    let nb = NSColor(b).usingColorSpace(.sRGB) ?? .black
    return Color(
        .sRGB,
        red: Double(na.redComponent) * t + Double(nb.redComponent) * (1 - t),
        green: Double(na.greenComponent) * t + Double(nb.greenComponent) * (1 - t),
        blue: Double(na.blueComponent) * t + Double(nb.blueComponent) * (1 - t),
        opacity: Double(na.alphaComponent) * t + Double(nb.alphaComponent) * (1 - t)
    )
}

// MARK: - Theme

/// The full `.rl2` palette + type system, resolved for one (theme, accent, doc-size).
/// Mirrors the `:root` custom properties in `Redline v2.html` so the native UI matches
/// the prototype token-for-token. Accent is decoupled from semantic error-red: changing
/// the accent never turns a "problem" finding non-red (the decoupling the user asked for).
struct RLTheme: Equatable {
    var isDark: Bool
    var accent: Color
    var docSize: CGFloat

    init(isDark: Bool = false, accent: Color = Color(hex: "#c8302b"), docSize: CGFloat = 16) {
        self.isDark = isDark
        self.accent = accent
        self.docSize = docSize
    }

    // ── surfaces ────────────────────────────────────────────────────────────
    var bg: Color { isDark ? Color(hex: "#0a0b0e") : Color(hex: "#e7e2d6") }
    var win: Color { isDark ? Color(hex: "#15171d") : Color(hex: "#faf8f2") }
    var rail: Color { isDark ? Color(hex: "#121319") : Color(hex: "#f2efe7") }
    var surface: Color { isDark ? Color(hex: "#1b1e25") : Color(hex: "#ffffff") }
    var surface2: Color { isDark ? Color(hex: "#23262f") : Color(hex: "#f4f1e9") }
    var docBG: Color { isDark ? Color(hex: "#171a20") : Color(hex: "#faf8f1") }

    // ── ink (text) ──────────────────────────────────────────────────────────
    var ink: Color { isDark ? Color(hex: "#eef0f5") : Color(hex: "#211f1b") }
    var ink2: Color { isDark ? Color(hex: "#a8aebb") : Color(hex: "#6a655c") }
    var ink3: Color { isDark ? Color(hex: "#6f7685") : Color(hex: "#a59f92") }
    var ink4: Color { isDark ? Color(hex: "#535a68") : Color(hex: "#bcb6a8") }

    // ── lines ───────────────────────────────────────────────────────────────
    var line: Color { isDark ? Color(hex: "#262a32") : Color(hex: "#ece7da") }
    var line2: Color { isDark ? Color(hex: "#333845") : Color(hex: "#ddd7c8") }

    // ── semantic severities ─────────────────────────────────────────────────
    var problem: Color { isDark ? Color(hex: "#ef5a50") : Color(hex: "#c8302b") }
    var warn: Color { isDark ? Color(hex: "#e0a341") : Color(hex: "#a86a10") }
    var note: Color { isDark ? Color(hex: "#5ba2e2") : Color(hex: "#2f6aa8") }
    var ok: Color { isDark ? Color(hex: "#34c98b") : Color(hex: "#1f8a5b") }
    var ai: Color { isDark ? Color(hex: "#b08ce8") : Color(hex: "#7a55bf") }
    var skip: Color { isDark ? Color(hex: "#79839a") : Color(hex: "#9b958a") }

    // ── soft tints: color-mix(in srgb, <sev> N%, win) ───────────────────────
    var problemSoft: Color { rlMix(problem, win, 0.12) }
    var warnSoft: Color { rlMix(warn, win, 0.14) }
    var noteSoft: Color { rlMix(note, win, 0.13) }
    var okSoft: Color { rlMix(ok, win, 0.13) }
    var aiSoft: Color { rlMix(ai, win, 0.12) }

    // ── window drop shadow (matches --shadow) ───────────────────────────────
    var shadowColor: Color { isDark ? Color.black.opacity(0.7) : Color(hex: "#281e12").opacity(0.42) }

    // MARK: bucket lookups

    func color(_ bucket: Bucket) -> Color {
        switch bucket {
        case .problem: problem
        case .warn: warn
        case .note: note
        case .ok, .pass: ok
        case .ai: ai
        case .skip: skip
        }
    }

    func softColor(_ bucket: Bucket) -> Color {
        switch bucket {
        case .problem: problemSoft
        case .warn: warnSoft
        case .note: noteSoft
        case .ok, .pass: okSoft
        case .ai: aiSoft
        case .skip: rlMix(skip, win, 0.12)
        }
    }

    // MARK: fonts
    //
    // Public Sans → SF Pro (system, .default) · Newsreader → New York (.serif) ·
    // IBM Plex Mono → SF Mono (.monospaced). The native equivalents are the closest
    // legible match without bundling web-font binaries.

    func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Environment plumbing

private struct RLThemeKey: EnvironmentKey {
    static let defaultValue = RLTheme()
}

extension EnvironmentValues {
    var rl: RLTheme {
        get { self[RLThemeKey.self] }
        set { self[RLThemeKey.self] = newValue }
    }
}
