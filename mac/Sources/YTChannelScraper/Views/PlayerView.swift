import AVFoundation
import AVKit
import AppKit
import SwiftUI

/// The video surface, wrapping AppKit's `AVPlayerView`.
///
/// SwiftUI's own `VideoPlayer` is not usable here: it lives in the `_AVKit_SwiftUI`
/// cross-import overlay, which Xcode links automatically but a SwiftPM-built executable
/// does not. Instantiating it aborts the process in `getSuperclassMetadata` trying to
/// resolve `AVPlayerView`'s metadata — a hard crash, not a warning. Referencing the
/// AppKit class directly sidesteps the overlay, and gives the transport controls too.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    /// Zoom the picture to cover the frame, cropping what overhangs, rather than fitting
    /// it whole inside black bars.
    var fills = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        let gravity: AVLayerVideoGravity = fills ? .resizeAspectFill : .resizeAspect
        if view.videoGravity != gravity { view.videoGravity = gravity }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        // Detach only — never pause. This view is torn down when the preview hands the
        // player to the island, and pausing here stopped playback the instant you
        // minimised the window. Lifecycle belongs to PreviewSession / MiniPlayer.
        view.player = nil
    }
}
