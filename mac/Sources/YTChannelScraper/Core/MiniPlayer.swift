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

    private static let expanded = CGSize(width: 640, height: 118)
    private static let collapsedHeight: CGFloat = 48

    /// The notch's own width, measured at present time. The collapsed pill has to be
    /// wider than it: sized narrower, it sat black-on-black *inside* the notch and was
    /// effectively invisible.
    private var notchWidth: CGFloat?

    var size: CGSize {
        if isExpanded { return Self.expanded }
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
        isExpanded = false
        isShowing = true
        present()
    }

    func hide() {
        playback.detach()
        dismissPanel()
        player = nil
        isShowing = false
        isExpanded = false
    }

    /// Hand the player back out without tearing it down.
    func release() -> AVPlayer? {
        let held = player
        playback.detach()
        dismissPanel()
        player = nil
        isShowing = false
        isExpanded = false
        return held
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        resize(animated: true)
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

    private func updateHover() {
        guard let anchor = Self.anchor() else { return }
        let cursor = NSEvent.mouseLocation
        if isExpanded {
            if !rect(for: Self.expanded, at: anchor).insetBy(dx: -18, dy: -18).contains(cursor) {
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
