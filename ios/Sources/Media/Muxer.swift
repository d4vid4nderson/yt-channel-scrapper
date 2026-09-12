import AVFoundation
import Foundation

/// Putting a downloaded video and its audio into one file, without ffmpeg.
///
/// The Mac app hands two streams to a vendored ffmpeg and lets it mux them. There is no
/// ffmpeg here — it cannot be shipped as a binary to exec, and linking it as a library
/// would mean carrying an LGPL build and a build script for a job AVFoundation already
/// does. `AVMutableComposition` puts the two tracks on one timeline and
/// `AVAssetExportSession` writes them out; with the passthrough preset nothing is
/// re-encoded, so this is a remux at disk speed rather than a transcode.
///
/// The catch, and it is the reason `StreamResolver.Stream.isMuxable` exists: passthrough
/// into an MP4 only works for codecs the MP4 container is allowed to hold, which for
/// AVFoundation means H.264/HEVC video and AAC audio. YouTube's VP9, AV1 and Opus
/// streams cannot go in, so they are never chosen in the first place. Selecting them and
/// discovering it here would mean failing at the end of a long download.
enum Muxer {

    /// Stitch `video` and `audio` into one `.mp4` at `destination`.
    static func combine(video: URL, audio: URL?, into destination: URL) async throws {
        let videoAsset = AVURLAsset(url: video)

        guard let audio else {
            // Video with no separate audio: still an export rather than a move, because
            // the downloaded stream is a raw fragmented MP4 and some players will not
            // seek in one until it has been rewritten with a proper index.
            try await export(videoAsset, to: destination, as: .mp4)
            return
        }

        let audioAsset = AVURLAsset(url: audio)
        let composition = AVMutableComposition()

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first else { throw Failure.noVideoTrack }

        guard let videoSlot = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.noVideoTrack }

        let span = try await videoAsset.load(.duration)
        try videoSlot.insertTimeRange(CMTimeRange(start: .zero, duration: span),
                                      of: videoTrack, at: .zero)
        // Carry the track's transform, or a video shot in portrait — every Short —
        // comes out rotated.
        videoSlot.preferredTransform = try await videoTrack.load(.preferredTransform)

        if let audioTrack = audioTracks.first,
           let audioSlot = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            // The audio stream is routinely a few milliseconds shorter or longer than
            // the video. Inserting the video's exact range would throw on the short
            // case, so the shorter of the two is used and any remainder dropped —
            // inaudible, and the alternative is no file at all.
            let audioSpan = try await audioAsset.load(.duration)
            let usable = CMTimeMinimum(span, audioSpan)
            try audioSlot.insertTimeRange(CMTimeRange(start: .zero, duration: usable),
                                          of: audioTrack, at: .zero)
        }

        try await export(composition, to: destination, as: .mp4)
    }

    /// Write the audio stream out on its own as an `.m4a`.
    ///
    /// The Mac transcodes to mp3 with a vendored lame. This does not: YouTube's audio
    /// stream is already AAC, so passthrough into an m4a copies it untouched. That is
    /// faster, lossless relative to the source, and a better file than a re-encode —
    /// mp3 would mean decoding and re-encoding for nothing but the extension.
    static func extractAudio(from source: URL, into destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw Failure.noAudioTrack
        }
        try await export(asset, to: destination, as: .m4a)
    }

    // MARK: - Export

    private static func export(
        _ asset: AVAsset,
        to destination: URL,
        as type: AVFileType
    ) async throws {
        // An export refuses to start if anything is already at the destination.
        try? FileManager.default.removeItem(at: destination)

        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetPassthrough
        ) else { throw Failure.noExporter }

        guard session.supportedFileTypes.contains(type) else {
            // Reached only if format selection let a codec through that the container
            // cannot hold — see `StreamResolver.Stream.isMuxable`.
            throw Failure.unsupportedCodec
        }

        session.outputURL = destination
        session.outputFileType = type
        // Lets a long video start playing before it has finished downloading elsewhere,
        // and costs nothing on a passthrough export.
        session.shouldOptimizeForNetworkUse = true

        // `export(to:as:)` is iOS 18 and this app runs on 17, so the completion-handler
        // form is bridged by hand. Deprecated, not gone.
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }

        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? Failure.exportFailed
        }
    }

    enum Failure: LocalizedError {
        case noVideoTrack
        case noAudioTrack
        case noExporter
        case unsupportedCodec
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                "The downloaded video stream had no video in it."
            case .noAudioTrack:
                "That stream carries no audio to save."
            case .noExporter:
                "Could not start the export."
            case .unsupportedCodec:
                "That video is only offered in a format this app cannot save "
                    + "(AV1 or VP9). Try a different quality."
            case .exportFailed:
                "Combining the video and audio failed."
            }
        }
    }
}
