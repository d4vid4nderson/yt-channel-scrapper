import Foundation
import Testing

@testable import YTChannelScraper

/// The shelf's merge rules, which are the part of the guardian feature that has to be
/// right. Everything else — folders, iCloud, the reconciler — is plumbing around these.
struct ShelfMergeTests {

    // A fixed clock, so "newer" is something the test states rather than races.
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static func t(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    static func video(
        _ id: String,
        _ state: ShelfEntry.State,
        by guardian: String,
        at offset: TimeInterval
    ) -> ShelfEntry {
        ShelfEntry(kind: .video, id: id, state: state, guardian: guardian, at: t(offset))
    }

    // MARK: - The basic rule

    @Test("The newest decision about an item wins")
    func newestWins() {
        let entries = [
            Self.video("abc", .approved, by: "David", at: 0),
            Self.video("abc", .removed, by: "Sarah", at: 10),
        ]
        #expect(ShelfMerge.approved(entries).isEmpty)
        #expect(ShelfMerge.resolve(entries)[.init(kind: .video, id: "abc")]?.guardian == "Sarah")
    }

    @Test("A removal can be undone by a later approval")
    func reapprovalWins() {
        let entries = [
            Self.video("abc", .approved, by: "David", at: 0),
            Self.video("abc", .removed, by: "Sarah", at: 10),
            Self.video("abc", .approved, by: "Sarah", at: 20),
        ]
        #expect(ShelfMerge.approved(entries) == [.init(kind: .video, id: "abc")])
    }

    // MARK: - Fail closed

    @Test("A removal beats an approval recorded at the same instant")
    func removalWinsTies() {
        let entries = [
            Self.video("abc", .approved, by: "David", at: 5),
            Self.video("abc", .removed, by: "Sarah", at: 5),
        ]
        #expect(ShelfMerge.approved(entries).isEmpty)
    }

    @Test("A tie is broken the same way whichever order the files are read in")
    func tieIsOrderIndependent() {
        let approve = Self.video("abc", .approved, by: "David", at: 5)
        let remove = Self.video("abc", .removed, by: "Sarah", at: 5)
        #expect(ShelfMerge.approved([approve, remove]).isEmpty)
        #expect(ShelfMerge.approved([remove, approve]).isEmpty)
    }

    @Test("Simultaneous identical decisions agree on whose name to show")
    func attributionIsDeterministic() {
        let david = Self.video("abc", .approved, by: "David", at: 5)
        let sarah = Self.video("abc", .approved, by: "Sarah", at: 5)
        let key = ShelfEntry.Key(kind: .video, id: "abc")
        let one = ShelfMerge.resolve([david, sarah])[key]?.guardian
        let other = ShelfMerge.resolve([sarah, david])[key]?.guardian
        #expect(one == other)
    }

    // MARK: - The bug this design exists to prevent

    @Test("An older approval from another guardian cannot resurrect a removed item")
    func tombstoneOutranksOlderApproval() {
        // David's file still holds his approval; he never changed his mind. Sarah's
        // removal is newer and lives in a different file. Reading both must not let
        // David's stale approval win just because it is there.
        let davidsFile = [Self.video("abc", .approved, by: "David", at: 0)]
        let sarahsFile = [Self.video("abc", .removed, by: "Sarah", at: 10)]
        #expect(ShelfMerge.approved(davidsFile + sarahsFile).isEmpty)
    }

    @Test("Collapsing a guardian's own file never drops a tombstone")
    func collapseKeepsTombstones() {
        // The pruning trap documented on `collapsed`: if Sarah's tombstone were dropped
        // as stale, David's approval would win by default and the video would return.
        let sarahsFile = [
            Self.video("abc", .approved, by: "Sarah", at: 0),
            Self.video("abc", .removed, by: "Sarah", at: 10),
        ]
        let collapsed = ShelfMerge.collapsed(sarahsFile)
        #expect(collapsed.count == 1)
        #expect(collapsed.first?.state == .removed)

        let davidsFile = [Self.video("abc", .approved, by: "David", at: 0)]
        #expect(ShelfMerge.approved(collapsed + davidsFile).isEmpty)
    }

    // MARK: - Two guardians, editing at once

    @Test("Concurrent edits by two guardians both survive")
    func concurrentEditsBothSurvive() {
        // The case whole-archive last-writer-wins gets wrong: each guardian adds
        // something different between syncs. Neither addition may be lost.
        let davidsFile = [
            Self.video("aaa", .approved, by: "David", at: 1),
            Self.video("bbb", .approved, by: "David", at: 2),
        ]
        let sarahsFile = [
            Self.video("ccc", .approved, by: "Sarah", at: 3),
        ]
        #expect(ShelfMerge.approved(davidsFile + sarahsFile).count == 3)
    }

    @Test("One guardian's veto applies to the other's approval")
    func vetoCrossesGuardians() {
        let davidsFile = [
            Self.video("aaa", .approved, by: "David", at: 1),
            Self.video("bbb", .approved, by: "David", at: 2),
        ]
        let sarahsFile = [Self.video("bbb", .removed, by: "Sarah", at: 5)]
        #expect(ShelfMerge.approved(davidsFile + sarahsFile) == [.init(kind: .video, id: "aaa")])
    }

    // MARK: - A channel veto takes its videos with it

    static func videoFrom(
        _ channel: String,
        _ id: String,
        _ state: ShelfEntry.State,
        by guardian: String,
        at offset: TimeInterval
    ) -> ShelfEntry {
        ShelfEntry(kind: .video, id: id, state: state, guardian: guardian,
                   at: t(offset), channelID: channel)
    }

    static func channel(
        _ id: String,
        _ state: ShelfEntry.State,
        by guardian: String,
        at offset: TimeInterval
    ) -> ShelfEntry {
        ShelfEntry(kind: .channel, id: id, state: state, guardian: guardian, at: t(offset))
    }

    @Test("Blocking a channel withdraws videos already approved from it")
    func channelVetoCascades() {
        let entries = [
            Self.videoFrom("UCkids", "aaa", .approved, by: "David", at: 1),
            Self.videoFrom("UCkids", "bbb", .approved, by: "David", at: 2),
            Self.videoFrom("UCother", "ccc", .approved, by: "David", at: 3),
            Self.channel("UCkids", .removed, by: "Sarah", at: 10),
        ]
        let playable = Set(ShelfMerge.playable(entries).map(\.id))
        #expect(playable == ["ccc"])
    }

    @Test("Un-blocking a channel restores its still-approved videos")
    func channelVetoIsReversible() {
        let entries = [
            Self.videoFrom("UCkids", "aaa", .approved, by: "David", at: 1),
            Self.channel("UCkids", .removed, by: "Sarah", at: 10),
            Self.channel("UCkids", .approved, by: "Sarah", at: 20),
        ]
        #expect(Set(ShelfMerge.playable(entries).map(\.id)) == ["aaa"])
    }

    @Test("A video removed on its own stays removed even on an allowed channel")
    func videoVetoSurvivesChannelApproval() {
        let entries = [
            Self.videoFrom("UCkids", "aaa", .approved, by: "David", at: 1),
            Self.videoFrom("UCkids", "aaa", .removed, by: "Sarah", at: 2),
            Self.channel("UCkids", .approved, by: "David", at: 30),
        ]
        #expect(ShelfMerge.playable(entries).isEmpty)
    }

    @Test("Approving a channel does not by itself approve any video")
    func channelApprovalIsNotBlanketConsent() {
        // The property that keeps a channel's new uploads from reaching a child unseen:
        // nothing is playable without a decision naming the video itself.
        let entries = [Self.channel("UCkids", .approved, by: "David", at: 1)]
        #expect(ShelfMerge.playable(entries).isEmpty)
    }

    @Test("A video with no channel recorded is unaffected by any channel veto")
    func videosWithoutChannelSurvive() {
        // Entries written before channelID existed. They cannot be cascaded onto, and
        // silently dropping them would empty a shelf on upgrade.
        let entries = [
            Self.video("aaa", .approved, by: "David", at: 1),
            Self.channel("UCkids", .removed, by: "Sarah", at: 10),
        ]
        #expect(Set(ShelfMerge.playable(entries).map(\.id)) == ["aaa"])
    }

    // MARK: - Shape

    @Test("Channels and videos with the same id are different items")
    func kindsDoNotCollide() {
        let entries = [
            ShelfEntry(kind: .video, id: "x", state: .approved, guardian: "David", at: Self.t(0)),
            ShelfEntry(kind: .channel, id: "x", state: .removed, guardian: "David", at: Self.t(1)),
        ]
        #expect(ShelfMerge.approved(entries) == [.init(kind: .video, id: "x")])
    }

    @Test("Merging is order-independent across many shuffles")
    func mergeIsOrderIndependent() {
        var entries: [ShelfEntry] = []
        for index in 0..<25 {
            entries.append(Self.video("v\(index % 7)",
                                      index.isMultiple(of: 3) ? .removed : .approved,
                                      by: index.isMultiple(of: 2) ? "David" : "Sarah",
                                      at: TimeInterval(index)))
        }
        let expected = ShelfMerge.approved(entries)
        for _ in 0..<50 {
            #expect(ShelfMerge.approved(entries.shuffled()) == expected)
        }
    }

    @Test("Collapsing is idempotent and loses nothing")
    func collapseIsIdempotent() {
        var entries: [ShelfEntry] = []
        for index in 0..<20 {
            entries.append(Self.video("v\(index % 5)",
                                      index.isMultiple(of: 4) ? .removed : .approved,
                                      by: "David",
                                      at: TimeInterval(index)))
        }
        let once = ShelfMerge.collapsed(entries)
        let twice = ShelfMerge.collapsed(once)
        #expect(once == twice)
        #expect(ShelfMerge.approved(once) == ShelfMerge.approved(entries))
    }

    @Test("An empty shelf approves nothing")
    func emptyIsEmpty() {
        #expect(ShelfMerge.approved([ShelfEntry]()).isEmpty)
        #expect(ShelfMerge.collapsed([ShelfEntry]()).isEmpty)
    }

    // MARK: - Round trip

    @Test("A shelf file survives JSON, tombstones and all")
    func fileRoundTrips() throws {
        let file = ShelfFile(
            guardianID: UUID(),
            guardianName: "David",
            minorID: UUID(),
            minorName: "Ellie",
            writtenAt: Self.t(0),
            entries: [
                Self.video("aaa", .approved, by: "David", at: 1),
                Self.video("bbb", .removed, by: "David", at: 2),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(ShelfFile.self, from: try encoder.encode(file))
        #expect(decoded.entries == file.entries)
        #expect(decoded.guardianID == file.guardianID)
        #expect(decoded.minorID == file.minorID)
        #expect(ShelfMerge.approved(decoded.entries) == [.init(kind: .video, id: "aaa")])
    }

    @Test("A date that has been through JSON still compares equal")
    func datesSurviveEncodingForTieBreaking() throws {
        // Why rule 2 is not theoretical: ISO-8601 drops sub-second precision, so two
        // decisions made milliseconds apart can come back as the same instant.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let approve = Self.video("abc", .approved, by: "David", at: 5.4)
        let remove = Self.video("abc", .removed, by: "Sarah", at: 5.9)
        let round = try [approve, remove].map {
            try decoder.decode(ShelfEntry.self, from: try encoder.encode($0))
        }
        #expect(round[0].at == round[1].at)
        #expect(ShelfMerge.approved(round).isEmpty)
    }
}
