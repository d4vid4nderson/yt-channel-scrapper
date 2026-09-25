import SwiftUI

/// The island's contents. Collapsed it is a sliver that reads as part of the notch;
/// hovering peeks it open into full transport controls, and it closes again on exit.
///
/// Flat against whichever screen edge it is docked to, and draggable from anywhere that
/// is not a control — see `Grip` and `moveGesture`.
///
/// It lies along the edge it is docked to, which means it is two layouts rather than
/// one: a wide, short bar on the top and bottom, and a narrow, tall column on the sides.
/// The alternative — keeping the 696-point bar and simply moving it — puts a slab most
/// of the way across the screen when all you asked for was the island on the left.
struct MiniPlayerView: View {
    let mini: MiniPlayer

    private var expanded: Bool { mini.isExpanded }

    /// The edge the island was last drawn on, so that arriving on a different one can
    /// be told apart from opening on the same one.
    @State private var settled: IslandPlacement.Edge = .top

    /// Standing up, because it is docked to a side. The island always runs along its
    /// own edge, so this is the same question as which way it slides.
    private var upright: Bool { !mini.edge.isHorizontal }

    /// Sized off whichever side is not the constrained one: the horizontal island has
    /// height to give a 16:9 picture and the upright one has width, and driving it from
    /// the wrong one turns the video into either an overflow or a postage stamp.
    private var picture: CGSize {
        if upright {
            let width: CGFloat = expanded ? 236 : 36
            return CGSize(width: width, height: (width / mini.aspectRatio).rounded())
        }
        let height: CGFloat = expanded ? 84 : 26
        return CGSize(width: (height * mini.aspectRatio).rounded(), height: height)
    }

    /// The far corners, and the concave flare where the island meets the screen.
    private var corner: CGFloat { expanded ? 22 : 16 }
    private var flare: CGFloat { expanded ? 18 : 12 }

