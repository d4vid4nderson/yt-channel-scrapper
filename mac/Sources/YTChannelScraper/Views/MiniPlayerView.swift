import SwiftUI

/// The island's contents. Collapsed it is a sliver that reads as part of the notch;
/// hovering peeks it open into full transport controls, and it closes again on exit.
struct MiniPlayerView: View {
    let mini: MiniPlayer

    private var expanded: Bool { mini.isExpanded }
    private var videoHeight: CGFloat { expanded ? 84 : 26 }

    var body: some View {
        ZStack(alignment: .top) {
            // Flat top, rounded bottom: it grows downward out of the screen edge rather
            // than floating as a detached rectangle.
            UnevenRoundedRectangle(
                bottomLeadingRadius: expanded ? 22 : 16,
                bottomTrailingRadius: expanded ? 22 : 16,
                style: .continuous
            )
            // No border. The island has to read as the notch continuing downward, and
            // any outline — even a faint one — draws a visible seam around it.
            .fill(.black)

            content
                .padding(.horizontal, expanded ? 14 : 10)
                .padding(.vertical, expanded ? 12 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Deliberately no .onHover here — MiniPlayer decides from the cursor position.
        // Hover on a view that resizes itself oscillates; see MiniPlayer.startTracking.
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.26), value: expanded)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: expanded ? 12 : 8) {
            // One layer view across both states, so the picture never tears down and
            // rebuild-flickers as the island opens.
            if let player = mini.player {
                PlayerLayerView(player: player)
                    .frame(width: videoHeight * mini.aspectRatio, height: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: expanded ? 8 : 4, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { mini.onRestore?() }
                    .pointingHand()
                    .help("Back to the window")
            }

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    Text(mini.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    scrubber
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                transport
                volume
                Divider().frame(height: 26).overlay(.white.opacity(0.14))
                chrome
            } else {
                Spacer(minLength: 4)
                PlayingBars(active: mini.playback.isPlaying)
            }
        }
        // Collapsed, the whole pill is a way back — there are no controls to hit by
        // mistake. Expanded, only the video is, so clicks land on the transport.
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { mini.onRestore?() } }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var scrubber: some View {
        if mini.playback.isLive {
            HStack(spacing: 6) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
            .frame(height: 14)
        } else {
            HStack(spacing: 8) {
                Text(Playback.clock(mini.playback.current))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
                Slider(
                    value: Binding(
                        get: { mini.playback.current },
                        set: { mini.playback.seek(to: $0) }
                    ),
                    in: 0...max(mini.playback.duration, 1)
                )
                .controlSize(.mini)
                .tint(Palette.accent)
                Text(Playback.clock(mini.playback.duration))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
            }
            .frame(height: 14)
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            IslandButton(icon: "gobackward.10", size: 12, help: "Back 10 seconds") {
                mini.playback.skip(-10)
            }
            .disabled(mini.playback.isLive)
            IslandButton(
                icon: mini.playback.isPlaying ? "pause.fill" : "play.fill",
                size: 15,
                help: mini.playback.isPlaying ? "Pause" : "Play"
            ) {
                mini.playback.toggle()
            }
            IslandButton(icon: "goforward.10", size: 12, help: "Forward 10 seconds") {
                mini.playback.skip(10)
            }
            .disabled(mini.playback.isLive)
        }
        .fixedSize()
    }

    private var volume: some View {
        HStack(spacing: 5) {
            Image(systemName: mini.playback.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
            Slider(
                value: Binding(
                    get: { Double(mini.playback.volume) },
                    set: { mini.playback.volume = Float($0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .tint(.white.opacity(0.8))
            .frame(width: 58)
        }
        .fixedSize()
        .help("Volume for this video")
    }

    private var chrome: some View {
        HStack(spacing: 8) {
            if let player = mini.player {
                RoutePickerView(player: player)
                    .frame(width: 22, height: 22)
                    .help("AirPlay this video to another device")
                    .pointingHand()
            }
            IslandButton(
                icon: "arrow.down.right.and.arrow.up.left",
                size: 11,
                help: "Put it back in the window"
            ) {
                mini.onRestore?()
            }
            IslandButton(icon: "xmark", size: 11, help: "Stop and close") {
                mini.onClose?()
            }
        }
    }
}

private struct IslandButton: View {
    let icon: String
    let size: CGFloat
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.82))
                .frame(width: size + 12, height: size + 12)
                .background(.white.opacity(hovering ? 0.16 : 0), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .pointingHand()
        .onHover { hovering = $0 }
    }
}

/// The collapsed state needs to say "something is playing up here" at a glance.
private struct PlayingBars: View {
    let active: Bool
    @State private var phase = false

    private let heights: [CGFloat] = [7, 12, 9]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: 2.5, height: active && phase ? height : height * 0.45)
                    .animation(
                        active
                            ? .easeInOut(duration: 0.42 + Double(index) * 0.11)
                                .repeatForever(autoreverses: true)
                            : .default,
                        value: phase
                    )
            }
        }
        .frame(height: 14)
        .onAppear { phase = true }
    }
}
