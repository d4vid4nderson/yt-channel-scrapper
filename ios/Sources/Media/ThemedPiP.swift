import AVKit
import SwiftUI
import UIKit

/// Picture in Picture wearing the theme.
///
/// The standard PiP window is iOS's and cannot be styled — it is `AVPlayerViewController`
/// handing the bare video to the system. The only PiP that lets an app draw its own
/// content is the video-call kind: the app supplies a view controller, and the system
/// floats *that*. So this is a video-call PiP whose "call" is the player: the same
/// `AVPlayer` shown through a second layer, inside the theme's ground, framed in its
/// accent and cut to its corners, with the accent drawn along the foot as progress.
///
/// What it gives up: a call window gets no transport buttons from iOS, only close and
/// back-to-app. Play, pause and skip are still on the widgets, the Lock Screen and
/// Control Centre, which all drive this same player. It is also a use of the call API
/// for something that is not a call, which is fine for a family's own phones and is the
/// kind of thing a future iOS could tighten — if PiP stops appearing after an update,
/// this is where to look.
@MainActor
final class ThemedPiP: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = ThemedPiP()

    private var controller: AVPictureInPictureController?
    private var content: ThemedPiPContent?
    private weak var player: AVPlayer?

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// Get ready to float `player`, animating out of and back into `source`. Called when
    /// the player's stage is built; with the stage on screen, swiping home starts it.
    func attach(player: AVPlayer, source: UIView) {
        guard isSupported else { return }
        if self.player === player, controller != nil { return }
        detach()
        self.player = player

        let content = ThemedPiPContent(player: player)
        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: source, contentViewController: content)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        self.content = content
        self.controller = controller
    }

    func detach() {
        controller?.stopPictureInPicture()
        controller = nil
        content = nil
        player = nil
    }

    /// The player screen's PiP button.
    func start() {
        content?.fitToVideo()
        controller?.startPictureInPicture()
    }

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        MainActor.assumeIsolated { content?.fitToVideo() }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void
    ) {
        completion(true)
    }
}

/// What floats: the theme's ground, the video, an accent frame, a progress line.
final class ThemedPiPContent: AVPictureInPictureVideoCallViewController {
    // Touched from `deinit` to take the time observer off, which is nonisolated; nothing
    // else reaches either off the main thread.
    nonisolated(unsafe) private let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private let frameLayer = CAShapeLayer()
    private let track = CALayer()
    private let progress = CALayer()
    nonisolated(unsafe) private var timeObserver: Any?

    private static let inset: CGFloat = 3
    private static let barHeight: CGFloat = 3

    init(player: AVPlayer) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = Theme.active
        view.backgroundColor = UIColor(Palette.ground)

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
        view.layer.addSublayer(playerLayer)

        frameLayer.fillColor = UIColor.clear.cgColor
        frameLayer.strokeColor = UIColor(Palette.accent).cgColor
        frameLayer.lineWidth = 2
        view.layer.addSublayer(frameLayer)

        track.backgroundColor = UIColor(Palette.accent).withAlphaComponent(0.25).cgColor
        progress.backgroundColor = UIColor(Palette.accent).cgColor
        view.layer.addSublayer(track)
        view.layer.addSublayer(progress)

        // Glow, where the theme has one — the neon themes' edge, in miniature.
        if case .neon = theme.edge {
            frameLayer.shadowColor = UIColor(Palette.accent).cgColor
            frameLayer.shadowOpacity = 0.9
            frameLayer.shadowRadius = 4
            frameLayer.shadowOffset = .zero
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutProgress() }
        }
        fitToVideo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let inner = bounds.insetBy(dx: Self.inset, dy: Self.inset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = inner
        let path = Self.outline(inner, corners: Theme.active.corners)
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.frame = CGRect(origin: CGPoint(x: -inner.minX, y: -inner.minY), size: bounds.size)
        playerLayer.mask = mask
        frameLayer.path = path.cgPath
        track.frame = CGRect(x: inner.minX + 8, y: inner.maxY - Self.barHeight - 6,
                             width: inner.width - 16, height: Self.barHeight)
        track.cornerRadius = Self.barHeight / 2
        progress.cornerRadius = Self.barHeight / 2
        CATransaction.commit()
        layoutProgress()
    }

    /// The window takes the video's shape, so the frame hugs the picture rather than
    /// boxing a letterbox.
    func fitToVideo() {
        let size = player.currentItem?.presentationSize ?? .zero
        let ratio = size.width > 0 && size.height > 0 ? size.width / size.height : 16.0 / 9.0
        preferredContentSize = CGSize(width: 1000, height: 1000 / ratio)
    }

    private func layoutProgress() {
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds
        let now = player.currentTime().seconds
        let fraction = duration.isFinite && duration > 0 && now.isFinite
            ? min(max(now / duration, 0), 1) : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var frame = track.frame
        frame.size.width *= fraction
        progress.frame = frame
        CATransaction.commit()
    }

    /// The theme's corners, the same cut `ThemedRect` makes.
    private static func outline(_ rect: CGRect, corners: Theme.Corners) -> UIBezierPath {
        switch corners {
        case .square:
            return UIBezierPath(rect: rect)
        case .rounded(let scale):
            return UIBezierPath(roundedRect: rect, cornerRadius: 10 * scale)
        case .chamfered(let scale):
            let c = min(10 * scale, min(rect.width, rect.height) / 2)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
            path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
            path.close()
            return path
        }
    }
}
