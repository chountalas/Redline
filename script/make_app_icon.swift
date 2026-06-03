#!/usr/bin/env swift
//
// make_app_icon.swift — generates Redline's macOS app icon from the design tokens.
//
// The icon mirrors `Theme.swift`: warm-paper surfaces, near-black ink "text", and the
// signature redline red (#c8302b) struck through a line of copy — the literal edit the
// app performs. Drawn with CoreGraphics so it stays token-for-token in sync with the UI.
//
//   usage:  swift script/make_app_icon.swift <out.icns>
//
// Re-renders every iconset size natively (not a downscale of one master) so the red
// strike stays crisp at 16px. Shells out to `iconutil` to pack the final .icns.

import AppKit
import Foundation

// MARK: - Tokens (kept identical to Sources/Redline/Design/Theme.swift, light theme)

func hex(_ s: String, _ a: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                   green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255,
                   alpha: a)
}

let paperTop = hex("#fdfbf6")   // lighter than --win, gives the tile a soft top-down warmth
let paperBot = hex("#efe9db")   // a touch deeper than --surface2 at the foot
let border   = hex("#e4decf")   // hairline, between --line and --line2
let heading  = hex("#6a655c")   // --ink2: the "title" row reads darker
let bodyInk  = hex("#a59f92")   // --ink3: muted body "text"
let redline  = hex("#c8302b")   // --accent / --problem: the hero strike
let shadow   = hex("#281e12")   // --shadow base

// MARK: - Layout (reference space is 1024×1024; the "iterate here" surface)

let REF: CGFloat = 1024
let tileInset: CGFloat = 100              // transparent margin → 824 tile on the macOS grid
let tileRadius: CGFloat = 185             // ≈ 22.4% of 824, Apple's rounded-tile proportion

// Document body: ragged-right rows of pill "text", one struck through in red.
let contentInset: CGFloat = 150           // left/right padding from the tile edge
let rowPitch: CGFloat = 80
let bodyThick: CGFloat = 26
let headThick: CGFloat = 36
let strikeThick: CGFloat = 32
let strikeOverhang: CGFloat = 42          // the red mark runs past the text on both ends

// rows top→bottom: (widthFraction, thickness, color, isStruck)
struct Row { let w: CGFloat; let t: CGFloat; let c: NSColor; let struck: Bool }
let rows: [Row] = [
    Row(w: 0.50, t: headThick, c: heading, struck: false),  // heading
    Row(w: 0.92, t: bodyThick, c: bodyInk, struck: false),
    Row(w: 0.80, t: bodyThick, c: bodyInk, struck: true),    // ← redlined line
    Row(w: 0.60, t: bodyThick, c: bodyInk, struck: false),
    Row(w: 0.88, t: bodyThick, c: bodyInk, struck: false),
    Row(w: 0.68, t: bodyThick, c: bodyInk, struck: false),
]

// MARK: - Drawing

func pill(_ rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
}

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high

    let f = CGFloat(px) / REF                       // scale every reference coordinate
    func s(_ v: CGFloat) -> CGFloat { v * f }

    // Tile geometry (CoreGraphics origin is bottom-left).
    let tile = NSRect(x: s(tileInset), y: s(tileInset),
                      width: s(REF - 2 * tileInset), height: s(REF - 2 * tileInset))
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s(tileRadius), yRadius: s(tileRadius))

    // 1 — baked floating shadow (fill once with the foot color, casting a soft shadow).
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = shadow.withAlphaComponent(0.26)
    sh.shadowBlurRadius = s(34)
    sh.shadowOffset = NSSize(width: 0, height: s(-18))
    sh.set()
    paperBot.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 2 — warm vertical paper gradient (clipped to the tile, no shadow).
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(starting: paperBot, ending: paperTop)?.draw(in: tile, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // 3 — hairline border for a crisp edge (matches the app's 1px surface lines).
    border.setStroke()
    tilePath.lineWidth = s(2)
    tilePath.stroke()

    // 4 — document rows, vertically centered as a block.
    let n = CGFloat(rows.count)
    let blockH = (n - 1) * rowPitch
    let topCenterY = REF / 2 + blockH / 2            // first row sits at the top of the block
    let xLeft = tileInset + contentInset
    let contentW = REF - 2 * (tileInset + contentInset)

    for (i, row) in rows.enumerated() {
        let cy = topCenterY - CGFloat(i) * rowPitch
        let w = contentW * row.w
        let bar = NSRect(x: s(xLeft), y: s(cy - row.t / 2), width: s(w), height: s(row.t))
        row.c.setFill()
        pill(bar).fill()

        if row.struck {
            let len = w + 2 * strikeOverhang
            let strike = NSRect(x: s(xLeft - strikeOverhang), y: s(cy - strikeThick / 2),
                                width: s(len), height: s(strikeThick))
            redline.setFill()
            pill(strike).fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Emit the iconset, then pack with iconutil

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift make_app_icon.swift <out.icns>\n".data(using: .utf8)!)
    exit(2)
}
let outIcns = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = outIcns.deletingPathExtension().appendingPathExtension("iconset")

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (pixelSize, filenames) — several sizes serve both @1x and the next size's @2x.
let plan: [(Int, [String])] = [
    (16,  ["icon_16x16.png"]),
    (32,  ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64,  ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024,["icon_512x512@2x.png"]),
]

for (px, names) in plan {
    let data = render(px: px).representation(using: .png, properties: [:])!
    for name in names { try data.write(to: iconset.appendingPathComponent(name)) }
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", outIcns.path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { exit(p.terminationStatus) }

FileHandle.standardOutput.write("wrote \(outIcns.path)\n".data(using: .utf8)!)
