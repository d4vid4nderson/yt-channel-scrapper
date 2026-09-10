import AVFoundation
import AppKit
import SwiftUI

/// A bare video surface: an `AVPlayerLayer` and nothing else.
///
/// The inline preview uses `AVPlayerView` for its built-in transport controls, but the
/// mini player draws its own, so it wants the picture without any chrome.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    final class LayerBackedView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            // Layer-*backed* with the player layer as a sublayer, not layer-*hosting*
            // with `layer = playerLayer`. Replacing the root layer fights AppKit's own
            // layer management and flickers.
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            guard playerLayer.frame != bounds else { return }
            // The island resizes on hover and re-lays out several times a second while
            // the clock ticks; an implicitly animated frame change would wobble.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> LayerBackedView {
        let view = LayerBackedView(frame: .zero)
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: LayerBackedView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    static func dismantleNSView(_ view: LayerBackedView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}
