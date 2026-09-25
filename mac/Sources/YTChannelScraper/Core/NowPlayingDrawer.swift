import AppKit
import SwiftUI

/// A panel that slides out from under the main window's bottom edge — a second screen
/// bolted to the first — to hold what is still playing after its preview card closed.
///
/// A child window rather than a view inside the window: it is meant to read as extra
/// hardware, outside the page, and a child window moves with its parent, is minimised
/// with it, and stays ordered just behind it, which is what lets it appear to emerge
/// from underneath rather than drop in from nowhere.
///
/// It cannot always be shown. In full screen there is no "below the window", and a
/// window near the foot of a short screen may have nowhere to put it; `show` says so and
/// the caller falls back to the in-window bar.
@MainActor
final class NowPlayingDrawer {
    /// How far the drawer stands in from the window's sides. None: it is the window's own
    /// width, a second screen the same size as the first, hung beneath it.
    private let inset: CGFloat = 0
    let height: CGFloat = 132

    private var panel: NSPanel?
    private weak var parent: NSWindow?
    private var watchers: [NSObjectProtocol] = []

    /// Full screen came or went, so the caller must re-decide where the video lives.
    var onPlacementChanged: (() -> Void)?

    var isShowing: Bool { panel != nil }

    /// Open under `window` holding `content`. False when there is no room below, in
    /// which case nothing has been shown.
    func show(under window: NSWindow, content: some View) -> Bool {
        hide(animated: false)
        guard !window.styleMask.contains(.fullScreen), makeRoom(below: window) else { return false }

        let panel = NSPanel(contentRect: closedFrame(for: window),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: AnyView(content.themed()))
        host.sizingOptions = []
        panel.contentView = host

        window.addChildWindow(panel, ordered: .below)
        panel.orderFront(nil)
        self.panel = panel
        parent = window
        watch(window)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.36
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
            panel.animator().setFrame(openFrame(for: window), display: true)
        }
        return true
    }

    func hide(animated: Bool = true) {
        watchers.forEach(NotificationCenter.default.removeObserver)
        watchers = []
        guard let panel else { return }
        self.panel = nil
        guard animated, let parent else {
            Self.detach(panel, from: self.parent)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(closedFrame(for: parent), display: true)
        }, completionHandler: { [weak parent] in
            MainActor.assumeIsolated { Self.detach(panel, from: parent) }
        })
    }

    private static func detach(_ panel: NSPanel, from parent: NSWindow?) {
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: - Geometry

    /// Tucked behind the window's lower edge, at full size, so sliding it out is a move
    /// and never a resize of what is inside.
    private func closedFrame(for window: NSWindow) -> NSRect {
        var frame = openFrame(for: window)
        frame.origin.y = window.frame.minY + 4
        return frame
    }

    private func openFrame(for window: NSWindow) -> NSRect {
        let w = window.frame
        return NSRect(x: w.minX + inset, y: w.minY - height + 2,
                      width: max(w.width - inset * 2, 360), height: height)
    }

    /// Lift the window if the drawer would fall off the bottom of the screen. False if
    /// the screen is simply too short for both.
    private func makeRoom(below window: NSWindow) -> Bool {
        guard let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return false }
        let need = screen.minY + height - 2
        guard window.frame.minY < need else { return true }
        let lifted = window.frame.offsetBy(dx: 0, dy: need - window.frame.minY)
        guard lifted.maxY <= screen.maxY else { return false }
        window.setFrame(lifted, display: true, animate: true)
        return true
    }

    private func watch(_ window: NSWindow) {
        let centre = NotificationCenter.default
        watchers = [
            centre.addObserver(forName: NSWindow.didResizeNotification, object: window,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel, let parent = self.parent else { return }
                    panel.setFrame(self.openFrame(for: parent), display: true)
                }
            },
            centre.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hide(animated: false)
                    self?.onPlacementChanged?()
                }
            },
        ]
    }
}
