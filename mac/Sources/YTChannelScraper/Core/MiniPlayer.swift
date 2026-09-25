import AVFoundation
import AppKit
import SwiftUI

/// A Dynamic-Island-style mini player that grows out of the top of the screen.
///
/// macOS has no Dynamic Island — that is iPhone hardware — and it will not start system
/// Picture in Picture programmatically either: `AVPlayerView` exposes no start method and
/// `canStartPictureInPictureAutomaticallyFromInline` is unavailable on macOS. So the
/// island is our own borderless panel, hung by default from the top centre above the menu
/// bar, where it reads as an extension of the notch on machines that have one and as a
/// floating pill on those that do not.
///
/// It does not have to stay there. Take hold of it anywhere that is not a control — the
/// grip at its leading end is the advertisement, not the only target — and it slides
/// along the screen edge and around the corners onto any of the four, remembering where
/// you left it. Right-clicking it names the four edges instead. See `IslandPlacement`.
@MainActor
@Observable
final class MiniPlayer {
    private(set) var isShowing = false
    var isExpanded = false

    /// Something the island put on screen has the cursor now — the AirPlay route list, so
    /// far. While that is true the island must not collapse: the picker only exists in
    /// the expanded layout, so collapsing pulls it out of the hierarchy and the list it
    /// is presenting goes with it. Which is exactly what happens when you reach down a
    /// long list of devices and the island decides you have left.
    private(set) var isHoldingOpen = false

    /// Whether the output list is open below the controls.
    private(set) var isShowingOutputs = false

    /// Where this video's sound can go. Held here rather than in the view so the island
    /// can size itself around the list before drawing it.
    let outputs = AudioOutputs()

    let playback = Playback()
    private(set) var title = ""
    private(set) var aspectRatio: CGFloat = 16.0 / 9.0
    private(set) var player: AVPlayer?

    /// Put the video back in the main window.
    var onRestore: (() -> Void)?
    /// Stop entirely.
    var onClose: (() -> Void)?

    /// Whether what is playing is already kept, and a way to change that.
    ///
    /// Closures rather than a reference to the library, so the island stays a player and
    /// does not grow a second opinion about what the library is. Both read observable
    /// state when the view calls them, which is what keeps the bookmark filling in the
    /// instant it is pressed.
    var isSaved: (() -> Bool)?
    var onToggleSaved: (() -> Void)?

    private var panel: NSPanel?
    private var tracker: Task<Void, Never>?
    private var outputsWatch: Task<Void, Never>?
    private var menuWatchers: [NSObjectProtocol] = []
    private var settle: Task<Void, Never>?

    /// Height covers the picture row plus the scrubber's own row beneath it. The
    /// scrubber was moved out of the title's column so it can run the island's full
    /// width; the panel has to grow by that row or it simply clips.
    ///
    /// Width grew by the grip's column and the gear's, rather than the title giving
    /// them up. The title already gets whatever a picture and a row of controls leave
    /// it, and taking another fifty points off it would have cost half a dozen
    /// characters of every video's name.
    private static let expanded = CGSize(width: 716, height: 140)
    private static let collapsedHeight: CGFloat = 48

    /// The same island stood up, for the left and right edges — and given its own
    /// proportions rather than the horizontal one's turned on its side. 696 points of
    /// island hanging off the left of the screen is a slab across most of the display
    /// when all that was asked for was the player on the left; upright it is a column,
    /// picture across the top and everything else stacked beneath it.
    private static let expandedUpright = CGSize(width: 264, height: 384)
    /// No notch to clear on a side edge, so the collapsed tab is only as long as the
    /// thumbnail, the grip and the bars need.
    private static let collapsedUpright = CGSize(width: 52, height: 112)

    /// What the open island's contents actually came to, once laid out.
    ///
    /// The heights above are estimates — added up by hand from padding, a 16:9
    /// picture and a row of controls whose real heights are AppKit's business, not
    /// ours. Every one of them came out a little too generous, and on the side edges
    /// that showed as a finger's width of dead black under the controls.
    ///
    /// So the layout measures itself and says, and these become nothing more than the
    /// size to open at before the first measurement arrives. Widths stay fixed: they
    /// are a decision, and the title is elastic, so asking the contents how wide they
    /// would like to be has no answer.
    private var measuredWide: CGFloat?
    private var measuredTall: CGFloat?

