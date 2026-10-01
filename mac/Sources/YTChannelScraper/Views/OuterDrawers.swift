import AppKit
import SwiftUI

/// The Saved, Family and Downloads panels, as drawers that slide out from behind the
/// window rather than opening inside it.
///
/// Inside, a panel took its width from the page, and everything on the page — the hero,
/// the board, the list — was squeezed to make room, then let out again. Here each panel
/// is a window of its own, attached to the main one as a child so it moves with it, kept
/// behind it in the window order, and slid out from under its edge: the page never
/// changes size. The old `NSDrawer` did this, and was taken out of AppKit; this is the
/// same idea built from a child window.
///
/// Full screen has no outside to slide into, so there the page keeps the inline slots it
/// always had (see `RootView`), and these stay shut.
@MainActor
final class OuterDrawers {
    enum Kind: CaseIterable { case saved, family, downloads }

    /// How far a drawer tucks behind the window's edge when open, so it reads as coming
    /// out from under it rather than as a window parked alongside.
    private static let tuck: CGFloat = 14
    private static let duration: TimeInterval = 0.32

    private weak var window: NSWindow?
    private var panels: [Kind: DrawerPanel] = [:]
    private var open: Set<Kind> = []
    private var observers: [NSObjectProtocol] = []

    /// The window the drawers belong to. Set once it exists, and again if SwiftUI hands
    /// the view to a different one.
    func attach(to window: NSWindow?) {
        guard let window, window !== self.window else { return }
        detachAll()
        self.window = window
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.relayout() }
            })
        }
    }

    /// Make the drawers match what the model says should be open.
    func sync(_ wanted: [Kind: Bool], content: (Kind) -> AnyView) {
        guard let window else { return }
        for kind in Kind.allCases {
            let want = wanted[kind] ?? false
            if want, !open.contains(kind) {
                let panel = panels[kind] ?? makePanel(kind, content: content(kind))
                panels[kind] = panel
                show(kind, panel, in: window)
            } else if !want, open.contains(kind), let panel = panels[kind] {
                hide(kind, panel, in: window)
            }
        }
    }

    // MARK: - Opening and closing

    private func show(_ kind: Kind, _ panel: DrawerPanel, in window: NSWindow) {
        open.insert(kind)
        makeRoom(for: kind, in: window)
        panel.setFrame(tucked(kind, in: window), display: false)
        if panel.parent !== window { window.addChildWindow(panel, ordered: .below) }
        panel.order(.below, relativeTo: window.windowNumber)
        animate(panel, to: extended(kind, in: window))
    }

    private func hide(_ kind: Kind, _ panel: DrawerPanel, in window: NSWindow) {
        open.remove(kind)
        animate(panel, to: tucked(kind, in: window)) { [weak self, weak panel, weak window] in
            guard let self, let panel, !self.open.contains(kind) else { return }
            window?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func animate(_ panel: NSPanel, to frame: NSRect, done: (@MainActor () -> Void)? = nil) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = still ? 0 : Self.duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { done?() }
        }
    }

    /// Keep open drawers the window's height (or width) as it is resized. Child windows
    /// move with their parent on their own, but nothing resizes them.
    private func relayout() {
        guard let window else { return }
        for kind in open {
            panels[kind]?.setFrame(extended(kind, in: window), display: true)
        }
    }

    private func detachAll() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for panel in panels.values {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panels = [:]
        open = []
    }

    // MARK: - Geometry

    /// Beside the window's body, below the title bar: the drawer comes out of the window,
    /// not out of its chrome.
    private func body(of window: NSWindow) -> NSRect {
        let frame = window.frame
        let titleBar = frame.height - window.contentLayoutRect.height
        return NSRect(x: frame.minX, y: frame.minY + 8,
                      width: frame.width, height: max(frame.height - titleBar - 16, 120))
    }

    private func extended(_ kind: Kind, in window: NSWindow) -> NSRect {
        let b = body(of: window)
        let w = Layout.drawerWidth, h = Layout.downloadsHeight
        switch kind {
        case .saved:
            return NSRect(x: b.minX - w + Self.tuck, y: b.minY, width: w, height: b.height)
        case .family:
            return NSRect(x: b.maxX - Self.tuck, y: b.minY, width: w, height: b.height)
        case .downloads:
            let width = min(b.width - 48, 900)
            return NSRect(x: b.midX - width / 2, y: window.frame.minY - h + Self.tuck,
                          width: width, height: h)
        }
    }

    /// The same drawer, slid all the way back behind the window.
    private func tucked(_ kind: Kind, in window: NSWindow) -> NSRect {
        var frame = extended(kind, in: window)
        switch kind {
        case .saved:     frame.origin.x += frame.width - Self.tuck - 2
        case .family:    frame.origin.x -= frame.width - Self.tuck - 2
        case .downloads: frame.origin.y += frame.height - Self.tuck - 2
        }
        return frame
    }

    /// Against the edge of the screen there is nowhere for a drawer to go, so the window
    /// steps in to make room — the same thing it would have had to do by hand.
    private func makeRoom(for kind: Kind, in window: NSWindow) {
        guard let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let target = extended(kind, in: window)
        var frame = window.frame
        switch kind {
        case .saved where target.minX < screen.minX:
            frame.origin.x += screen.minX - target.minX
        case .family where target.maxX > screen.maxX:
            frame.origin.x -= target.maxX - screen.maxX
        case .downloads where target.minY < screen.minY:
            frame.origin.y += screen.minY - target.minY
        default:
            return
        }
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Panels

    private func makePanel(_ kind: Kind, content: AnyView) -> DrawerPanel {
        let panel = DrawerPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: DrawerChrome(content: content).themed())
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

/// A borderless panel that can still take typing — the Saved panel's filter, the family
/// name — which a borderless window refuses by default.
final class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The drawer's own outline: the panel's surface clipped to the theme's corner, with a
/// hairline, so the part that shows outside the window reads as a finished edge.
private struct DrawerChrome: View {
    let content: AnyView

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(ThemedRect(cornerRadius: 10, style: .continuous))
            .overlay {
                ThemedRect(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.ink(0.16), lineWidth: 1)
            }
    }
}

/// Hands the hosting window to `OuterDrawers`, which needs the real `NSWindow` to attach
/// its children to.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { Probe(found: found) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Probe: NSView {
        let found: (NSWindow?) -> Void
        init(found: @escaping (NSWindow?) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            found(window)
        }
    }
}
