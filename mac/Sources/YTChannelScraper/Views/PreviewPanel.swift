import AppKit
import SwiftUI

/// Watch a video before deciding to download it — the scraper doubling as a viewer.
///
/// A panel across the full width of the window, at the top of the results with the list
/// carrying on below it. It used to be a card floating over a dimmed page, which meant the
/// list you were picking from was behind glass: to watch the next one you closed the card,
/// found the row and opened another. Here the list stays live underneath, and clicking
/// another video loads it into the same panel.
///
/// Deliberately no `GeometryReader` reading `session`: reads of an `@Observable` inside
/// its content closure land in a different update scope from the view's own body, so
/// `state` changes did not invalidate this view and the stage stayed on its spinner while
/// the player was already running. The available height comes in from the page instead.
struct PreviewPanel: View {
    let session: PreviewSession
    /// The height the results area has; the stage takes at most part of it, so the list
    /// below always keeps a few rows.
    let available: CGFloat
    let download: (Video) -> Void
    let popOut: () -> Void
    /// Keeping what you are watching. Closures rather than the model, to match the rest
    /// of this panel's inputs — it is handed what it can do, not where things live.
    let isSaved: (Video) -> Bool
    let toggleSaved: (Video) -> Void
    /// Every way out of the panel. Not `session.close()` directly: leaving the panel is
    /// not asking for silence, so what is playing goes down to the Now Playing bar.
    let dismiss: () -> Void

    var body: some View {
        // Every observable read happens here, in this view's own body.
        let video = session.video
        let ratio = session.aspectRatio
        let state = session.state

        if let video {
            VStack(spacing: 0) {
                // The stage takes the shape of the stream, so a Short is not letterboxed
                // into a widescreen box and a talk is not cropped into a tall one; the
                // black band behind it is what runs the full width.
                PreviewStage(state: state)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: stageHeight)
                    .frame(maxWidth: .infinity)
                    .background(.black)

                bar(video)
            }
            .background(Palette.sheetSurface)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink(0.12)).frame(height: 1) }
            .onExitCommand(perform: dismiss)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Most of the room, never all of it: below 3/5 of the results area the list keeps
    /// enough rows to pick the next video from.
    private var stageHeight: CGFloat { max(available * 0.6, 220) }

    /// What it is and what to do with it, in one line under the picture so the picture
    /// can have the height.
    ///
    /// The controls are the window's standard 28pt plates, in reading order of how far
    /// each one takes you: keep it, take it elsewhere (YouTube, the notch), then the one
    /// thing this panel is for — Download, the only accent here — and, past a rule, out.
    /// It used to be a bookmark disc, a red pill, two grey capsules and a close disc, five
    /// controls in four shapes.
    private func bar(_ video: Video) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink(1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(video.title)
                Text([video.channelName ?? "", video.durationText, video.viewsText]
                        .filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.ink(0.55))
                    .lineLimit(1)
            }
            // The title is the part that gives way in a narrow window; the buttons keep
            // their labels.
            .layoutPriority(-1)

            Spacer(minLength: 8)

            let saved = isSaved(video)
            Button { toggleSaved(video) } label: {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.chrome(.secondary, square: true, isOn: saved))
            .help(saved ? "Remove from Saved" : "Save this video to your shelf")
            .accessibilityLabel(saved ? "Remove from Saved" : "Save")

            Button { NSWorkspace.shared.open(video.url) } label: {
                Label("YouTube", systemImage: "arrow.up.right")
                    .labelStyle(TrailingIcon())
            }
            .buttonStyle(.chrome())
            .help("Open this video on YouTube, in your browser")

            Button(action: popOut) {
                HStack(spacing: 6) {
                    NotchIcon(width: 14)
                    Text("Notch Player")
                }
            }
            .buttonStyle(.chrome())
            .help("Keep it playing in the notch and put the window away")

            Button {
                download(video)
            } label: {
                Label("Download", systemImage: "arrow.down")
            }
            .buttonStyle(.chrome(.primary))
            .help("Queue this video at the chosen quality; it keeps playing here")

            ChromeSeparator()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.chrome(.ghost, square: true))
            .help("Close the player — it keeps playing in the bar at the bottom  (esc)")
            .accessibilityLabel("Close the player")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 52)
    }
}

/// "YouTube ↗": the arrow says it leaves the app, so it goes after the word, where the
/// eye arrives at it last.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon.font(.system(size: 10, weight: .semibold))
        }
    }
}

/// Its own view, so its read of `session.state` is tracked in its own body.
private struct PreviewStage: View {
    let state: PreviewSession.State

    var body: some View {
        switch state {
        case .working(let stage):
            VStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(Palette.ink(1))
                Text(stage)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let player):
            PlayerView(player: player)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.warn)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }
}