    /// Told by `MiniPlayerView` what its contents measured, excluding the output list
    /// — that one is still added on, so the island has room for it the instant it
    /// opens rather than one frame later.
    func report(contentHeight: CGFloat, upright: Bool) {
        guard isExpanded, contentHeight > 1 else { return }
        let height = contentHeight.rounded(.up)
        if upright {
            guard abs((measuredTall ?? 0) - height) > 0.5 else { return }
            measuredTall = height
        } else {
            guard abs((measuredWide ?? 0) - height) > 0.5 else { return }
            measuredWide = height
        }
        resize(animated: false)
    }

    static let outputRowHeight: CGFloat = 30
    /// The section label and the padding around the list.
    private static let outputsChrome: CGFloat = 30
    /// Past about six devices the island would be reaching halfway down the screen, so
    /// the rest scroll.
    private static let outputsMaxHeight: CGFloat = 214
    /// The divider and the AirPlay row under the list, which never scroll away.
    private static let outputsFooter: CGFloat = 39

    // MARK: - Where it hangs

    /// Where the island is docked, or `nil` for home — the top edge of the notched
    /// display, centred on the notch.
    ///
    /// Home is a state rather than a coordinate, and that is the point: only at home
    /// does the collapsed pill size itself to the notch it is sitting in. Storing home
    /// as "the top edge, 0.503 of the way across" would lose that the moment the
    /// island was put back.
    private(set) var placement: IslandPlacement?

    /// Which edge the island is growing out of. The view rounds the three corners that
    /// are not against it.
    var edge: IslandPlacement.Edge { placement?.edge ?? .top }

    /// Whether the island has been moved off home, which is the only time there is
    /// anywhere to go back to.
    var isPlaced: Bool { placement != nil }

    /// Whether this Mac has a notch, for the wording of the menu item that goes home.
    var hasNotch: Bool { IslandDock.home()?.notchWidth != nil }

    /// True from the moment a drag passes its threshold until the mouse comes up.
    /// Hover tracking stands down for the duration: the panel is moving under a cursor
    /// that is holding on to it, and every rule about entering and leaving is wrong.
    private(set) var isDragging = false

    /// How far the cursor was from the island's middle when the drag began.
    ///
    /// Without it the island jumps so its middle lands under the pointer the instant
    /// you start to move, which for something 640 points wide is a lurch of a third of
    /// the screen. Reset when a drag turns a corner, because an offset measured across
    /// the top cannot be carried down the side.
    private var grabOffset: CGFloat = 0

    /// The edge the drag is currently on, which is what `IslandDock.edge(nearest:)`
    /// biases towards so a corner does not flicker between two of them.
    private var dragEdge: IslandPlacement.Edge?

    /// A menu is on screen somewhere. The island holds whatever shape it is in until it
    /// has gone — see `watchMenus`.
    private var isMenuOpen = false

