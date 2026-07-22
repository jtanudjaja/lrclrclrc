import SwiftUI
import AppKit

/// A small window to set lyrics by hand when LRCLIB doesn't have them:
/// open lrclib.net to browse for the song, then paste the `.lrc` (timed) or
/// plain text here. Applying it persists the override for the current track.
struct FindLyricsView: View {
    @ObservedObject var controller: LyricsController
    @State private var text = ""
    @State private var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Lyrics")
                .font(.headline)

            Text(controller.hasCurrentTrack ? "\(controller.title) — \(controller.artist)" : "Nothing playing")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button("Open lrclib.net") { openLRCLIB() }
                    .disabled(!controller.hasCurrentTrack)
                Text("then paste the .lrc (timed) or plain lyrics below")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3))
                )

            Text("Tip: lines like [00:12.34] Lyric text sync to the song; plain text shows without timing.")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Clear override") {
                    controller.clearManualLyrics()
                    text = ""
                    applied = false
                }
                Spacer()
                if applied {
                    Text("Applied ✓").font(.caption).foregroundColor(.secondary)
                }
                Button("Apply") {
                    controller.applyManualLyrics(text)
                    applied = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.hasCurrentTrack || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 470, height: 400)
    }

    private func openLRCLIB() {
        let query = "\(controller.artist) \(controller.title)".trimmingCharacters(in: .whitespaces)
        guard var comps = URLComponents(string: "https://lrclib.net/") else { return }
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }
}
