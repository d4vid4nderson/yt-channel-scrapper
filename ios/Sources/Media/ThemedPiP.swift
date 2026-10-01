import AVKit
import CoreMedia
import CoreVideo
import os
import SwiftUI
import UIKit

/// Picture in Picture wearing the theme.
///
/// AVKit's own PiP floats the bare video in a window the system draws, and nothing about
/// it can be styled. The one PiP an app draws the content of is the sample-buffer kind:
/// the app hands over finished frames, and the system floats those. So every frame of the
/// playing video is pulled off the player (`AVPlayerItemVideoOutput`), has the theme
/// drawn onto it — a frame in the accent, rounded to the PiP window's own corners, glowing
/// on the neon themes, and an accent progress line along the foot — and is handed to an
/// `AVSampleBufferDisplayLayer` that PiP floats. The same layer sits over the player on
/// screen, so the video wears the frame in the app too, and swiping home carries it out.
///
/// The drawing is CPU work on a copy the player already made, a few hundred pixels of
/// stroke per frame — no GPU, which a backgrounded app is not allowed. The system still
/// draws its own buttons over the window: those cannot be themed by anyone.
///
/// A first attempt used the video-call content source instead; iOS would not start it
/// for a player.
@MainActor
final class ThemedPiP: NSObject, AVPictureInPictureControllerDelegate,
                       AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = ThemedPiP()

    /// The view whose layer PiP floats, hung over the player's video.
    private let host = DisplayView()
    private var controller: AVPictureInPictureController?
    private var pump: FramePump?
    private var player: AVPlayer?
    private var statusWatch: NSKeyValueObservation?

    private var layer: AVSampleBufferDisplayLayer { host.displayLayer }

    /// Put the themed layer over `overlay` and get ready to float `player`. With the
    /// player on screen, swiping home starts it.
    /// False when it cannot — no PiP on this device, or no item yet — and the caller
    /// keeps AVKit's own instead.
    @discardableResult
    func attach(player: AVPlayer, over overlay: UIView) -> Bool {
        #if targetEnvironment(simulator)
        // The simulator has no PiP, but the frames can still be drawn and checked there:
        // the themed border on the player in the app is this same pipeline.
        let supported = true
        #else
        let supported = AVPictureInPictureController.isPictureInPictureSupported()
        #endif
        guard supported, let item = player.currentItem else {
            Log.preview.info("pip: themed unavailable, keeping AVKit's")
            return false
        }

        if self.player !== player {
            // Before the layer goes up, not after: tearing down the last player takes the
            // layer down with it.
            detach()
        }
        host.frame = overlay.bounds
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if host.superview !== overlay { overlay.addSubview(host) }
        guard self.player !== player else { return true }
        self.player = player

        layer.videoGravity = .resizeAspect
        // The window's scrubber and the frames' timing both follow the item's own clock.
        layer.controlTimebase = item.timebase

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        let pump = FramePump(output: output, renderer: layer.sampleBufferRenderer,
                             style: FrameStyle(theme: Theme.active))
        pump.duration = item.duration.seconds
        pump.start()
        self.pump = pump

        let controller = AVPictureInPictureController(contentSource:
            .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        self.controller = controller
        Log.preview.info("pip attached")

        // Play/pause from anywhere — the widget, the Lock Screen — shows on the window,
        // and a duration that arrives late reaches the progress line.
        statusWatch = player.observe(\.timeControlStatus) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.player === player else { return }
                self.pump?.duration = player.currentItem?.duration.seconds ?? .nan
                self.controller?.invalidatePlaybackState()
            }
        }
        return true
    }

    func detach() {
        statusWatch = nil
        controller?.stopPictureInPicture()
        controller = nil
        pump?.stop()
        pump = nil
        player = nil
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        host.removeFromSuperview()
    }

    // MARK: - The window's buttons

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, setPlaying playing: Bool
    ) {
        MainActor.assumeIsolated {
            playing ? player?.play() : player?.pause()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        MainActor.assumeIsolated {
            guard let duration = player?.currentItem?.duration, duration.isNumeric else {
                return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
            }
            return CMTimeRange(start: .zero, duration: duration)
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController
    ) -> Bool {
        MainActor.assumeIsolated { (player?.rate ?? 0) == 0 }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated {
            NowPlaying.shared.skip(by: skipInterval.seconds)
        }
        completionHandler()
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let ns = error as NSError
        Log.preview.error("pip failed to start: \(ns.domain, privacy: .public) \(ns.code) \(ns.localizedDescription, privacy: .public)")
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Log.preview.info("pip started")
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void
    ) {
        completion(true)
    }
}

/// A view whose layer is the display layer, so it sizes with the player it sits over.
private final class DisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// The theme, resolved to what drawing on a frame needs — read once, on the main actor.
private struct FrameStyle: Sendable {
    let accent: CGColor
    let track: CGColor
    let glow: Bool

    @MainActor
    init(theme: Theme) {
        let traits = UITraitCollection(userInterfaceStyle: theme.colorScheme == .light ? .light : .dark)
        let accent = UIColor(theme.accent).resolvedColor(with: traits)
        self.accent = accent.cgColor
        self.track = accent.withAlphaComponent(0.3).cgColor
        if case .neon = theme.edge { glow = true } else { glow = false }
    }
}

/// Pulls frames off the player, draws the theme on them and hands them on, thirty times
/// a second, on a queue of its own. Runs with the app in the background as well — the
/// player keeps it alive, and none of the work touches the GPU.
private final class FramePump: @unchecked Sendable {
    private let output: AVPlayerItemVideoOutput
    private let renderer: AVSampleBufferVideoRenderer
    private let style: FrameStyle
    private let queue = DispatchQueue(label: "ytcs.pip.frames", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let durationLock = OSAllocatedUnfairLock(initialState: Double.nan)
    private var frames = 0
    #if DEBUG
    private var startedAt: CFTimeInterval = 0
    #endif

    /// Seconds, for the progress line; NaN until the item knows.
    var duration: Double {
        get { durationLock.withLock { $0 } }
        set { durationLock.withLock { $0 = newValue } }
    }

    init(output: AVPlayerItemVideoOutput, renderer: AVSampleBufferVideoRenderer, style: FrameStyle) {
        self.output = output
        self.renderer = renderer
        self.style = style
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        // A display that is still showing the last frame does not need another queued
        // behind it; skipping keeps the queue from growing while it catches up.
        guard renderer.isReadyForMoreMediaData else { return }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }

        let duration = self.duration
        let fraction = duration.isFinite && duration > 0
            ? min(max(itemTime.seconds / duration, 0), 1) : 0
        decorate(buffer, progress: fraction)

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: itemTime,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        // Shown as it arrives: the frame was chosen for this moment already.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0),
                                           to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        if renderer.status == .failed {
            let reason = renderer.error?.localizedDescription ?? "unknown"
            Log.preview.error("pip renderer failed: \(reason, privacy: .public)")
            renderer.flush()
        }
        renderer.enqueue(sample)
        frames += 1
        #if DEBUG
        if frames == 1 { startedAt = CACurrentMediaTime() }
        if frames == 150 {
            let fps = 149 / (CACurrentMediaTime() - startedAt)
            Log.preview.info("pip rate: \(String(format: "%.1f", fps), privacy: .public) fps")
        }
        #endif
        if frames == 1 {
            let size = "\(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))"
            Log.preview.info("pip frames flowing, \(size, privacy: .public)")
        }
    }

    /// The frame and the progress line, drawn straight onto the pixels.
    private func decorate(_ buffer: CVPixelBuffer, progress: Double) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: base, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }

        // Sized to the frame, so a 360p stream and a 1080p one look the same in the window.
        let unit = CGFloat(min(width, height)) / 120
        let line = max(2, unit * 1.6)
        let inset = line / 2 + unit
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
            .insetBy(dx: inset, dy: inset)

        // Rounded whatever the theme's corners: iOS rounds the PiP window itself and
        // clips whatever is drawn under its corners, so a square or chamfered frame loses
        // its corners there. The curve is concentric with the window's — about 4% of the
        // width, a touch rounder than the system's, so it is never clipped at any size.
        let windowRadius = CGFloat(width) * 0.04
        let radius = max(windowRadius - inset, line)
        context.setStrokeColor(style.accent)
        context.setLineWidth(line)
        if style.glow { context.setShadow(offset: .zero, blur: unit * 3, color: style.accent) }
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                               transform: nil))
        context.strokePath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        // CoreGraphics counts up from the bottom, which is where the line goes.
        let barHeight = max(2, unit * 1.2)
        let track = CGRect(x: rect.minX + unit * 4, y: rect.minY + unit * 3,
                           width: rect.width - unit * 8, height: barHeight)
        context.setFillColor(style.track)
        context.fill(track)
        context.setFillColor(style.accent)
        context.fill(CGRect(x: track.minX, y: track.minY,
                            width: track.width * progress, height: barHeight))
    }
}
