import AVFoundation
import Foundation

/// Playing a YouTube HLS stream at one chosen resolution, instead of the one AVPlayer
/// picks for itself.
///
/// AVPlayer has a ceiling (`preferredMaximumResolution`) but no floor: on a small window or
/// a busy connection it settles low and stays there, and there is no setting that says
/// "1080p, please". So the master playlist is handed to it through a custom URL scheme,
/// with every variant but the chosen height taken out — one rung on the ladder means
/// nothing to choose between. The media playlists it then points at are the real ones,
/// fetched as usual.
///
/// Only H.264 variants are kept or offered. YouTube lists VP9 too, up to 2160p, but
/// AVFoundation will not decode VP9 in HLS ("The media cannot be used on this computer"),
/// so above 1080p there is nothing it can play.
enum HLSVariants {
    /// The heights worth offering, highest first: those with an H.264 variant.
    static func heights(in playlist: String) -> [Int] {
        Set(playlist.split(separator: "\n").compactMap { line -> Int? in
            let line = String(line)
            guard isPlayable(line) else { return nil }
            return height(of: line)
        }).sorted(by: >)
    }

    /// An item that plays `master` at `height`. The loader is kept alive by the item, so
    /// it lasts exactly as long as the item does — wherever the player is moved to.
    static func item(master: URL, height: Int) -> AVPlayerItem {
        let loader = Loader(master: master, height: height)
        let asset = AVURLAsset(url: loader.url)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        let item = AVPlayerItem(asset: asset)
        objc_setAssociatedObject(item, &Loader.key, loader, .OBJC_ASSOCIATION_RETAIN)
        return item
    }

    static func height(of streamInf: String) -> Int? {
        guard streamInf.hasPrefix("#EXT-X-STREAM-INF"),
              let found = streamInf.range(of: "RESOLUTION=") else { return nil }
        let size = streamInf[found.upperBound...].prefix { $0 != "," }.split(separator: "x")
        return size.count == 2 ? Int(size[1]) : nil
    }

    private static func isPlayable(_ streamInf: String) -> Bool {
        streamInf.hasPrefix("#EXT-X-STREAM-INF") && streamInf.contains("avc1")
    }

    /// The playlist with only the chosen height's H.264 variants. Each `#EXT-X-STREAM-INF`
    /// is followed by its URI line, so dropping one means dropping the next line too.
    /// Renditions (`#EXT-X-MEDIA` — the audio groups, subtitles) all stay.
    static func filter(_ playlist: String, height: Int, base: URL) -> String {
        var kept: [String] = []
        var dropNextURI = false
        for raw in playlist.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if dropNextURI, !line.hasPrefix("#") {
                dropNextURI = false
                continue
            }
            if line.hasPrefix("#EXT-X-STREAM-INF"),
               !(isPlayable(line) && self.height(of: line) == height) {
                dropNextURI = true
                continue
            }
            // The playlist arrives under a made-up scheme, so a relative URI would resolve
            // against that; YouTube's are absolute, but this costs nothing.
            if !line.isEmpty, !line.hasPrefix("#"), URL(string: line)?.scheme == nil,
               let absolute = URL(string: line, relativeTo: base)?.absoluteString {
                kept.append(absolute)
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    private final class Loader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
        nonisolated(unsafe) static var key: UInt8 = 0
        static let scheme = "ytcs-hls"
        let master: URL
        let height: Int
        let queue = DispatchQueue(label: "ytcs.hls-variants")

        init(master: URL, height: Int) {
            self.master = master
            self.height = height
        }

        var url: URL {
            var parts = URLComponents(url: master, resolvingAgainstBaseURL: false)
            parts?.scheme = Self.scheme
            return parts?.url ?? master
        }

        func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                            shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest
        ) -> Bool {
            let master = master, height = height
            URLSession.shared.dataTask(with: master) { data, _, error in
                guard let data, let text = String(data: data, encoding: .utf8) else {
                    request.finishLoading(with: error ?? URLError(.badServerResponse))
                    return
                }
                let playlist = Data(HLSVariants.filter(text, height: height, base: master).utf8)
                request.contentInformationRequest?.contentType = "public.m3u-playlist"
                request.contentInformationRequest?.contentLength = Int64(playlist.count)
                request.contentInformationRequest?.isByteRangeAccessSupported = false
                request.dataRequest?.respond(with: playlist)
                request.finishLoading()
            }.resume()
            return true
        }
    }
}
