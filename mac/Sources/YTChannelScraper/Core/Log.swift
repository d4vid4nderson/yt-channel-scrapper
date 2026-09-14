import Foundation
import os

/// Diagnostics that survive a launch from Finder, where stdout goes nowhere.
///
/// Read them back with:
///   log show --last 10m --predicate 'subsystem == "com.d4vid4nderson.ytchannelscraper"'
enum Log {
    static let preview = Logger(subsystem: "com.d4vid4nderson.ytchannelscraper", category: "preview")
    static let updater = Logger(subsystem: "com.d4vid4nderson.ytchannelscraper", category: "updater")
    static let icon = Logger(subsystem: "com.d4vid4nderson.ytchannelscraper", category: "icon")
    static let library = Logger(subsystem: "com.d4vid4nderson.ytchannelscraper", category: "library")
}
