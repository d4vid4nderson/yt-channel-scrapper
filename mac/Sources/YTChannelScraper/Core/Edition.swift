import Foundation

/// Which build this is: the family's own, or the one shared with other people.
///
/// The shared edition is the scraper and player on their own — search, browse, preview,
/// download, saved channels — with everything about guardians, children and their phones
/// switched off: no Users panel, no Dispatch board, no Send-to-a-child on rows, no reads
/// of the shared family folder. It is ad-hoc signed, so it has no iCloud either.
///
/// Set at build time (`build-mac-app.sh --shared` writes `YTCSEdition` into Info.plist),
/// read here, so both are one codebase. A build with no key — `swift run`, every family
/// build — is the family edition.
enum Edition {
    static let isShared =
        Bundle.main.object(forInfoDictionaryKey: "YTCSEdition") as? String == "shared"
    static var isFamily: Bool { !isShared }

    /// What the edition's disk images are called on a release, so each copy's updater
    /// takes its own and never the other's.
    static let diskTag = "shared"
}
