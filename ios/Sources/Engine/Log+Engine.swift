import os

/// Log categories the iOS app adds to the shared `Log`.
///
/// An extension rather than an edit to `mac/Sources/.../Core/Log.swift`: the Mac app has
/// no engine to log about, and the port does not touch files it cannot compile.
extension Log {
    /// Extraction: InnerTube calls, which client answered, player-script parsing.
    /// The one to read when a video will not resolve:
    ///   log stream --predicate 'subsystem == "com.moregroup.ytchannelscraper"'
    static let engine = Logger(subsystem: "com.moregroup.ytchannelscraper", category: "engine")
    /// Downloading and muxing.
    static let transfer = Logger(subsystem: "com.moregroup.ytchannelscraper", category: "transfer")
}
