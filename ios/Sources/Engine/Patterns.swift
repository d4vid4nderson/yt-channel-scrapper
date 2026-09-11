import Foundation

/// Lifting the two interesting functions out of YouTube's minified `base.js`.
///
/// Everything in this file is pattern-matching against code that is deliberately
/// obfuscated and re-minified weekly. It is the one part of the engine expected to rot,
/// and it is all in one file for exactly that reason: when the highest resolutions stop
/// working, this is the file to compare against yt-dlp's `_video.py`.
///
/// The patterns are written as lists tried in order, oldest-shape last, so adding a new
/// one is a single line rather than a rewrite.
enum Patterns {

    // MARK: - The signature cipher

    /// `a=a.split("")` is the giveaway: the signature function is the only one that
    /// takes a string, splits it to an array, shuffles it and joins it back.
    private static let signatureNamePatterns = [
        #"(?:\b|[^a-zA-Z0-9$])([a-zA-Z0-9$]{2,})\s*=\s*function\(\s*([a-zA-Z0-9$]+)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(\s*""\s*\)"#,
        #"function\s+([a-zA-Z0-9$]{2,})\s*\(\s*([a-zA-Z0-9$]+)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(\s*""\s*\)"#,
        #"\bm=([a-zA-Z0-9$]{2,})\(decodeURIComponent\(h\.s\)\)"#,
        #"\bc&&\(c=([a-zA-Z0-9$]{2,})\(decodeURIComponent\(c\)\)"#,
    ]

    /// The signature function plus the helper object it shuffles with.
    ///
    /// The function body alone is useless: it is three or four calls into a separate
    /// object of tiny reverse/swap/splice operations (`Xy.ab(a,3)`), and without that
    /// object every call throws. So the object is found by looking at what the body
    /// actually calls and pulled in alongside.
    /// What a call into the helper object looks like, and — just as importantly — what
    /// it does not.
    ///
    /// The receiver is required to be two characters or more and the argument list to be
    /// `(a)` or `(a,3)`. Both constraints earn their keep: the signature function opens
    /// with `a=a.split("")` and closes with `a.join("")`, and a looser pattern picks the
    /// single-character argument `a` out of those as the helper object's name, finds no
    /// such object, and silently returns a function that throws on every call.
    private static let helperCallPattern =
        #"([a-zA-Z0-9$_]{2,})\.[a-zA-Z0-9$_]{2,}\(\s*[a-zA-Z0-9$_]+\s*(?:,\s*\d+\s*)?\)"#

    static func signatureFunction(in source: String) -> String? {
        guard let name = firstGroup(signatureNamePatterns, in: source, group: 1),
              let body = function(named: name, in: source)
        else { return nil }

        // The first `Ident.method(` inside the body names the helper object.
        guard let helperName = firstGroup([helperCallPattern], in: body, group: 1),
              let helper = objectLiteral(named: helperName, in: source)
        else {
            // Some builds inline the operations. The body stands alone then.
            return body
        }
        return "(function(){ var \(helperName) = \(helper); return \(body); })()"
    }

    // MARK: - The throttling transform

    /// Finding the `n` function is a two-step: the player reads the parameter, then
    /// calls the transform — sometimes by name, and increasingly through an index into
    /// an array of functions, which is the obfuscation that keeps the name from being
    /// greppable.
    private static let transformCallPatterns = [
        #"[;\n]\s*[a-zA-Z0-9$_]+\s*=\s*(?:[a-zA-Z0-9$_]+\.)?get\(\s*"n"\s*\)\s*\)?\s*&&\s*\([a-zA-Z0-9$_]+\s*=\s*([a-zA-Z0-9$_]+)(?:\[(\d+)\])?\s*\("#,
        #"\.get\(\s*"n"\s*\)\s*\)\s*&&\s*\([a-zA-Z0-9$_]+\s*=\s*([a-zA-Z0-9$_]+)(?:\[(\d+)\])?\s*\("#,
        #"[a-zA-Z0-9$_]+\s*=\s*"nn"\[\+[a-zA-Z0-9$_.]+\]\s*,\s*[a-zA-Z0-9$_]+\s*=\s*[a-zA-Z0-9$_]+\.get\([a-zA-Z0-9$_]+\)\s*\)\s*&&\s*\([a-zA-Z0-9$_]+\s*=\s*([a-zA-Z0-9$_]+)(?:\[(\d+)\])?\s*\("#,
    ]

