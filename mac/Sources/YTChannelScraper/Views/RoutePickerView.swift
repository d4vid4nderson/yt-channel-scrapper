import AVFoundation
import AVKit
import AppKit
import SwiftUI

/// The system AirPlay picker, bound to the player so routes apply to this video.
///
/// It has to be the real `AVRoutePickerView` — AirPlay device discovery and selection is
/// not something an app can reimplement, and the system button is what users recognise.
///
/// It also reports when its route list is on screen. The island it sits in collapses when
/// the cursor leaves, and the list it presents hangs below the island, so without this the
/// act of reaching for a device dismisses the thing you were reaching from.
struct RoutePickerView: NSViewRepresentable {
    let player: AVPlayer
    /// Draw the system glyph, or stay invisible and serve purely as the click target over
    /// a row we drew ourselves.
    ///
    /// Invisible is how the output list offers AirPlay without a second button: its
    /// button fills whatever frame the view is given, so laid over a row it turns that
    /// whole row into the system picker while our own icon and label are what you see.
    var showsGlyph = true
    /// `true` while the route list is up, `false` once it has gone.
    let isPresentingRoutes: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(report: isPresentingRoutes)
    }

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.delegate = context.coordinator
        // Borderless and white, to sit with the island's own controls rather than
        // arriving as a stray system-grey button.
        view.isRoutePickerButtonBordered = false
        let colour: NSColor = showsGlyph ? .white : .clear
        for state in [AVRoutePickerView.ButtonState.normal, .normalHighlighted,
                      .active, .activeHighlighted] {
            view.setRoutePickerButtonColor(colour, for: state)
        }
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        context.coordinator.report = isPresentingRoutes
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVRoutePickerView, coordinator: Coordinator) {
        view.delegate = nil
        view.player = nil
    }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var report: (Bool) -> Void

        init(report: @escaping (Bool) -> Void) {
            self.report = report
        }

        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            report(true)
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            report(false)
        }
    }
}
