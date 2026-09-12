import SwiftUI

@main
struct YTScraperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // Downloads run on a background `URLSession`, which means the system may finish
        // one while this app is suspended and then relaunch it just to hand the results
        // over. Without this the app has nowhere to receive that and iOS logs a warning
        // about a session with no handler; with it, `Transfer`'s delegate gets its
        // callbacks and the job finishes as if the app had been open all along.
        .backgroundTask(.urlSession(Transfer.sessionIdentifier)) {
            await Transfer.shared.discardOrphans()
        }
    }
}
