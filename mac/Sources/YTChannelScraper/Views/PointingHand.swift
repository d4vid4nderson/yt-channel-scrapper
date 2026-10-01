import SwiftUI

/// macOS leaves the arrow cursor over everything, including custom-drawn controls, so
/// nothing on a hand-built surface signals that it can be clicked. This puts the hand
/// back over the things that act like buttons.
///
/// `NSCursor.pointingHand.push()` from `onHover` does not survive here: AppKit re-sets
/// the cursor on every mouse-moved event inside the view, so the hand is overwritten
/// almost immediately. `pointerStyle` hooks into that same machinery instead of fighting
/// it, which is why it sticks.
///
/// `pointerStyle` alone does nothing in the drawers, though: they are panels beside the
/// window that never become key, and AppKit only honours cursor requests in the key
/// window. Hover still reaches them, so the hand is also set on every move over the view
/// — after AppKit's own reset, which is what made `push()` lose — and the arrow put back
/// on leaving.
extension View {
    /// Show the pointing hand while the cursor is over this view.
    func pointingHand() -> some View {
        pointerStyle(.link)
            .onContinuousHover { phase in
                switch phase {
                case .active: NSCursor.pointingHand.set()
                case .ended: NSCursor.arrow.set()
                }
            }
    }
}
