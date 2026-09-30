import AVKit
import SwiftUI

/// The system AirPlay button, for the Now Playing bar. The full player has its own —
/// `AVPlayerViewController` draws one — but the bar is where a video that is already
/// going lives, and that is when you think of sending it to the TV.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = UIColor(Color.primaryText)
        picker.activeTintColor = UIColor(Palette.accent)
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

/// Opening the AirPlay list without anyone tapping the button — what the widget's
/// AirPlay button asks for.
///
/// There is no API to present the route picker directly; the only way to it is an
/// `AVRoutePickerView` being tapped. So one is put in the window, invisibly, and its
/// button is pressed for it. That is the widely used route and relies on nothing
/// private — only on the picker's button being a `UIButton`, and if it ever stops being
/// one this quietly does nothing.
@MainActor
enum RoutePicker {
    private static var picker: AVRoutePickerView?

    static func present() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return }
        picker?.removeFromSuperview()
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        picker.prioritizesVideoDevices = true
        picker.alpha = 0.01
        window.addSubview(picker)
        self.picker = picker
        picker.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
    }
}
