import UniformTypeIdentifiers

extension UTType {
    /// The exported library. Declared in the bundle's Info.plist too, which is what gives
    /// it an icon in the Finder and makes double-clicking one open the app.
    static let ytcsLibrary = UTType(
        exportedAs: "com.d4vid4nderson.ytchannelscraper.library",
        conformingTo: .json
    )
}
