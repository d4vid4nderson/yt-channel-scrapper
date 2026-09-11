import Foundation
import JavaScriptCore

/// Solving YouTube's player JavaScript, which is what the Mac app bundles Deno for.
///
/// Deno cannot ship on iOS — V8 needs JIT, and `MAP_JIT` is behind an entitlement no
/// third-party app gets. JavaScriptCore can: it is Apple's own framework, and for an
/// app without the JIT entitlement it runs the interpreter. That is slower than V8 by a
/// wide margin and completely irrelevant here, because the two functions involved are a
/// few thousand operations each and run once per video.
///
/// ## This is the fallback, not the main path
///
/// `InnerTube.playerLadder` tries three clients that hand over plain URLs before it
/// reaches the web client that needs any of this. So when YouTube next reshapes
/// `base.js` and the patterns below stop matching, the app keeps working — it loses the
/// web client's rung, which mostly costs the highest resolutions on the videos the
/// mobile clients refuse. Worth knowing before spending an evening on a regex.
///
/// ## Status: this rung does not currently fire
///
/// Measured against the live player on 2026-09-11 (build `8c3fda2d`, 2.96 MB), and
/// worth knowing before you spend an evening on a regex:
///
/// - There is no `a=a.split("")` anywhere in it, and no `enhanced_except`, no
///   `String.fromCharCode(110)`, no `.get("n")` belonging to the transform. The single
///   literal `.get("n")` in the file is an HLS path rewriter, not the solver.
/// - The player now hoists its string constants into **four** tables and indexes them
///   with values computed at run time — `H5[A^4028]`, where `A` arrives as an argument.
///   So the operation names the old patterns matched on ("split", "reverse", "n") are
///   no longer *in* the functions that use them.
///
/// Name-based static extraction cannot see through that, so `Patterns` finds nothing
/// and this rung stays inert. That is survivable rather than fatal because the web
/// client is last in `InnerTube.playerLadder` and the three ahead of it hand over plain
/// URLs — the cost is the videos only the web client would have served.
///
/// The code is kept because it costs nothing when it fails, because it is the scaffold
/// to fix if YouTube tightens the mobile clients, and because
/// `ios/Tools/check-patterns.py` reports in a few seconds whether it has started
/// working again. yt-dlp's `yt_dlp/extractor/youtube/_video.py` is the reference to
/// follow — it gets through this by *interpreting* the JavaScript rather than pattern
/// matching it, which is the direction to go if this rung ever has to work.
actor JSChallenge {
    static let shared = JSChallenge()

    /// Keyed by the player hash in the script URL, so the parse and the JS evaluation
    /// happen once per player build rather than once per video.
    private var solvers: [String: JSSolver] = [:]
    private var scriptHash: String?
    private var scriptHashFetchedAt: Date?

    /// How long a player hash is trusted before it is looked up again. YouTube ships a
    /// new player a few times a week; an hour keeps a long session from going stale
    /// without asking on every video.
    private static let hashLifetime: TimeInterval = 3600

    // MARK: - Getting one

    func solver() async throws -> JSSolver {
        let hash = try await currentScriptHash()
        if let cached = solvers[hash] { return cached }

        let url = URL(string:
            "https://www.youtube.com/s/player/\(hash)/player_ias.vflset/en_US/base.js")!
        let source = try await InnerTube.get(url, client: InnerTube.webClient)

        let solver = try JSSolver(
            prelude: Patterns.globalPrelude(in: source),
            signature: Patterns.signatureFunction(in: source),
            transform: Patterns.transformFunction(in: source)
        )
        solvers[hash] = solver
        Log.engine.info("player \(hash, privacy: .public) parsed")
        return solver
    }

    /// The hash in the current player's URL.
    ///
    /// Read from `/iframe_api`, which is a few kilobytes and names the player, rather
    /// than from a watch page, which is around a megabyte and names the same thing.
    private func currentScriptHash() async throws -> String {
        if let scriptHash, let fetchedAt = scriptHashFetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.hashLifetime {
            return scriptHash
        }
        let source = try await InnerTube.get(
            URL(string: "https://www.youtube.com/iframe_api")!,
            client: InnerTube.webClient
        )
        guard let hash = Patterns.playerHash(in: source) else { throw Failure.noPlayer }
        scriptHash = hash
        scriptHashFetchedAt = Date()
        return hash
    }

    enum Failure: LocalizedError {
        case noPlayer
        case noFunctions
        case evaluation(String)

        var errorDescription: String? {
            switch self {
            case .noPlayer:
                "Could not find YouTube's player script."
            case .noFunctions:
                "YouTube's player script has changed shape — the solver needs updating."
            case .evaluation(let message):
                "The player script would not run: \(message)"
            }
        }
    }
}

/// The two functions lifted out of `base.js`, evaluated and ready to call.
///
/// A top-level class rather than one nested in the actor because it has to cross the
/// actor boundary — `StreamResolver` holds one while it decodes a response's formats —
/// and so has to be `Sendable`. `JSContext` is not thread-safe and the compiler cannot
/// see that the lock below is what makes this safe, hence `@unchecked`.
final class JSSolver: @unchecked Sendable {
    private let context = JSContext()!
    private let lock = NSLock()
    private let hasSignature: Bool
    private let hasTransform: Bool

    /// Throws only if `base.js` yielded neither function, which means `Patterns` needs
    /// updating and the caller should fall back to another client rather than retry.
    init(prelude: String, signature: String?, transform: String?) throws {
        hasSignature = signature != nil
        hasTransform = transform != nil
        guard hasSignature || hasTransform else { throw JSChallenge.Failure.noFunctions }

        var thrown: String?
        context.exceptionHandler = { _, exception in
            thrown = exception?.toString() ?? "unknown JS error"
        }

        // `prelude` is the hoisted string table modern players keep their operations in;
        // without it the extracted functions reference an undefined global and every
        // call returns undefined rather than throwing, which is much harder to notice.
        var source = prelude
        if let signature { source += "\nvar __ytcsSig = \(signature);" }
        if let transform { source += "\nvar __ytcsN = \(transform);" }
        context.evaluateScript(source)
        if let thrown { throw JSChallenge.Failure.evaluation(thrown) }
    }

    /// Unscramble a format's `s` parameter into the `sig` the URL needs.
    func signature(_ scrambled: String) -> String? {
        guard hasSignature else { return nil }
        return call("__ytcsSig", with: scrambled)
    }

    /// Run the throttling parameter through the transform. Skipping this does not fail
    /// the request — it succeeds and then trickles at about 50 KB/s, which is the
    /// symptom to recognise if this ever silently stops working.
    func transformN(_ value: String) -> String? {
        guard hasTransform else { return nil }
        guard let result = call("__ytcsN", with: value) else { return nil }
        // A transform that hits its own error path returns the input prefixed with
        // "enhanced_except_" — a real result, but one that would still be throttled.
        return result.hasPrefix("enhanced_except_") || result == value ? nil : result
    }

    private func call(_ name: String, with argument: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let function = context.objectForKeyedSubscript(name),
              !function.isUndefined,
              let result = function.call(withArguments: [argument]),
              !result.isUndefined, !result.isNull
        else { return nil }
        let string = result.toString()
        return (string?.isEmpty ?? true) ? nil : string
    }
}
