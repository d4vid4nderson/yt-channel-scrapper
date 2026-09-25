import AVFoundation
import SwiftUI

/// What is still playing after its preview card was closed.
///
/// The card closing is not the window going away, so the video stays in the window: a
/// strip at the foot of the page that says what is going, lets you pause or stop it, and
/// takes you back to the full card when you click it. The notch island is kept for when
/// the window itself is minimised or the app hidden — see `AppModel.popOutToIsland`.
struct NowPlayingBar: View {
    let video: Video
    let player: AVPlayer
    let reopen: () -> Void
    let toNotch: () -> Void
    let stop: () -> Void

    /// Mirrors the player rather than the last button pressed: media keys and the island
    /// can change it from outside this view.
    @State private var isPlaying = true
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: video.thumbnail) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.black
                }
            }
            .frame(width: 64, height: 36)
            .clipShape(ThemedRect(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing")
                    .displayType(10, classic: .semibold)
                    .foregroundStyle(Palette.accent)
                Text(video.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink(1))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control(isPlaying ? "pause.fill" : "play.fill",
                    help: isPlaying ? "Pause" : "Play") {
                isPlaying ? player.pause() : player.play()
            }
            control("rectangle.topthird.inset.filled", help: "Move to the notch player",
                    action: toNotch)
            control("xmark", help: "Stop", action: stop)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .frame(maxWidth: 620)
        .background(Palette.surface, in: ThemedRect(cornerRadius: 12, style: .continuous))
        .overlay {
            ThemedRect(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.ink(hovering ? 0.2 : 0.12), lineWidth: 1)
        }
        .themeEdge(radius: 12, lit: hovering)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
        // The strip itself is the way back into the card; the buttons keep their own
        // clicks, so reopening is everything that is not one of them.
        .contentShape(Rectangle())
        .onTapGesture(perform: reopen)
        .onHover { hovering = $0 }
        .help("Back to the player")
        .pointingHand()
        .onReceive(player.publisher(for: \.timeControlStatus)) { isPlaying = $0 != .paused }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(video.title)")
    }

    private func control(_ icon: String, help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink(0.85))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .pointingHand()
    }
}
