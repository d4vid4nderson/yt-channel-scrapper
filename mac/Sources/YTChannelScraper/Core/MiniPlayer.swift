import AVFoundation
import AppKit
import SwiftUI

/// A Dynamic-Island-style mini player that grows out of the top of the screen.
///
/// macOS has no Dynamic Island — that is iPhone hardware — and it will not start system
/// Picture in Picture programmatically either: `AVPlayerView` exposes no start method and
/// `canStartPictureInPictureAutomaticallyFromInline` is unavailable on macOS. So the
/// island is our own borderless panel, pinned to the top centre above the menu bar, where
/// it reads as an extension of the notch on machines that have one and as a floating pill
/// on those that do not.
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

    private var panel: NSPanel?
    private var tracker: Task<Void, Never>?
    private var outputsWatch: Task<Void, Never>?

    private static let expanded = CGSize(width: 640, height: 118)
    private static let collapsedHeight: CGFloat = 48

    static let outputRowHeight: CGFloat = 30
    /// The section label and the padding around the list.
    private static let outputsChrome: CGFloat = 30
    /// Past about six devices the island would be reaching halfway down the screen, so
    /// the rest scroll.
    private static let outputsMaxHeight: CGFloat = 214
    /// The divider and the AirPlay row under the list, which never scroll away.
    private static let outputsFooter: CGFloat = 39

    /// The notch's own width, measured at present time. The collapsed pill has to be
    /// wider than it: sized narrower, it sat black-on-black *inside* the notch and was
    /// effectively invisible.
    private var notchWidth: CGFloat?

    /// How much taller the island stands while the output list is open.
    var outputsHeight: CGFloat {
        guard isShowingOutputs else { return 0 }
        // The devices, plus the row for the system default.
        let rows = CGFloat(outputs.devices.count + 1)
        let list = min(rows * Self.outputRowHeight, Self.outputsMaxHeight)
        return list + Self.outputsChrome + Self.outputsFooter
    }

    var size: CGSize {
        if isExpanded {
            return CGSize(
                width: Self.expanded.width,
                height: Self.expanded.height + outputsHeight
            )
        }
        let clearance: CGFloat = 104     // visibly proud of the notch on both sides
        return CGSize(
            width: max(320, (notchWidth ?? 0) + clearance),
            height: Self.collapsedHeight
        )
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
            updateHover()
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

    // MARK: - Hover

    /// Hover is decided from the cursor's own position, not from a `.onHover` on the
    /// panel's content.
    ///
    /// Expanding *resizes the panel*, which makes AppKit rebuild the content view's
    /// tracking areas; hover briefly reports false, the island collapses, the cursor is
    /// inside the small pill again, and it re-expands — a flicker loop, worst right over
    /// the notch because that is the middle of the trigger zone.
    ///
    /// The zones are deliberately asymmetric: a small rect opens it, a larger one keeps
    /// it open. Since the open zone sits wholly inside the hold zone, expanding can
    /// never push the cursor out of what is holding it open, so it cannot oscillate.
    private func startTracking() {
        tracker?.cancel()
        tracker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isShowing else { return }
                self.updateHover()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// Keep the island open regardless of where the cursor goes, until told otherwise.
    ///
    /// The AirPlay list drops well below the island and can run to a dozen devices, so
    /// picking one means travelling a long way outside anything the island could sensibly
    /// treat as "still hovering". Rather than guess at a hold zone big enough — which
    /// would have to cover most of the screen, and would still be a guess — the thing
    /// presenting the list says when it starts and when it is done.
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
        // Checked at once rather than waiting for the next poll: by the time a device has
        // been chosen the cursor is usually nowhere near the island, and the island should
        // close behind you rather than sit there open for another beat.
        updateHover()
    }

    private func updateHover() {
        guard !isHoldingOpen, let anchor = Self.anchor() else { return }
        let cursor = NSEvent.mouseLocation
        if isExpanded {
            if !rect(for: size, at: anchor).insetBy(dx: -18, dy: -18).contains(cursor) {
                setExpanded(false)
            }
        } else if rect(for: size, at: anchor).contains(cursor) {
            setExpanded(true)
        }
    }

    // MARK: - The panel

    private func dismissPanel() {
        tracker?.cancel()
        tracker = nil
        outputsWatch?.cancel()
        outputsWatch = nil
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
        notchWidth = Self.anchor()?.notchWidth
        resize(animated: false)
        panel.orderFrontRegardless()
        startTracking()
    }

    private func rect(for size: CGSize, at anchor: Anchor) -> NSRect {
        NSRect(
            // Centred on the notch itself, which is not always the screen's midpoint,
            // and flush with the very top so it grows downward out of it.
            x: anchor.centreX - size.width / 2,
            y: anchor.topY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func resize(animated: Bool) {
        guard let panel, let anchor = Self.anchor() else { return }
        let frame = rect(for: size, at: anchor)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private struct Anchor {
        let centreX: CGFloat
        let topY: CGFloat
        let notchWidth: CGFloat?
    }

    /// Where the island should hang from: the notched display if there is one, and the
    /// notch's true centre rather than the screen's — they differ when displays are
    /// arranged off-centre. Machines with no notch just get the screen's midpoint.
    private static func anchor() -> Anchor? {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else { return nil }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return Anchor(
                centreX: (left.maxX + right.minX) / 2,
                topY: screen.frame.maxY,
                notchWidth: right.minX - left.maxX
            )
        }
        return Anchor(centreX: screen.frame.midX, topY: screen.frame.maxY, notchWidth: nil)
    }
}
