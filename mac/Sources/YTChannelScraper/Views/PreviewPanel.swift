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
    /// The page's width, so the stage can be given an exact height. Asked for only as a
    /// maximum, the height was whatever the list below left over — the list is a scroll
    /// view and takes all it can — so dragging the grip never made the picture larger.
    let width: CGFloat
    let download: (Video) -> Void
    let popOut: () -> Void
    /// Keeping what you are watching. Closures rather than the model, to match the rest
    /// of this panel's inputs — it is handed what it can do, not where things live.
    let isSaved: (Video) -> Bool
    let toggleSaved: (Video) -> Void
    /// Every way out of the panel. Not `session.close()` directly: leaving the panel is
    /// not asking for silence, so what is playing goes down to the Now Playing bar.
    let dismiss: () -> Void

    /// How much of the results area the picture takes, set by dragging the grip under
    /// the panel and kept between launches. 0.6 is where it started.
    @AppStorage("player.stageFraction") private var fraction: Double = 0.6
    /// The fraction when the current drag began, so the drag is measured from there.
    @State private var dragStart: Double?

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
                // Exactly the grip's height, unless the stream's shape at the page's width
                // is shorter — then that, so a widescreen picture is never pillarboxed for
                // height it cannot use.
                PreviewStage(state: state)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: min(stageHeight, width / max(ratio, 0.1)))
                    .background(.black)

                bar(video)
            }
            .background(Palette.sheetSurface)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink(0.12)).frame(height: 1) }
            .overlay(alignment: .bottom) { grip }
            .onExitCommand(perform: dismiss)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// As much of the results area as the grip has been dragged to, between a floor that
    /// keeps the picture worth watching and a ceiling that keeps the list's toolbar in view.
    private var stageHeight: CGFloat { max(available * clamped(fraction), 160) }

    private func clamped(_ value: Double) -> Double {
        // Room for the panel's own bar and the list's toolbar, and nothing else: drag all
        // the way down and the picture has the page, with the tabs still there to come
        // back from. Leaving a row of the list as well capped a 16:9 video well short of
        // the window's width.
        let ceiling = max((available - 52 - Chrome.bar * 2) / max(available, 1), 0.3)
        return min(max(value, 0.25), ceiling)
    }

    /// The divider between the player and the list, dragged up or down to trade picture
    /// for list. Double-click puts it back where it started. Straddles the panel's lower
    /// edge so it is easy to catch without taking room of its own.
    private var grip: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Palette.ink(dragStart == nil ? 0.28 : 0.55))
                .frame(width: 36, height: 4)
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .offset(y: 6)
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? clamped(fraction)
                    if dragStart == nil { dragStart = start }
                    fraction = clamped(start + drag.translation.height / max(available, 1))
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture(count: 2) { fraction = 0.6 }
        .help("Drag to make the player larger or smaller; double-click to reset")
        .zIndex(1)
    }

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