    private static let placementKey = "island.placement"

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.placementKey) else { return }
        placement = try? JSONDecoder().decode(IslandPlacement.self, from: data)
    }

    /// How much taller the island stands while the output list is open.
    var outputsHeight: CGFloat {
        guard isShowingOutputs else { return 0 }
        // The devices, plus the row for the system default.
        let rows = CGFloat(outputs.devices.count + 1)
        let list = min(rows * Self.outputRowHeight, Self.outputsMaxHeight)
        return list + Self.outputsChrome + Self.outputsFooter
    }

    /// Taken against a dock rather than stored, because the collapsed width depends on
    /// whether the island is currently sitting in a notch, and that changes as it is
    /// dragged out of one.
    private func size(in dock: IslandDock, opened: Bool) -> CGSize {
        // The output list always grows the island downward — it is the last thing in
        // the stack either way round.
        guard dock.edge.isHorizontal else {
            guard opened else { return Self.collapsedUpright }
            return CGSize(
                width: Self.expandedUpright.width,
                height: (measuredTall ?? Self.expandedUpright.height) + outputsHeight
            )
        }
        if opened {
            return CGSize(
                width: Self.expanded.width,
                height: (measuredWide ?? Self.expanded.height) + outputsHeight
            )
        }
        let clearance: CGFloat = 104     // visibly proud of the notch on both sides
        return CGSize(
            width: max(320, (dock.notchWidth ?? 0) + clearance),
            height: Self.collapsedHeight
        )
    }

    private func frame(in dock: IslandDock, size: CGSize) -> NSRect {
        dock.frame(for: size)
    }

    /// How far the island sits from the middle of its panel, along the edge.
    ///
    /// Zero nearly always. It earns its keep in the corners: the shut island can be
    /// parked right into one, while the panel — which is always the open island's
    /// size — has to be pushed inward to stay on screen. Without this the shut island
    /// would be drawn in the middle of that panel, which is a couple of hundred
    /// points short of the corner it was put in.
    var islandOffset: CGSize {
        guard let dock = IslandDock.resolve(placement) else { return .zero }
        let island = frame(in: dock, size: islandSize)
        let panel = panelFrame(in: dock)
        // Flipped on the vertical, because this is handed to SwiftUI.
        return dock.edge.isHorizontal
            ? CGSize(width: island.midX - panel.midX, height: 0)
            : CGSize(width: 0, height: -(island.midY - panel.midY))
    }

    private func frame(in dock: IslandDock) -> NSRect {
        frame(in: dock, size: islandSize)
    }

    /// The panel is the open island's size whether or not the island is open.
    ///
    /// Hovering it open then moves no window at all: the island grows inside a frame
    /// that was already the right size, as one SwiftUI animation. Every version that
    /// resized the window in step with the island — AppKit's animator, then a hand
    /// stepped one, then growing it in a single jump — had the window changing on
    /// AppKit's clock while the contents changed on SwiftUI's, and the seam between
    /// those two showed every time: the island appearing at a corner of where it was
    /// about to be, a frame of daylight between the flare and the screen, the picture
    /// arriving after the body it sits in.
    ///
    /// The price is a window larger than what it draws, which would otherwise swallow
    /// every click that lands on the empty part. See `updateClickThrough`.
    private func panelFrame(in dock: IslandDock) -> NSRect {
        frame(in: dock, size: size(in: dock, opened: true))
    }

    /// How big the island is *drawn*, which is not always how big the panel is.
    ///
    /// The panel is grown before the island grows into it and shrunk again once it has
    /// shrunk out of it, so that opening is not also a quarter of a second of the
    /// window server resizing a window and SwiftUI laying the whole island out again,
    /// thirty times over. That was the judder. Inside a panel that is already the
    /// right size the change is one ordinary SwiftUI animation.
    var islandSize: CGSize {
        guard let dock = IslandDock.resolve(placement) else { return Self.collapsedUpright }
        return size(in: dock, opened: isExpanded)
    }

    func show(player: AVPlayer, title: String, aspectRatio: CGFloat) {
        // Tear down any existing panel first. Presenting on top of one orphans it on
        // screen — it stays visible, and an AVPlayer only renders into one layer, so the
        // survivor shows the picture while the orphan sits there as a black rectangle.
        dismissPanel()
        self.player = player
        self.title = title
        self.aspectRatio = aspectRatio
        playback.attach(player)
        outputs.sync(from: player)
        isExpanded = false
        isHoldingOpen = false
        isShowingOutputs = false
        isShowing = true
        present()
    }

    func hide() {
        playback.detach()
        dismissPanel()
        player = nil
        isShowing = false
        isExpanded = false
        isHoldingOpen = false
        isShowingOutputs = false
        isDragging = false
    }

    /// Hand the player back out without tearing it down.
    func release() -> AVPlayer? {
        let held = player
        playback.detach()
        dismissPanel()
        player = nil
        isShowing = false
        isExpanded = false
        isHoldingOpen = false
        isShowingOutputs = false
        isDragging = false
        return held
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        // Closing takes the list with it — it is drawn inside the part that just went.
        if !expanded { isShowingOutputs = false }
        resize(animated: true)
    }

    /// Open or close the output list, growing the island to fit it.
    ///
    /// Open, it holds the island open the same way the AirPlay list does: choosing a
    /// device means travelling down a list that hangs well below the controls, and the
    /// island must not read that as you having left.
    func showOutputs(_ on: Bool) {
        guard isShowingOutputs != on, isShowing else { return }
        if on {
            outputs.refresh()
            if let player { outputs.sync(from: player) }
            isShowingOutputs = true
            isHoldingOpen = true
            isExpanded = true
            resize(animated: true)
            watchOutputs()
        } else {
            outputsWatch?.cancel()
            outputsWatch = nil
            isShowingOutputs = false
            isHoldingOpen = false
            resize(animated: true)
        }
    }

    /// Keep re-reading the device list for as long as it is on screen.
    ///
    /// AirPods leave CoreAudio entirely the moment they idle-disconnect or hand
    /// themselves to a phone, and reappear a second after they wake — so a list read once
    /// when the panel opened is wrong by the time you have looked at it. Which is exactly
    /// the way to open this list, see no AirPods, and conclude the app cannot see them.
    ///
    /// Only while the list is up: this is a menu open for a few seconds, not a reason to
    /// hold a standing subscription to the audio system.
    private func watchOutputs() {
        outputsWatch?.cancel()
        outputsWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, self.isShowingOutputs, !Task.isCancelled else { return }
                let before = self.outputs.devices
                self.outputs.refresh()
                // The island is sized around the row count, so a device arriving or
                // leaving has to move the panel as well as the list.
                if self.outputs.devices.count != before.count { self.resize(animated: true) }
            }
        }
    }

    // MARK: - The cursor

    /// The island no longer opens on hover — it opens on a click, and stays open until
    /// another one.
    ///
    /// Hover was wrong for something you are also expected to pick up and move. Taking
    /// hold of it meant it had already unfolded under your hand, and letting go left
    /// the cursor on top of it, which hover reads as a reason to unfold again. It also
    /// forced the shut island to reserve the open one's room wherever it was parked,
    /// or opening would slide it out from under the pointer that opened it — and that
    /// reservation is what kept it a couple of hundred points away from the corners.
    ///
    /// What is left of the tracking loop is click-through, which still has to be
    /// decided from where the cursor is.
    private func startTracking() {
        tracker?.cancel()
        tracker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isShowing else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Open it, or shut it.
    func toggle() {
        setExpanded(!isExpanded)
    }

    /// Keep the island open regardless of what happens next, until told otherwise.
    ///
    /// Left from when hover could close it, and kept because the AirPlay list still
    /// wants to say "I am up": the list is drawn inside the open island, so whatever
    /// presents it needs a way to insist the island stays open underneath it.
    func holdOpen() {
        isHoldingOpen = true
        setExpanded(true)
    }

    func releaseHold() {
        guard isHoldingOpen else { return }
        // The output list is its own reason to stay open: the AirPlay menu is opened from
        // inside it, and closing that menu must not take the list with it.
        guard !isShowingOutputs else { return }
        isHoldingOpen = false
    }

    private func tick() {
        guard let dock = IslandDock.resolve(placement) else { return }
        updateClickThrough(frame(in: dock), cursor: NSEvent.mouseLocation)
    }

    /// Hand back the clicks that land on the panel but not on the island.
    ///
    /// The panel is the open island's size even while the island is shut, so most of
    /// it is usually transparent — and a transparent window still swallows what lands
    /// on it, which at the notch means swallowing the menu bar.
    ///
    /// Driven from the cursor at the tracking interval rather than from the window's
    /// own events, because the window cannot report events it is ignoring.
    private func updateClickThrough(_ island: NSRect, cursor: CGPoint) {
        guard let panel else { return }
        // Never while a drag or a menu is running: the cursor can outrun the poll, and
        // pulling the window's mouse events out from under either of those is worse
        // than swallowing a click.
        let live = isDragging
            || isMenuOpen
            || island.insetBy(dx: -2, dy: -2).contains(cursor)
        if panel.ignoresMouseEvents == live { panel.ignoresMouseEvents = !live }
    }

    // MARK: - Moving it

    /// Start following the cursor. Called once the drag has passed its threshold, so a
    /// click that happens to wobble a point or two still reads as a click.
    func beginDrag() {
        guard isShowing, panel != nil, let dock = IslandDock.resolve(placement) else { return }
        isDragging = true
        dragEdge = dock.edge
        let cursor = NSEvent.mouseLocation
        // The island's own rect, not the panel's: while the island is closing the
        // panel is still the open size and its middle is not the island's.
        let island = frame(in: dock)
        grabOffset = dock.edge.isHorizontal
            ? island.midX - cursor.x
            : island.midY - cursor.y
    }

    /// Re-dock to wherever the cursor now is.
    ///
    /// The island never floats free mid-drag: it stays flush to the nearest edge and
    /// slides along it, hopping to the next edge when the cursor is decisively closer
    /// to that one. Which means there is no detached state to draw, no drop animation
    /// to get right, and nothing that can be let go of in the middle of the screen.
    ///
    /// Positions come from `NSEvent.mouseLocation` rather than the gesture's own
    /// translation, because the panel the gesture is measured in is the thing being
    /// moved — feeding its displacement back in is a loop.
    func dragged() {
        guard isDragging else { return }
        let cursor = NSEvent.mouseLocation
        guard let screen = IslandDock.screen(under: cursor) else { return }

        let held = dragEdge ?? edge
        let landing = IslandDock.edge(nearest: cursor, on: screen, holding: held)
        if landing.isHorizontal != held.isHorizontal { grabOffset = 0 }
        dragEdge = landing

        let centre = (landing.isHorizontal ? cursor.x : cursor.y) + grabOffset
        let landed = IslandPlacement(
            edge: landing,
            along: IslandDock.fraction(of: centre, along: landing, on: screen),
            displayID: screen.displayID
        )
        // Sticks to the notch as it passes rather than only on release: a magnet you
        // can feel on the way past is the only thing telling you the notch is a target
        // at all, and it also means what you see mid-drag is what you get.
        placement = IslandDock.isHome(landed) ? nil : landed
        resize(animated: false)
    }

    /// Let go.
    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        dragEdge = nil
        savePlacement()
        // Animated, because the drop may have been past the end of the edge and the
        // clamp is about to pull it back in. Letting go no longer opens it — that is
        // now a click, and a drag that ended under the pointer is not one.
        resize(animated: true)
    }

    /// Put the island on an edge without dragging it there, keeping how far along it
    /// sits as far as the new edge allows.
    func move(to edge: IslandPlacement.Edge) {
        guard let dock = IslandDock.resolve(placement) else { return }
        let along = dock.edge.isHorizontal == edge.isHorizontal
            ? IslandDock.fraction(of: dock.centre, along: dock.edge, on: dock.screen)
            : 0.5
        placement = IslandPlacement(edge: edge, along: along, displayID: dock.screen.displayID)
        // Choosing "Top edge" on the notched Mac lands on the notch, and that is home.
        if IslandDock.isHome(placement) { placement = nil }
        savePlacement()
        // Immediately, not on the open/close schedule. Being put somewhere else is not
        // the island changing size, and deferring half of it leaves the island already
        // redrawn for its new edge while still sitting at the old one.
        resize(animated: false)
    }

    /// Back to the notch.
    func goHome() {
        placement = nil
        savePlacement()
        resize(animated: false)
    }

    private func savePlacement() {
        let defaults = UserDefaults.standard
        guard let placement, let data = try? JSONEncoder().encode(placement) else {
            defaults.removeObject(forKey: Self.placementKey)
            return
        }
        defaults.set(data, forKey: Self.placementKey)
    }

    /// Freeze the island for as long as any menu is up.
    ///
    /// The placement menu is a right-click on the island itself, and using it means
    /// walking the cursor down a list that hangs outside the island — which hover
    /// tracking would otherwise read as having left. The route picker solves the same
    /// problem by reporting for itself (see `RoutePickerView`), but a menu raised by
    /// SwiftUI's `contextMenu` has nobody to report for it, so listen to AppKit.
    ///
    /// Deliberately not filtered to our own menu: any menu at all means the cursor has
    /// business somewhere other than the island, and none of them want it resizing
    /// underneath them.
    private func watchMenus() {
        let centre = NotificationCenter.default
        menuWatchers = [
            centre.addObserver(
                forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isMenuOpen = true }
            },
            centre.addObserver(
                forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isMenuOpen = false }
            },
        ]
    }

    // MARK: - The panel

    private func dismissPanel() {
        settle?.cancel()
        settle = nil
        tracker?.cancel()
        tracker = nil
        outputsWatch?.cancel()
        outputsWatch = nil
        menuWatchers.forEach(NotificationCenter.default.removeObserver)
        menuWatchers = []
        isMenuOpen = false
        panel?.ignoresMouseEvents = false
        panel?.contentView = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func present() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.expanded),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Always dark, whatever the Mac is set to: the island is black, and every
        // system-drawn thing in it — the sliders, the placement menu, the AirPlay
        // picker — has to be drawn for black. See the note in `App.swift`.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        // Above the menu bar, so it can sit in the notch's space.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let host = NSHostingView(rootView: MiniPlayerView(mini: self))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        resize(animated: false)
        panel.orderFrontRegardless()
        startTracking()
        watchMenus()
    }

    /// Make the panel fit the island.
    ///
    /// Deliberately not an animation. The island's own size is animated by SwiftUI,
    /// inside here; all this has to do is see that there is room for it. Growing, the
    /// room has to exist before the island reaches for it — so the panel goes first.
    /// Shrinking, it has to stay until the island has finished giving it back — so the
    /// panel goes last. In between, nothing but one hosting view redrawing, which is
    /// the only way this was ever going to feel smooth.
    private func resize(animated: Bool) {
        settle?.cancel()
        settle = nil
        guard let panel, let dock = IslandDock.resolve(placement) else { return }
        let wanted = panelFrame(in: dock)
        guard animated, panel.isVisible else {
            place(panel, wanted)
            panel.invalidateShadow()
            return
        }
        if wanted.width >= panel.frame.width, wanted.height >= panel.frame.height {
            place(panel, wanted)
        }
        settle = Task { @MainActor [weak self] in
            // A window's shadow is taken from what it draws, and the island is about
            // to spend a quarter of a second changing shape without the window
            // changing size — which is not an occasion AppKit recomputes a shadow for.
            // So nudge it on the way, and set the final frame once it has landed.
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(64))
                guard let self, !Task.isCancelled, let panel = self.panel else { return }
                panel.invalidateShadow()
            }
            guard let self, !Task.isCancelled, let panel = self.panel,
                  let dock = IslandDock.resolve(self.placement) else { return }
            self.place(panel, self.panelFrame(in: dock))
            panel.invalidateShadow()
        }
    }

    /// Apply a frame in the order that keeps the island against the screen edge.
    ///
    /// Moving a window and resizing it are two operations, and which goes first shows.
    /// A top-docked island sits at `maxY - 48` shut and `maxY - 140` open: move it
    /// first and the small pill lands where the big one's corner is going to be,
    /// hanging clear of the screen edge until it fills out. Grow it first and the
    /// overshoot goes off the top instead, where it is clipped and nobody sees it.
    ///
    /// Closing is the same two operations the other way round, which is the whole
    /// reason it always looked right while opening did not.
    private func place(_ panel: NSPanel, _ rect: NSRect) {
        let now = panel.frame
        guard now != rect else { return }
        if rect.width > now.width || rect.height > now.height {
            panel.setFrame(NSRect(origin: now.origin, size: rect.size), display: false)
        }
        panel.setFrame(rect, display: true)
    }
}
