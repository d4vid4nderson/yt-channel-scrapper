import SwiftUI

/// The web app tinted its checkboxes with the brand red (`accent-color: var(--accent)`).
/// A system checkbox always follows the user's own accent colour — blue by default — so
/// the mark is drawn here to keep it red.
struct CheckBox: View {
    let isOn: Bool
    /// Picked rows sit on a dark surface, where a dim outline would disappear.
    var onPickedSurface = false
    var size: CGFloat = 17

    private var corner: CGFloat { size * 0.26 }

    var body: some View {
        ThemedRect(cornerRadius: corner, style: .continuous)
            .fill(isOn ? Palette.accent : .clear)
            .overlay {
                ThemedRect(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        isOn ? .clear : (onPickedSurface ? Palette.ink(0.4) : Palette.ink(0.32)),
                        lineWidth: 1.4
                    )
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.6, weight: .bold))
                        .foregroundStyle(Palette.onFill)
                }
            }
            .frame(width: size, height: size)
            .animation(.easeOut(duration: 0.12), value: isOn)
    }
}
