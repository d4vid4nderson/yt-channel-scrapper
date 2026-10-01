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
    private func bar(_ video: Video) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.ink(1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(video.title)
                Text([video.channelName ?? "", video.durationText, video.viewsText]
                        .filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.ink(0.6))
                    .lineLimit(1)
            }
            // The title is the part that gives way in a narrow window; the buttons keep
            // their labels.
            .layoutPriority(-1)

            Spacer(minLength: 8)

            CircleButton(
                icon: isSaved(video) ? "bookmark.fill" : "bookmark",
                title: isSaved(video)
                    ? "Remove from Saved"
                    : "Save this video to your shelf",
                tint: isSaved(video) ? Palette.accent : nil,
                action: { toggleSaved(video) }
            )

            Button {
                download(video)
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.onFill)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Palette.accent, in: ThemedCapsule())
            }
            .buttonStyle(.plain)
            .help("Queue this video at the chosen quality; it keeps playing here")
            .pointingHand()

            Link(destination: video.url) {
                Text("Open on YouTube")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink(0.75))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.ink(0.1), in: ThemedCapsule())
            }
            .buttonStyle(.plain)
            .help("Open this video in your browser")
            .pointingHand()

            Button(action: popOut) {
                HStack(spacing: 6) {
                    NotchIcon(width: 15)
                    Text("Notch Player")
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink(0.75))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.ink(0.1), in: ThemedCapsule())
            }
            .buttonStyle(.plain)
            .help("Keep it playing in the notch and put the window away")
            .pointingHand()

            CircleButton(
                icon: "xmark",
                title: "Close the player — it keeps playing in the bar at the bottom  (esc)",
                action: dismiss
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

private struct CircleButton: View {
    let icon: String
    let title: String
    /// Only the bookmark uses it. Close is chrome and stays white.
    var tint: Color?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint ?? Palette.ink(1))
                .frame(width: 28, height: 28)
                .background(Palette.ink(hovering ? 0.22 : 0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .pointingHand()
        .onHover { hovering = $0 }
    }
}
