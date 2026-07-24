// Renders the 1200×630 social-share card referenced by <meta property="og:image">.
// Same material as the site: the page background, the icon's gradient wash, and
// a mock of the overlay card with the current line lit.
// Usage: swift scripts/make-og-image.swift [out.png]   (macOS only)

import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "site/assets/og.png"

let W: CGFloat = 1200
let H: CGFloat = 630

// ───────────────────────────  PALETTE  ───────────────────────────
// Read out of the stylesheet rather than copied into this file. Transcribed
// hexes drift the moment someone retunes the page and doesn't think to grep
// the scripts directory; this way `site/styles.css` is a real input, and the
// workflow that watches it for changes isn't watching it for nothing.

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // scripts/
    .deletingLastPathComponent()   // repo root
let stylesheet = repoRoot.appendingPathComponent("site/styles.css")

let palette: [String: NSColor] = {
    guard let css = try? String(contentsOf: stylesheet, encoding: .utf8) else {
        fatalError("could not read \(stylesheet.path)")
    }
    let pattern = try! NSRegularExpression(
        pattern: "--([a-z0-9-]+)\\s*:\\s*#([0-9a-fA-F]{6})\\b")
    var found: [String: NSColor] = [:]
    let range = NSRange(css.startIndex..., in: css)
    for m in pattern.matches(in: css, range: range) {
        guard let nameR = Range(m.range(at: 1), in: css),
              let hexR = Range(m.range(at: 2), in: css),
              let rgb = Int(css[hexR], radix: 16) else { continue }
        found[String(css[nameR])] = NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
            green:   CGFloat((rgb >> 8) & 0xff) / 255,
            blue:    CGFloat(rgb & 0xff) / 255,
            alpha:   1)
    }
    return found
}()

/// Fails loudly rather than falling back to a placeholder — a card that
/// silently renders in the wrong colour is worse than one that doesn't render.
func token(_ name: String) -> NSColor {
    guard let c = palette[name] else {
        fatalError("--\(name) is not defined in site/styles.css")
    }
    return c
}

let bg        = token("bg")
let ink       = token("ink")
let inkDim    = token("ink-dim")
let inkFaint  = token("ink-faint")
let brandDeep = token("brand-deep")
let brand     = token("brand")
let brandLit  = token("brand-lit")

/// AppKit's origin is bottom-left; the layout below is written top-down.
func fromTop(_ y: CGFloat) -> CGFloat { H - y }

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

/// An elliptical radial wash, matching the page's `radial-gradient(w h at x y)`.
func wash(color: NSColor, at center: NSPoint, w: CGFloat, h: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.scaleX(by: 1, yBy: h / w)
    t.translateX(by: -center.x, yBy: -center.y)
    t.concat()
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: w, options: [])
    NSGraphicsContext.restoreGraphicsState()
}

func draw(_ text: String, at p: NSPoint, size: CGFloat,
          weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: kern,
    ]).draw(at: p)
}

// ───────────────────────────  BACKGROUND  ───────────────────────────

func drawBackground() {
    bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    wash(color: brand.withAlphaComponent(0.42),
         at: NSPoint(x: W * 0.82, y: fromTop(-60)), w: 720, h: 540)
    wash(color: brandLit.withAlphaComponent(0.13),
         at: NSPoint(x: W * 0.02, y: fromTop(20)), w: 560, h: 430)
}

// ───────────────────────────  APP ICON  ───────────────────────────
// The same tile scripts/make-icon.swift renders, drawn inline so the card
// doesn't depend on the PNGs in site/assets.

