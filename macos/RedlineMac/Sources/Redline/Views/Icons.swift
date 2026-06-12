import SwiftUI

/// Maps the design's named SVG glyphs to the closest SF Symbol so the native UI keeps
/// the same iconography. The prototype draws custom strokes; SF Symbols are the native,
/// crisp equivalent at every size.
enum RLSym {
    static func name(_ design: String) -> String {
        switch design {
        case "check": "checkmark"
        case "x": "xmark"
        case "alert": "exclamationmark.triangle.fill"
        case "info": "info.circle"
        case "spark": "sparkle"
        case "lease": "house"
        case "contract": "doc.text"
        case "search": "magnifyingglass"
        case "plus": "plus"
        case "jump": "arrow.up.right"
        case "export": "square.and.arrow.up"
        case "rerun": "arrow.clockwise"
        case "chev": "chevron.right"
        case "chevl": "chevron.left"
        case "chevd": "chevron.down"
        case "arrow": "arrow.right"
        case "doc": "doc"
        case "tablecells": "tablecells"
        case "tray": "tray.and.arrow.down"
        case "clip": "doc.on.clipboard"
        case "cog": "gearshape"
        case "folder": "rectangle.stack"
        case "gear": "slider.horizontal.3"
        default: "circle"
        }
    }

    static func bucket(_ b: Bucket) -> String {
        switch b {
        case .problem: "xmark"
        case .warn: "exclamationmark.triangle.fill"
        case .note: "info.circle"
        case .ai: "sparkle"
        case .skip: "xmark"
        case .pass, .ok: "checkmark"
        }
    }
}

/// A named design glyph rendered as an SF Symbol.
struct RLIcon: View {
    let design: String
    var size: CGFloat
    var weight: Font.Weight

    init(_ design: String, size: CGFloat = 16, weight: Font.Weight = .semibold) {
        self.design = design
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Image(systemName: RLSym.name(design))
            .font(.system(size: size, weight: weight))
    }
}

/// The severity glyph for a reduced bucket (problem ✕ / warn △ / note ⓘ / ai ✦ / pass ✓).
struct BucketGlyph: View {
    let bucket: Bucket
    var size: CGFloat = 13
    var weight: Font.Weight = .bold

    var body: some View {
        Image(systemName: RLSym.bucket(bucket))
            .font(.system(size: size, weight: weight))
    }
}
