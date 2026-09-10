import Foundation
import os

/// Diagnostics that survive a launch from Finder, where stdout goes nowhere.
///
/// Read them back with:
///   log show --last 10m --predicate 'subsystem == "com.moregroup.ytchannelscraper"'
enum Log {
    static let preview = Logger(subsystem: "com.moregroup.ytchannelscraper", category: "preview")
    static let updater = Logger(subsystem: "com.moregroup.ytchannelscraper", category: "updater")
    static let icon = Logger(subsystem: "com.moregroup.ytchannelscraper", category: "icon")
}
