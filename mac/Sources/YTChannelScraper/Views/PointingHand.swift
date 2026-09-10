import SwiftUI

/// macOS leaves the arrow cursor over everything, including custom-drawn controls, so
/// nothing on a hand-built surface signals that it can be clicked. This puts the hand
/// back over the things that act like buttons.
///
/// `NSCursor.pointingHand.push()` from `onHover` does not survive here: AppKit re-sets
/// the cursor on every mouse-moved event inside the view, so the hand is overwritten
/// almost immediately. `pointerStyle` hooks into that same machinery instead of fighting
/// it, which is why it sticks.
extension View {
    /// Show the pointing hand while the cursor is over this view.
    func pointingHand() -> some View {
        pointerStyle(.link)
    }
}
