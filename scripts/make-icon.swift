// Renders the app icon (a gradient tile with three "lyric bars", the middle
// one highlighted) and packages it into an .icns via iconutil.
// Usage: swift scripts/make-icon.swift [out.icns]   (macOS only)

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.icns"

func drawIcon(_ size: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.2237 // macOS squircle-ish
    NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).addClip()

    let gradient = NSGradient(colors: [
        NSColor(red: 0.11, green: 0.13, blue: 0.20, alpha: 1),
        NSColor(red: 0.20, green: 0.44, blue: 0.82, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -55)

    let barHeight = size * 0.085
    let radius = barHeight / 2
    let centerX = size * 0.5
    let centerY = size * 0.5
    let spacing = size * 0.17
    let widths: [CGFloat] = [0.40, 0.54, 0.34]
    let alphas: [CGFloat] = [0.5, 1.0, 0.35]

    for i in 0..<3 {
        let w = size * widths[i]
        let y = centerY + CGFloat(1 - i) * spacing - barHeight / 2
        let barRect = NSRect(x: centerX - w / 2, y: y, width: w, height: barHeight)
        NSColor(white: 1, alpha: alphas[i]).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()
    }
}

func pngData(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "lrclrclrc.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    if let data = pngData(px) {
        try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    }
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset, "-o", outPath]
try proc.run()
proc.waitUntilExit()
print("wrote \(outPath)")
