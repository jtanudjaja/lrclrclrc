import Foundation

/// One lyric line. `time == nil` means unsynced (plain lyrics).
struct LrcLine {
    let time: Double?
    let text: String
}

/// Parses an `.lrc` string into sorted, timestamped lines. Handles lines that
/// carry several timestamps, e.g. `[00:15.00][01:02.50] repeated line`.
enum LRCParser {
    private static let tag = try? NSRegularExpression(
        pattern: "\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
    )

    static func parse(_ lrc: String) -> [LrcLine] {
        guard let tag else { return [] }
        var out: [LrcLine] = []

        for rawLine in lrc.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let full = NSRange(location: 0, length: ns.length)
            let matches = tag.matches(in: rawLine, range: full)
            if matches.isEmpty { continue } // metadata like [ar:...] or a blank line

            var stamps: [Double] = []
            for m in matches {
                let minute = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let second = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                let fracRange = m.range(at: 3)
                if fracRange.location != NSNotFound {
                    let f = ns.substring(with: fracRange)
                    frac = (Double(f) ?? 0) / pow(10.0, Double(f.count))
                }
                stamps.append(minute * 60 + second + frac)
            }

            let text = tag
                .stringByReplacingMatches(in: rawLine, range: full, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)

            for t in stamps { out.append(LrcLine(time: t, text: text)) }
        }

        out.sort { ($0.time ?? 0) < ($1.time ?? 0) }
        return out
    }
}