    private var inset: (side: CGFloat, top: CGFloat, bottom: CGFloat) {
        // At the two ends of the island the body pinches back towards the screen by
        // the flare, so whatever sits at those ends has to start after it — otherwise
        // the grip is drawn on the curve with half of it hanging over nothing.
        let ends = flare + 6
        if upright { return (expanded ? 14 : 8, ends, ends) }
        return (ends, expanded ? 12 : 6, expanded ? 8 : 6)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                // No border. The island has to read as the screen edge continuing
                // inward, and any outline — even a faint one — draws a visible seam
                // around it.
                .fill(.black)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    content
                        .padding(.horizontal, inset.side)
                        .padding(.top, inset.top)
                        .padding(.bottom, inset.bottom)

                    // A row of its own, for the horizontal island only. Upright, the
                    // scrubber is simply the next thing down the column and gets the
                    // full width there already.
                    if expanded, !upright {
                        scrubber
                            .padding(.horizontal, inset.side)
                            .padding(.bottom, 10)
                    }
                }
                // What this came to is what the panel should be, rather than a height
                // added up by hand. See `MiniPlayer.report(contentHeight:upright:)`.
                // Measured without the output list below, which is sized separately so
                // that opening it does not have to wait a frame for a measurement.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    mini.report(contentHeight: height, upright: upright)
                }

                if mini.isShowingOutputs, let player = mini.player {
                    OutputList(
                        outputs: mini.outputs,
                        player: player,
                        dismiss: { mini.showOutputs(false) },
                        holdOpen: { mini.holdOpen() },
                        releaseHold: { mini.releaseHold() }
                    )
                    .padding(.horizontal, inset.side)
                    .padding(.bottom, 10)
                }
            }
        }
        // The island's own size, which the panel is not always: it is grown early and
        // shrunk late so that the change happening here is a SwiftUI animation and not
        // a window resize. See `MiniPlayer.islandSize`.
        .frame(width: mini.islandSize.width, height: mini.islandSize.height)
        // Clipped now that the window is no longer doing it. Mid-animation the
        // contents briefly want more room than the island has, and the panel around
        // it has the room to let that show.
        .clipShape(shape)
        .contentShape(shape)
        // A click opens it and another shuts it. Anywhere that is not a control:
        // shut, that is the whole pill; open, it is the padding and the black around
        // the transport, with the picture keeping its own job of going back to the
        // window.
        .onTapGesture { mini.toggle() }
        // Anywhere on the island moves it.
        //
        // `.gesture` and not `.simultaneousGesture`: a child's gesture takes precedence
        // over its parent's, which is exactly the rule wanted here — a drag that starts
        // on the scrubber is a seek, one that starts on the volume is a volume change,
        // and everything else is the island being picked up.
        .gesture(moveGesture)
        // The open hand over the whole island, closing while it is being carried. On a
        // borderless black panel this is most of what tells you the thing moves at all.
        .pointerStyle(mini.isDragging ? .grabActive : .grabIdle)
        // Deliberately no .onHover here — MiniPlayer decides from the cursor position.
        // Hover on a view that resizes itself oscillates; see MiniPlayer.startTracking.
        // One animation off one value, not three off three. Stacked, they can start a
        // frame apart, and a frame apart is the body arriving before the picture in
        // it — which is exactly how that read.
        //
        // No animation at all when the island has arrived on a *different* edge. Being
        // put on the left is not a morph: there is no honest way to tween a wide bar
        // at the top into a tall one at the side, and every attempt reads as a shape
        // crawling across the screen. The Dock does not slide either. Opening and
        // closing on one edge still animates, which is the case that wants it.
        .animation(mini.edge == settled ? .timingCurve(0.2, 0.8, 0.3, 1, duration: 0.26) : nil,
                   value: pose)
        .onChange(of: mini.edge) { settled = mini.edge }
        .contextMenu { placementMenu }
        // Whatever room the panel has beyond the island, spend it away from the screen
        // — the island stays welded to the edge it is docked to.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pin)
        // And along the edge, sit where the island actually goes rather than in the
        // middle of the panel. Only ever non-zero in a corner. See
        // `MiniPlayer.islandOffset`.
        .offset(x: mini.islandOffset.width, y: mini.islandOffset.height)
    }

    /// Everything the island's layout hangs off, in one equatable value, so that any
    /// change to it is a single animation covering the shape, the size and every
    /// control inside at once.
    private struct Pose: Equatable {
        let edge: IslandPlacement.Edge
        let size: CGSize
        let offset: CGSize
        let open: Bool
    }

    private var pose: Pose {
        Pose(edge: mini.edge, size: mini.islandSize, offset: mini.islandOffset, open: expanded)
    }

    /// Which way up the island sits inside a panel that may be larger than it.
    private var pin: Alignment {
        switch mini.edge {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private var shape: IslandShape {
        IslandShape(edge: mini.edge, radius: corner, flare: flare)
    }

    /// Somewhere to put the island that is not a drag.
    ///
    /// Dragging is the good way to move it and a bad way to *discover* that it moves,
    /// so the same list hangs off the gear in the chrome and off a right-click
    /// anywhere on the island. The tick is also the only place that states, in words,
    /// which edge it is currently on.
    @ViewBuilder
    private var placementMenu: some View {
        Section("Where the island lives") {
            ForEach(IslandPlacement.Edge.allCases) { edge in
                Toggle(
                    edge.label,
                    isOn: Binding(
                        get: { mini.edge == edge },
                        set: { if $0 { mini.move(to: edge) } }
                    )
                )
            }
        }
        if mini.isPlaced {
            Divider()
            Button(mini.hasNotch ? "Back to the notch" : "Back to the middle") {
                mini.goHome()
            }
        }
    }

    /// Only a signal that the mouse is down and moving — every position comes from the
    /// cursor itself, in `MiniPlayer.dragged()`. The threshold is what keeps a click
    /// that wobbles a point or two from counting as a move, and therefore what lets the
    /// taps below still fire.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { _ in
                if !mini.isDragging { mini.beginDrag() }
                mini.dragged()
            }
            .onEnded { _ in mini.endDrag() }
    }

    /// Grip, picture, and everything else — along the island's own axis.
    ///
    /// `AnyLayout` and not `if upright { VStack } else { HStack }`: swapping the
    /// container this way keeps the children's identities across the change, and the
    /// one child whose identity matters is the picture. Rebuilt, an `AVPlayerLayer`
    /// comes up black for a frame, so the branch would flash the video off and on
    /// every time the island turned a corner.
    private var content: some View {
        let layout = upright
            ? AnyLayout(VStackLayout(spacing: expanded ? 10 : 7))
            : AnyLayout(HStackLayout(spacing: expanded ? 12 : 8))
        return layout {
            Grip(upright: upright, expanded: expanded, toggle: { mini.toggle() })
                .simultaneousGesture(moveGesture)

            // One layer view across every state, so the picture never tears down and
            // rebuild-flickers as the island opens or moves.
            if let player = mini.player {
                PlayerLayerView(player: player)
                    .frame(width: picture.width, height: picture.height)
                    .clipShape(RoundedRectangle(cornerRadius: expanded ? 8 : 4, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { expanded ? mini.onRestore?() : mini.toggle() }
                    // Its own copy of the move, because its own tap would otherwise be
                    // the child gesture that wins and swallows the drag. Harmless when
                    // both fire: begin, move and end are each idempotent.
                    .simultaneousGesture(moveGesture)
                    .pointingHand()
                    .help(expanded
                        ? "Back to the window — or drag to move the island"
                        : "Open the player — or drag to move it")
            }

            details
        }
    }

    /// The title and the controls, along the same axis as everything else.
    private var details: some View {
        let layout = upright
            ? AnyLayout(VStackLayout(spacing: expanded ? 10 : 0))
            : AnyLayout(HStackLayout(spacing: expanded ? 12 : 0))
        return layout {
            if expanded {
                title
                if upright { scrubber }
                transport
                volume
                // Separates the transport from the chrome, which only reads as a
                // separation while they are side by side. Down a column the spacing
                // already says it.
                if !upright {
                    Divider().frame(height: 26).overlay(.white.opacity(0.14))
                }
                chrome
            } else {
                Spacer(minLength: 4)
                PlayingBars(active: mini.playback.isPlaying)
            }
        }
    }

    // MARK: - Pieces

    /// Title only. The scrubber used to live under it in the same column, which meant a
    /// progress bar for an hour-long video sharing the leftovers of a row that also
    /// holds the picture, the transport, the volume and four chrome buttons — a few
    /// dozen points, where a minute of seeking is a pixel.
    private var title: some View {
        Text(mini.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            // Upright there is a column's width to fill and no row to stay out of the
            // way of, so a long name gets a second line instead of an ellipsis.
            .lineLimit(upright ? 2 : 1)
            .truncationMode(.tail)
            .multilineTextAlignment(upright ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: upright ? .center : .leading)
    }

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
                .pointerStyle(.default)
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
            // Upright it has a whole row to itself, so it takes the width rather than
            // sitting at a fixed 58 with the column empty either side of it.
            .frame(width: upright ? nil : 58)
            .pointerStyle(.default)
        }
        .fixedSize(horizontal: !upright, vertical: true)
        .help("Volume for this video")
    }

    private var chrome: some View {
        HStack(spacing: 8) {
            // First, because it is the only one that changes anything you keep — the rest
            // move the picture around or stop it. Deciding you want a video is a thing
            // that happens while watching it, which is the whole reason this is here and
            // not only on the row you started from.
            if let saved = mini.isSaved?() {
                IslandButton(
                    icon: saved ? "bookmark.fill" : "bookmark",
                    size: 11,
                    tint: saved ? Palette.accent : nil,
                    help: saved ? "Remove from Saved" : "Save this video"
                ) {
                    mini.onToggleSaved?()
                }
            }
            // One way to the question "where is this playing?", answered by one list:
            // the outputs this Mac has, and AirPlay for the ones it has not met yet.
            IslandButton(
                icon: mini.isShowingOutputs ? "speaker.wave.2.fill" : "speaker.wave.2",
                size: 11,
                help: "Where this video plays — speakers, headphones, or AirPlay"
            ) {
                mini.showOutputs(!mini.isShowingOutputs)
            }
            // Next to Restore rather than off on its own: both of them answer the
            // question of where this video is living, one on the screen edge and one
            // back in the window.
            IslandMenu(
                icon: "gearshape.fill",
                size: 11,
                help: "Which edge of the screen the island hangs from"
            ) {
                placementMenu
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

/// A chrome button that opens a menu instead of doing something.
///
/// Hand-dressed to match `IslandButton` down to the hover circle: a stock `Menu` on a
/// black panel arrives as a grey system control with a chevron, which reads as a
/// different kind of thing from the four buttons it sits beside.
private struct IslandMenu<Content: View>: View {
    let icon: String
    let size: CGFloat
    let help: String
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        // The label is empty and the glyph is drawn over it.
        //
        // Given the glyph directly, `BorderlessButtonMenuStyle` treats it as a
        // control's content and colours it from the appearance rather than from
        // `foregroundStyle` — which on a Mac in light mode is near-black, on an island
        // that is always black. The gear simply was not there. Nothing can restyle a
        // clear rectangle, and the overlay is outside the style's reach.
        Menu {
            content()
        } label: {
            Color.clear.frame(width: size + 12, height: size + 12)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .overlay {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.82))
                .frame(width: size + 12, height: size + 12)
                .background(.white.opacity(hovering ? 0.16 : 0), in: Circle())
                .allowsHitTesting(false)
        }
        .help(help)
        .pointingHand()
        .onHover { hovering = $0 }
    }
}

/// Something to take hold of.
///
/// The island can be dragged from anywhere that is not a control, so this is a sign
/// rather than the only target — but a black pill with no border and no title bar says
/// nothing at all about being movable, and a handle nobody can see is a handle nobody
/// finds. Six dots, because that is what a drag handle looks like everywhere else.
private struct Grip: View {
    let upright: Bool
    let expanded: Bool
    /// The grip is a handle, but it is also just part of the island, and a click on
    /// any part of the island opens or shuts it.
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        // Three dots across by two down on the upright island, two by three on the
        // horizontal one: the long side of the grip lies across the way the island
        // travels, which is how every other grabber on the machine is drawn.
        let rows = Array(0..<(upright ? 2 : 3))
        let columns = Array(0..<(upright ? 3 : 2))
        return VStack(spacing: 2.5) {
            ForEach(rows, id: \.self) { _ in
                HStack(spacing: 2.5) {
                    ForEach(columns, id: \.self) { _ in
                        Circle().frame(width: 2, height: 2)
                    }
                }
            }
        }
        .foregroundStyle(.white.opacity(hovering ? 0.7 : 0.3))
        // Bigger than the dots so there is something to hit, and a fixed size in each
        // state so the layout does not reflow as the island opens.
        .frame(
            width: upright ? (expanded ? 36 : 26) : 13,
            height: upright ? 12 : (expanded ? 28 : 20)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Drag to move the island — or right-click to pick a side")
        .simultaneousGesture(TapGesture().onEnded { toggle() })
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct IslandButton: View {
    let icon: String
    let size: CGFloat
    /// Left nil by everything but the bookmark. A transport control that took a colour
    /// would be one more thing competing with the picture.
    var tint: Color?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? .white.opacity(hovering ? 1 : 0.82))
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
