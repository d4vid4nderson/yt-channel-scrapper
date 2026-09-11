import Foundation

/// The one ffmpeg invocation the app makes for itself.
///
/// Everything else that needs ffmpeg goes through yt-dlp, which is handed
/// `--ffmpeg-location` and left to it. This is the exception: lifting an mp3 out of a
/// video that has already landed. That is the whole point of the option — the audio is
/// already on disk inside the video, so a second file costs a re-encode rather than a
/// second trip past YouTube's gating, which is the slow and failure-prone half.
enum FFmpeg {
    static var executable: URL { Paths.vendor.appendingPathComponent("ffmpeg") }

    /// The mp3 that sits beside a downloaded video: same name, different extension.
    static func mp3Path(for video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("mp3")
    }

    /// 192 kbps to match what the audio-only quality asks yt-dlp for, so which route the
    /// mp3 came by makes no difference to the file.
    ///
    /// `-vn` drops the video — without it ffmpeg carries the first frame over as cover
    /// art and the "mp3" is a video file wearing the wrong extension. `-nostdin` keeps
    /// ffmpeg from reaching for a terminal that is not there.
    static func mp3Arguments(from source: URL, to destination: URL) -> [String] {
        ["-nostdin", "-hide_banner", "-loglevel", "error", "-y",
         "-i", source.path,
         "-vn", "-c:a", "libmp3lame", "-b:a", "192k",
         destination.path]
    }
}
