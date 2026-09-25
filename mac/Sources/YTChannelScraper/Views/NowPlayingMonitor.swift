import AVFoundation
import SwiftUI

/// What the Now Playing drawer shows: the picture itself, live, and a readout beside it —
/// a second screen hung under the window rather than a bar across it.
struct NowPlayingMonitor: View {
    let video: Video
    let player: AVPlayer
    let ratio: CGFloat
    let expand: () -> Void
    let toNotch: () -> Void
    let stop: () -> Void

    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 0) {
            hinge
            HStack(spacing: 18) {
                screen
                readout
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Palette.surface
                ThemeBackdrop(strength: 0.5)
            }
        }
        .clipShape(ThemedRect(cornerRadius: 14, style: .continuous))
        .overlay {
            ThemedRect(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.ink(0.14), lineWidth: 1)
        }
        .themeEdge(radius: 14)
        .onReceive(player.publisher(for: \.timeControlStatus)) { isPlaying = $0 != .paused }
    }

    /// Where the drawer meets the window: a darker strip carrying a row of status lights,
    /// the one that is lit being whether it is playing.
    private var hinge: some View {
        HStack(spacing: 6) {
            Circle().fill(isPlaying ? Palette.good : Palette.ink(0.2)).frame(width: 5, height: 5)
                .shadow(color: isPlaying ? Palette.good : .clear, radius: 3)
            Circle().fill(Palette.accent.opacity(0.7)).frame(width: 5, height: 5)
            Circle().fill(Palette.ink(0.2)).frame(width: 5, height: 5)
            Spacer()
            Text("Output 2")
                .font(.system(size: 9, weight: .semibold).monospaced())
                .foregroundStyle(Palette.ink(0.35))
                .textCase(.uppercase)
                .tracking(1.5)
        }
        .padding(.horizontal, 16)
        .frame(height: 20)
        .background(Color.black.opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink(0.10)).frame(height: 1)
        }
    }

    /// The picture, in a bezel. Clicking it opens the full card.
    private var screen: some View {
        let height: CGFloat = 116
        let width = min(max(height * ratio, height), height * 16 / 9)
        return PlayerLayerView(player: player)
            .frame(width: width, height: height)
            .background(Color.black)
            .clipShape(ThemedRect(cornerRadius: 8, style: .continuous))
            .overlay {
                ThemedRect(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.ink(0.18), lineWidth: 1)
            }
            .themeEdge(radius: 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: expand)
            .help("Back to the player")
            .pointingHand()
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Now Playing")
                .displayType(10, classic: .semibold)
                .foregroundStyle(Palette.accent)
            Text(video.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.ink(1))
                .lineLimit(2)
            Track(player: player)
            HStack(spacing: 4) {
                control("gobackward.15", help: "Back 15 seconds") { skip(-15) }
                control(isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? "Pause" : "Play",
                        size: 16) {
                    isPlaying ? player.pause() : player.play()
                }
                control("goforward.15", help: "Forward 15 seconds") { skip(15) }
                Spacer()
                control("arrow.up.left.and.arrow.down.right", help: "Back to the player",
                        action: expand)
                control("rectangle.topthird.inset.filled", help: "Move to the notch player",
                        action: toNotch)
                control("xmark", help: "Stop", action: stop)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skip(_ seconds: Double) {
        let now = player.currentTime().seconds
        guard now.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, now + seconds), preferredTimescale: 600))
    }

    private func control(_ icon: String, help: String, size: CGFloat = 13,
                         action: @escaping () -> Void) -> some View {
        ControlButton(icon: icon, size: size, action: action)
            .help(help)
            .accessibilityLabel(help)
    }

    private struct ControlButton: View {
        let icon: String
        let size: CGFloat
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(hovering ? Palette.accent : Palette.ink(0.85))
                    .frame(width: 30, height: 28)
                    .background(hovering ? Palette.ink(0.08) : .clear,
                                in: ThemedRect(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .pointingHand()
        }
    }

    /// Elapsed and remaining, and a line between them. Read off the player twice a second
    /// rather than observed — nothing else wants the time, and a timeline is cheaper than
    /// a periodic observer to keep in step with a view that comes and goes.
    private struct Track: View {
        let player: AVPlayer

        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let now = player.currentTime().seconds
                let total = player.currentItem?.duration.seconds ?? .nan
                let fraction = (now.isFinite && total.isFinite && total > 0) ? now / total : 0
                HStack(spacing: 8) {
                    Text(Self.clock(now))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            ThemedCapsule().fill(Palette.ink(0.12))
                            ThemedCapsule().fill(Palette.accent)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 3)
                    Text(total.isFinite ? Self.clock(total) : "--:--")
                }
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Palette.ink(0.5))
            }
        }

        static func clock(_ seconds: Double) -> String {
            guard seconds.isFinite else { return "--:--" }
            let s = Int(seconds)
            return s >= 3600
                ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                : String(format: "%d:%02d", s / 60, s % 60)
        }
    }
}
