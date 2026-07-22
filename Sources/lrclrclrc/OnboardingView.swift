import SwiftUI

/// First-run welcome: explains the menu-bar home and nudges the user to grant
/// Automation permission (the #1 reason the overlay would otherwise sit empty).
struct OnboardingView: View {
    let controller: LyricsController
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)

            Text("Welcome to lrclrclrc")
                .font(.title2).bold()

            Text("A floating lyrics overlay for Apple Music and Spotify. It lives in your menu bar — look for the ♫ icon at the top; every option is there.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                row("play.circle", "Play a song in Apple Music or Spotify.")
                row("rectangle.on.rectangle", "Lyrics appear in a floating card you can drag, resize, and restyle.")
                row("lock.shield", "macOS will ask permission to read the current track — click Allow.")
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                Button("Grant Automation Access") { controller.openAutomationSettings() }
                Button("Get Started") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