    static func transformFunction(in source: String) -> String? {
        for pattern in transformCallPatterns {
            guard let match = capture(pattern, in: source) else { continue }
            guard let name = match[1] else { continue }

            // `NAME(b)` — a direct call, the name is the function.
            guard let indexText = match[2], let index = Int(indexText) else {
                if let body = function(named: name, in: source) { return body }
                continue
            }

            // `NAME[3](b)` — an array of functions. Resolve the slot: it is either a
            // reference to a named function declared elsewhere, or a function literal
            // sitting in the array.
            guard let elements = arrayElements(named: name, in: source),
                  index < elements.count
            else { continue }
            let element = elements[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if element.hasPrefix("function") { return element }
            if let body = function(named: element, in: source) { return body }
        }
        return nil
    }

    // MARK: - The hoisted string table

    /// Modern players hoist their string constants into one array at the top of the
    /// file and index into it everywhere, so both extracted functions reference a global
    /// that is not inside either of them.
    ///
    /// Missing this does not throw — JavaScript happily reads an undefined global and
    /// returns undefined — so the symptom is a transform that appears to run and
    /// silently returns nothing. `Solver` treats a nil result as "fall back", which
    /// makes this fail safely, but it is the first thing to check when the top
    /// resolutions vanish.
    static func globalPrelude(in source: String) -> String {
        // Either quote style, and tolerating backslash escapes inside the literal —
        // the table is full of separators and quoted punctuation.
        let string = #"(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"#
        let patterns = [
            // var X = "a,b,c".split(",")
            #"var\s+([a-zA-Z0-9_$]+)\s*=\s*"# + string + #"\s*\.\s*split\(\s*"# + string + #"\s*\)"#,
            // var X = ['a','b','c', …]
            #"var\s+([a-zA-Z0-9_$]+)\s*=\s*\[\s*(?:"# + string + #"\s*,\s*){8,}"# + string + #"\s*\]"#,
        ]
        for pattern in patterns {
            if let range = source.range(of: pattern, options: .regularExpression) {
                // The pattern matches the whole `var X = …` declaration, so it is already
                // a valid statement — it only needs the semicolon the minifier omitted.
                return String(source[range]) + ";"
            }
        }
        return ""
    }

    // MARK: - The player URL

    /// The eight-hex-digit build id in `/s/player/<hash>/player_ias.vflset/…`.
    ///
    /// `/iframe_api` embeds the path inside a JavaScript string literal, where the
    /// slashes may or may not be backslash-escaped depending on how it was serialised —
    /// hence the optional backslash before each one.
    static func playerHash(in source: String) -> String? {
        capture(#"player\\?/([0-9a-fA-F]{8})\\?/"#, in: source)?[1]
    }

    // MARK: - Extraction primitives

    /// The source of a function, given its name, in any of the three forms a minifier
    /// emits it: `name=function(…){…}`, `function name(…){…}`, `name:function(…){…}`.
    ///
    /// Returned without the name, as a bare `function(…){…}` expression, so the caller
    /// can bind it to whatever it likes.
    static func function(named name: String, in source: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let headers = [
            #"(?:var\s+)?"# + escaped + #"\s*=\s*function\s*\([^)]*\)\s*\{"#,
            #"function\s+"# + escaped + #"\s*\([^)]*\)\s*\{"#,
            escaped + #"\s*:\s*function\s*\([^)]*\)\s*\{"#,
        ]
        for header in headers {
            guard let range = source.range(of: header, options: .regularExpression),
                  let end = matchingBrace(in: source, openedAt: source.index(before: range.upperBound))
            else { continue }
            // Rebuild as an anonymous expression: take the argument list out of the
            // matched header and pair it with the brace-matched body.
            let matched = String(source[range])
            guard let argsStart = matched.firstIndex(of: "("),
                  let argsEnd = matched.firstIndex(of: ")"), argsStart < argsEnd
            else { continue }
            let args = matched[matched.index(after: argsStart)..<argsEnd]
            let body = source[range.upperBound...end]
            return "function(\(args)){\(body.dropLast())}"
        }
        return nil
    }

    /// The `{…}` of `var name={…}`, for the signature helper object.
    static func objectLiteral(named name: String, in source: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let header = #"(?:var\s+)?"# + escaped + #"\s*=\s*\{"#
        guard let range = source.range(of: header, options: .regularExpression),
              let open = source.range(of: "{", range: range)?.lowerBound,
              let end = matchingBrace(in: source, openedAt: open)
        else { return nil }
        return String(source[open...end])
    }

    /// The top-level elements of `var name=[…]`, split on commas that are not nested.
    static func arrayElements(named name: String, in source: String) -> [String]? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let range = source.range(of: #"(?:var\s+)?"# + escaped + #"\s*=\s*\["#,
                                       options: .regularExpression),
              let open = source.range(of: "[", range: range)?.lowerBound,
              let end = matchingBrace(in: source, openedAt: open)
        else { return nil }

        var elements: [String] = []
        var current = ""
        var depth = 0
        var index = source.index(after: open)
        while index < end {
            let character = source[index]
            if let skipped = skipString(in: source, from: index) {
                current.append(contentsOf: source[index..<skipped])
                index = skipped
                continue
            }
            switch character {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case "," where depth == 0:
                elements.append(current)
                current = ""
                index = source.index(after: index)
                continue
            default: break
            }
            current.append(character)
            index = source.index(after: index)
        }
        elements.append(current)
        return elements
    }

    /// Index of the bracket closing the one at `openedAt`, skipping string literals.
    ///
    /// Minified JavaScript is one line with no comments, so string literals are the only
    /// place a stray brace can hide — but they are full of them, because the signature
    /// helper's operations are keyed by short quoted strings.
    private static func matchingBrace(in source: String, openedAt start: String.Index) -> String.Index? {
        let opener = source[start]
        let closer: Character
        switch opener {
        case "{": closer = "}"
        case "[": closer = "]"
        case "(": closer = ")"
        default: return nil
        }

        var depth = 0
        var index = start
        while index < source.endIndex {
            if index > start, let skipped = skipString(in: source, from: index) {
                index = skipped
                continue
            }
            let character = source[index]
            if character == opener { depth += 1 }
            else if character == closer {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// If `from` opens a string literal, the index just past its closing quote.
    private static func skipString(in source: String, from start: String.Index) -> String.Index? {
        let quote = source[start]
        guard quote == "\"" || quote == "'" || quote == "`" else { return nil }
        var index = source.index(after: start)
        while index < source.endIndex {
            let character = source[index]
            if character == "\\" {
                index = source.index(index, offsetBy: 2, limitedBy: source.endIndex) ?? source.endIndex
                continue
            }
            if character == quote { return source.index(after: index) }
            index = source.index(after: index)
        }
        return nil
    }

    // MARK: - Regex helpers

    /// First capture group `group` from the first pattern in `patterns` that matches.
    private static func firstGroup(_ patterns: [String], in source: String, group: Int) -> String? {
        for pattern in patterns {
            if let match = capture(pattern, in: source), let value = match[group] {
                return value
            }
        }
        return nil
    }

    /// All capture groups of the first match, indexed by group number.
    ///
    /// `NSRegularExpression` rather than a Swift regex literal: these patterns are
    /// assembled from strings at runtime, and several use backreferences, which the
    /// literal syntax does not take.
    private static func capture(_ pattern: String, in source: String) -> [Int: String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Log.engine.error("bad pattern: \(pattern, privacy: .public)")
            return nil
        }
        let full = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: full) else { return nil }

        var groups: [Int: String] = [:]
        for index in 0..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: source) else { continue }
            groups[index] = String(source[range])
        }
        return groups
    }
}
