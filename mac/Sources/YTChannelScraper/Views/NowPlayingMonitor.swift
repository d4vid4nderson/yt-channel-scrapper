import AVFoundation
import SwiftUI

/// What the Now Playing module shows: the picture itself, live, and a readout beside it —
/// its own unit between the page and the footer, rather than a bar laid across the list.
struct NowPlayingMonitor: View {
    let video: Video
    let player: AVPlayer
    let ratio: CGFloat
    let analysis: TrackAnalysis
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
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
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

    /// Where the module meets the page: a darker strip carrying a row of status lights,
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
        .frame(height: 14)
        .background(Color.black.opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink(0.10)).frame(height: 1)
        }
    }

    /// The picture, in a bezel. Clicking it opens the full card.
    private var screen: some View {
        let height: CGFloat = 84
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text("Now Playing")
                    .displayType(10, classic: .semibold)
                    .foregroundStyle(Palette.accent)
                Spacer(minLength: 0)
                Pulse(player: player, analysis: analysis)
            }
            Text(video.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink(1))
                .lineLimit(1)
            Track(player: player, analysis: analysis)
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

    /// Elapsed and total, and between them the track's own waveform — played in the
    /// accent, still to come in ink, and a dotted line where the analysis has not got to
    /// yet. With no analysis at all (no ffmpeg) it is a plain progress line.
    private struct Track: View {
        let player: AVPlayer
        let analysis: TrackAnalysis

        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let now = player.currentTime().seconds
                let total = player.currentItem?.duration.seconds ?? .nan
                let known = now.isFinite && total.isFinite && total > 0
                let fraction = known ? now / total : 0
                HStack(spacing: 8) {
                    Text(Self.clock(now))
                    Canvas { c, size in
                        let playedX = size.width * fraction
                        let accent = GraphicsContext.Shading.color(Palette.accent)
                        let rest = GraphicsContext.Shading.color(Palette.ink(0.28))
                        let pending = GraphicsContext.Shading.color(Palette.ink(0.12))
                        guard known, analysis.peak > 0 else {
                            c.fill(Path(CGRect(x: 0, y: size.height / 2 - 1.5, width: size.width, height: 3)), with: rest)
                            c.fill(Path(CGRect(x: 0, y: size.height / 2 - 1.5, width: playedX, height: 3)), with: accent)
                            return
                        }
                        let bar: CGFloat = 2, gap: CGFloat = 1.5
                        let columns = Int(size.width / (bar + gap))
                        let perColumn = total * TrackAnalysis.rate / Double(max(columns, 1))
                        for column in 0..<columns {
                            let x = CGFloat(column) * (bar + gap)
                            let first = Int(Double(column) * perColumn)
                            guard first < analysis.envelope.count else {
                                c.fill(Path(ellipseIn: CGRect(x: x, y: size.height / 2 - 0.75, width: 1.5, height: 1.5)), with: pending)
                                continue
                            }
                            // The loudest of a few samples across the column's stretch.
                            let last = min(analysis.envelope.count, Int(Double(column + 1) * perColumn))
                            var loud: Float = 0
                            let step = max(1, (last - first) / 8)
                            var i = first
                            while i < last { loud = max(loud, analysis.envelope[i]); i += step }
                            let v = CGFloat(min(1, (loud / analysis.peak).squareRoot()))
                            let h = max(2, v * size.height)
                            let rect = CGRect(x: x, y: (size.height - h) / 2, width: bar, height: h)
                            c.fill(Path(roundedRect: rect, cornerRadius: 1), with: x < playedX ? accent : rest)
                        }
                        c.fill(Path(CGRect(x: playedX - 0.5, y: 0, width: 1, height: size.height)),
                               with: .color(Palette.ink(0.9)))
                    }
                    .frame(height: 18)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { _ in })
                    .overlay {
                        // Click or drag along it to seek.
                        GeometryReader { geo in
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                    guard known else { return }
                                    let f = min(max(drag.location.x / geo.size.width, 0), 1)
                                    player.seek(to: CMTime(seconds: f * total, preferredTimescale: 600))
                                })
                        }
                    }
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

    /// The sound as it is now: a small level meter moving with the loudness at the
    /// playhead, and the tempo with a light that flashes on the beat. The flash is a soft
    /// rise and fall rather than a strobe — this can be on a child's screen.
    private struct Pulse: View {
        let player: AVPlayer
        let analysis: TrackAnalysis

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                let now = player.currentTime().seconds
                let playing = player.timeControlStatus == .playing
                HStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<7, id: \.self) { i in
                            // Seven taps across the last 120 ms, so the meter has shape.
                            let level = playing ? CGFloat(analysis.level(at: now - Double(6 - i) * 0.02) ?? 0) : 0
                            ThemedCapsule()
                                .fill(Palette.accent.opacity(0.4 + 0.6 * level))
                                .frame(width: 3, height: 3 + level.squareRoot() * 15)
                        }
                    }
                    .frame(height: 18)
                    if let bpm = analysis.bpm {
                        let period = 60 / bpm
                        let since = (now - analysis.beatPhase).truncatingRemainder(dividingBy: period)
                        let phase = since < 0 ? since + period : since
                        let glow = playing ? exp(-pow(phase / 0.09, 2)) : 0
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 6, height: 6)
                            .opacity(0.3 + 0.7 * glow)
                            .shadow(color: Palette.accent.opacity(glow), radius: 4)
                        Text("\(Int(bpm.rounded())) BPM")
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.ink(0.6))
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }
}
