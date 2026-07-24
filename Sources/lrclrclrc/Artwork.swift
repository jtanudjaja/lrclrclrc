import AppKit
import ImageIO

/// Album art decoding, kept deliberately separate from AppKit's `NSImage(data:)`.
///
/// Two reasons. It runs on a background queue (the poll queue for Apple Music's
/// raw bytes, a URLSession callback for Spotify's URL), and ImageIO is the part
/// of the stack that is documented as thread-safe — `NSImage`'s lazy decode is
/// not something to lean on off the main thread. And it *validates*: the
/// artwork payload comes back from AppleScript as an untyped descriptor, so the
/// bytes could be an old PICT wrapper, an error string coerced to data, or
/// nothing at all. `CGImageSourceCreateThumbnailAtIndex` either produces a real
/// image or it doesn't, which is exactly the check we'd otherwise have to
/// hand-write around a format sniff.
///
/// The thumbnail is also the whole point: the tile renders at 26pt, and holding
/// a decoded 1400×1400 cover for it would be several megabytes per track for
/// something the user sees at postage-stamp size.
enum Artwork {
    /// Longest edge of the decoded tile, in pixels. The tile draws at 26pt ×
    /// fontScale; 192 covers a 2× display at the largest text size with room
    /// spare, and it's small enough that the decode is imperceptible.
    static let maxPixel = 192

    /// Decode image bytes to a small tile, or nil if they aren't an image.
    static func thumbnail(from data: Data) -> NSImage? {
        guard data.count > 128,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
