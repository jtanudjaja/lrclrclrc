import SwiftUI

/// First-run wizard: welcome → automation permission (only prompts if missing)
/// → player choice (skippable) → done. Progress dots show where you are.
struct OnboardingView: View {
    @ObservedObject var controller: LyricsController
    var onDone: () -> Void

    @State private var step = 0
    private let steps = 4

    var body: some View {
        VStack(spacing: 22) {
            content
                .id(step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)

            progressDots
            navigation
        }
        .padding(28)
        .frame(width: 460)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: permission
        case 2: sourceStep
        default: done
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Welcome to lrclrclrc").font(.title2).bold()
            Text("A floating lyrics overlay for Apple Music and Spotify. It lives in your menu bar — look for the ♫ icon at the top; every option is there.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var permission: some View {
        VStack(spacing: 14) {
            Image(systemName: controller.permissionNeeded ? "lock.shield" : "checkmark.shield.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(controller.permissionNeeded ? .orange : .green)
            Text("Automation Access").font(.title3).bold()
            if controller.permissionNeeded {
                Text("lrclrclrc needs permission to read the current track from your music app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Grant Automation Access") { controller.openAutomationSettings() }
            } else {
                Text("Looks good. macOS will ask the first time a song plays if it still needs permission — just click Allow.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// No "which player do you use?" question any more — we looked. This step
    /// just shows the answer, and lets the user correct it if their copy lives
    /// somewhere we couldn't see.
    private var sourceStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Your music apps").font(.title3).bold()
            Text("These are enabled. You can change it anytime in Preferences.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(controller.sourceStates) { state in
                    Toggle(isOn: Binding(
                        get: { state.isEnabled },
                        set: { controller.setSourceEnabled($0, for: state.kind) }
                    )) {
                        Text(state.isInstalled
                             ? state.kind.displayName
                             : "\(state.kind.displayName) — not found")
                    }
                }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
            Text("You're all set").font(.title2).bold()
            Text("Play a song and the lyrics will appear. Everything lives in the menu-bar ♫ menu.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chrome

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<steps, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var navigation: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            if step == steps - 1 {
                Button("Get Started") { onDone() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
