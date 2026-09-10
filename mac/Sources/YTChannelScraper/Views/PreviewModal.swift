import SwiftUI

/// Watch a video before deciding to download it — the scraper doubling as a viewer.
///
/// Deliberately no `GeometryReader`: reads of an `@Observable` inside its content closure
/// land in a different update scope from the view's own body, so `state` changes did not
/// invalidate this view and the stage stayed on its spinner while the player was already
/// running. `aspectRatio(_:contentMode:)` does the sizing without one.
struct PreviewModal: View {
    let session: PreviewSession
    let download: (Video) -> Void
    let popOut: () -> Void

    var body: some View {
        // Every observable read happens here, in this view's own body. The
        // GeometryReader below is used purely for available space — nothing observable
        // is read inside its closure, which is what previously broke invalidation.
        let video = session.video
        let ratio = session.aspectRatio
        let state = session.state

        return ZStack {
            if let video {
                Rectangle()
                    .fill(.black.opacity(0.62))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { session.close() }
                    .transition(.opacity)

                GeometryReader { geo in
                    card(video, ratio: ratio, state: state, available: geo.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(video != nil)
        .animation(.easeOut(duration: 0.2), value: video?.id)
        .onExitCommand { session.close() }
    }

    private func card(
        _ video: Video,
        ratio: CGFloat,
        state: PreviewSession.State,
        available: CGSize
    ) -> some View {
        // The stage has to be bounded on both axes. Bounded only by width, a 9:16 Short
        // asks for ~1740pt of height and pushes the footer clean off the card.
        let chrome: CGFloat = 132          // header + footer
        let inset: CGFloat = 88            // the card's own padding, both sides
        let maxStageWidth = max(min(available.width - inset, 980), 260)
        let maxStageHeight = max(available.height - inset - chrome, 160)

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([video.durationText, video.viewsText]
                            .filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color(white: 0.6))
                }
                Spacer(minLength: 8)
                CircleButton(
                    icon: "arrow.up.right.and.arrow.down.left",
                    title: "Keep playing in the island at the top of the screen"
                ) { popOut() }
                CircleButton(icon: "xmark", title: "Close preview") { session.close() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // The stage takes the shape of the stream, so a Short is not letterboxed
            // into a widescreen box and a talk is not cropped into a tall one — while
            // staying inside the card either way.
            PreviewStage(state: state)
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: maxStageWidth, maxHeight: maxStageHeight)
                .frame(maxWidth: .infinity)
                .background(.black)

            HStack(spacing: 10) {
                Button {
                    download(video)
                    session.close()
                } label: {
                    Label("Download this", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Queue this video for download at the chosen quality")
                .pointingHand()

                Link(destination: video.url) {
                    Text("Open on YouTube")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Open this video in your browser")
                .pointingHand()

                Spacer()

                Text("Adapts to your connection, up to 1080p")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(white: 0.45))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: max(min(maxStageWidth, 980), 560))
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.sheetSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(white: 0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.6), radius: 40, y: 16)
        .padding(44)
    }
}

/// Its own view, so its read of `session.state` is tracked in its own body.
private struct PreviewStage: View {
    let state: PreviewSession.State

    var body: some View {
        switch state {
        case .working(let stage):
            VStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(.white)
                Text(stage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let player):
            PlayerView(player: player)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.72))
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(hovering ? 0.22 : 0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .pointingHand()
        .onHover { hovering = $0 }
    }
}
