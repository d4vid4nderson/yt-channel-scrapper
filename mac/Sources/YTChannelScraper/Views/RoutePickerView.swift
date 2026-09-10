import AVFoundation
import AVKit
import AppKit
import SwiftUI

/// The system AirPlay picker, bound to the player so routes apply to this video.
///
/// It has to be the real `AVRoutePickerView` — AirPlay device discovery and selection is
/// not something an app can reimplement, and the system button is what users recognise.
struct RoutePickerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        // Borderless and white, to sit with the island's own controls rather than
        // arriving as a stray system-grey button.
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVRoutePickerView, coordinator: ()) {
        view.player = nil
    }
}
