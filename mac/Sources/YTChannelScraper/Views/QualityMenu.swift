import AppKit
import SwiftUI

/// The quality picker — an AppKit menu rather than SwiftUI's, so it can hang from the
/// button's right edge.
///
/// SwiftUI anchors a `Menu` to the leading edge of its label and gives no way to change
/// it: the SDK offers menuStyle, menuOrder, menuIndicator and nothing for alignment. On a
/// control sitting at the right end of the results bar that is the wrong way round — the
/// menu is wider than the button it comes from, so it grows out over the Download button
/// beside it instead of back across the empty bar it has to its left. An `NSMenu` can be
/// popped at a point of our choosing, which is the only reason this is not a `Menu`.
struct QualityMenu: View {
    @Binding var quality: Quality
    @Binding var alsoAudio: Bool
    /// What the button reads: the quality, plus the mp3 when one is coming with it.
    let face: String

    @State private var anchor: NSView?

    var body: some View {
        Button(action: present) {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(face).font(.system(size: 12.5))
                // `menuStyle(.button)` drew this itself; a plain button has to say so.
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 5)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .background(MenuAnchor { anchor = $0 })
    }

    private func present() {
        guard let anchor else { return }

        let menu = NSMenu()
        // Without this AppKit decides for itself what is enabled, by hunting the
        // responder chain for something answering each item's action.
        menu.autoenablesItems = false

        for option in Quality.menuOrder {
            let item = NSMenuItem(title: option.label, action: nil, keyEquivalent: "")
            item.state = option == quality ? .on : .off
            bind(item) { quality = option }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let sidecar = NSMenuItem(title: "Also save an mp3", action: nil, keyEquivalent: "")
        sidecar.state = alsoAudio ? .on : .off
        sidecar.isEnabled = !quality.isAudioOnly
        bind(sidecar) { alsoAudio.toggle() }
        menu.addItem(sidecar)

        // `popUp` puts the menu's top-left at this point in the anchor's coordinates,
        // which are not flipped — so hanging it *below* the button means going down from
        // the button's minY. Reading `size` is what lays the menu out, and is what makes
        // the right edges line up rather than the left ones.
        let origin = NSPoint(x: anchor.bounds.maxX - menu.size.width, y: anchor.bounds.minY - 5)
        menu.popUp(positioning: nil, at: origin, in: anchor)
    }

    /// An `NSMenuItem` holds its target weakly and its `representedObject` strongly, so
    /// the closure is parked in both: one to fire it, one to keep it alive long enough.
    private func bind(_ item: NSMenuItem, to run: @escaping () -> Void) {
        let action = MenuAction(run)
        item.target = action
        item.action = #selector(MenuAction.fire)
        item.representedObject = action
    }
}

private final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) { self.run = run }

    @objc func fire() { run() }
}

/// Hands back the `NSView` sitting behind a SwiftUI view, to hang the menu from.
private struct MenuAnchor: NSViewRepresentable {
    let store: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view has no frame yet inside `makeNSView`; by the next turn of the loop it
        // has been laid out and its bounds are the button's.
        DispatchQueue.main.async { store(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