func drawIconTile(at origin: NSPoint, size: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let rect = NSRect(x: origin.x, y: origin.y, width: size, height: size)
    rounded(rect, size * 0.2237).addClip()

    // --brand-deep / --brand are the stylesheet's note that these two are
    // "straight off the app icon's gradient", so use them and stay in step.
    NSGradient(colors: [brandDeep, brand])!.draw(in: rect, angle: -55)

    let barH = size * 0.085
    let widths: [CGFloat] = [0.40, 0.54, 0.34]
    let alphas: [CGFloat] = [0.5, 1.0, 0.35]
    for i in 0..<3 {
        let w = size * widths[i]
        let y = rect.midY + CGFloat(1 - i) * size * 0.17 - barH / 2
        NSColor(white: 1, alpha: alphas[i]).setFill()
        rounded(NSRect(x: rect.midX - w / 2, y: y, width: w, height: barH), barH / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

// ───────────────────────────  OVERLAY MOCK  ───────────────────────────
// Abstract bars rather than lettering: no lyrics are reproduced anywhere on
// this page, and the shape reads as "lines of text" at thumbnail size anyway.

func drawOverlayCard(in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()

    let card = rounded(rect, 24)
    NSColor(white: 1, alpha: 0.055).setFill()
    card.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(white: 1, alpha: 0.11).setStroke()
    card.lineWidth = 1.5
    card.stroke()

    // A soft top edge, the way a translucent card catches light.
    NSGraphicsContext.saveGraphicsState()
    card.addClip()
    NSGradient(colors: [
        NSColor(white: 1, alpha: 0.07),
        NSColor(white: 1, alpha: 0),
    ])!.draw(in: NSRect(x: rect.minX, y: rect.maxY - 90,
                        width: rect.width, height: 90), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let inset: CGFloat = 34
    let innerW = rect.width - inset * 2
    let rows: [(w: CGFloat, alpha: CGFloat, lit: Bool)] = [
        (0.58, 0.20, false),
        (0.80, 0.32, false),
        (0.92, 1.00, true),
        (0.66, 0.30, false),
        (0.44, 0.18, false),
    ]

    var y = rect.maxY - inset - 24
    for row in rows {
        let h: CGFloat = row.lit ? 20 : 15
        let bar = NSRect(x: rect.minX + inset, y: y - h,
                         width: innerW * row.w, height: h)

        if row.lit {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = brandLit.withAlphaComponent(0.55)
            glow.shadowBlurRadius = 26
            glow.shadowOffset = .zero
            glow.set()
            NSColor(white: 1, alpha: 0.96).setFill()
            rounded(bar, h / 2).fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor(white: 1, alpha: row.alpha).setFill()
            rounded(bar, h / 2).fill()
        }

        y -= row.lit ? 62 : 56
    }
}

// ───────────────────────────  COMPOSITION  ───────────────────────────

func drawCard() {
    drawBackground()

    let margin: CGFloat = 84
    let tile: CGFloat = 76
    let tileTop: CGFloat = 74

    drawIconTile(at: NSPoint(x: margin, y: fromTop(tileTop + tile)), size: tile)
    draw("lrclrclrc",
         at: NSPoint(x: margin + tile + 24, y: fromTop(tileTop + tile - 16)),
         size: 38, weight: .semibold, color: ink, kern: -0.6)

    draw("Lyrics that float",
         at: NSPoint(x: margin, y: fromTop(292)), size: 70, weight: .bold,
         color: ink, kern: -1.6)
    draw("over everything.",
         at: NSPoint(x: margin, y: fromTop(378)), size: 70, weight: .bold,
         color: brandLit, kern: -1.6)

    let sub = NSMutableParagraphStyle()
    sub.lineSpacing = 6
    NSAttributedString(
        string: "Time-synced lyrics for Apple Music and Spotify, in a\ntranslucent card that stays above every app and Space.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 25, weight: .regular),
            .foregroundColor: inkDim,
            .paragraphStyle: sub,
        ]
    ).draw(at: NSPoint(x: margin, y: fromTop(500)))

    draw("macOS  ·  menu bar app  ·  free and open source",
         at: NSPoint(x: margin, y: fromTop(566)),
         size: 19, weight: .medium, color: inkFaint, kern: 0.4)

    drawOverlayCard(in: NSRect(x: 726, y: fromTop(486), width: 392, height: 348))
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not allocate bitmap") }
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
drawCard()
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)  (\(Int(W))×\(Int(H)), \(data.count / 1024) KB)")
