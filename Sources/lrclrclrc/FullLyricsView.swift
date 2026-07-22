import SwiftUI

/// The whole song's lyrics, scrollable, with the current line highlighted and
/// auto-scrolled into view. Click a timed line to seek playback there.
struct FullLyricsView: View {
    @ObservedObject var controller: LyricsController

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if controller.allLines.isEmpty {
                Spacer()
                Text("No lyrics for this track")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                lyricsList
            }
        }
        .frame(minWidth: 360, minHeight: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(controller.title)
                .font(.headline)
                .lineLimit(1)
            Text(controller.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var lyricsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(controller.allLines.enumerated()), id: \.offset) { index, line in
                        let isCurrent = index == controller.currentLineIndex
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 16, weight: isCurrent ? .bold : .regular))
                            .foregroundStyle(isCurrent ? Color.primary : Color.secondary.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let time = line.time { controller.seek(to: time) }
                            }
                            .id(index)
                    }
                }
                .padding(16)
            }
            .onChange(of: controller.currentLineIndex) { index in
                guard index >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}
