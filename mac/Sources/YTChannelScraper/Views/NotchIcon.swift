import SwiftUI

/// A window with a notch.
///
/// Drawn rather than picked: SF Symbols has a panel icon for every edge of a window and
/// nothing for the notch, and the notch is the whole point here.
///
/// It is deliberately the toolbar drawer buttons' own drawing — an outlined window with
/// one filled region floating inside it — with that region moved to the top and cut short.
/// Short is the only thing telling the two apart, so it is cut to about a third of the
/// width, which is unmistakable at the 15pt this is actually used at.
///
/// The bar is held clear of the border rather than hung off it. Touching the stroke fuses
/// the two, and the pair then reads as a dent in the top edge instead of something sitting
/// at the top of a screen.
struct NotchIcon: View {
    var width: CGFloat = 17
    var lineWidth: CGFloat = 1.4

    private var height: CGFloat { (width * 0.72).rounded() }

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.22, style: .continuous)
            .strokeBorder(lineWidth: lineWidth)
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
                    .frame(width: width * 0.34, height: (height * 0.2).rounded())
                    .padding(.top, lineWidth + width * 0.07)
            }
            .accessibilityHidden(true)
    }
}
