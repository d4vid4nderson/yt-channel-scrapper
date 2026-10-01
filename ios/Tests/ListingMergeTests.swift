import Foundation
import Testing

@testable import YTChannelScraper

/// Splicing a refreshed head onto a kept channel list — what makes a refresh fetch one
/// page instead of the whole channel, and what must never leave a hole in the list.
struct ListingMergeTests {

    static func videos(_ ids: String...) -> [Video] {
        ids.map { Video(json: ["id": $0, "title": $0])! }
    }

    static func ids(_ result: ListingMerge.Result?) -> [String]? { result?.videos.map(\.id) }

    @Test("New videos go on top, the kept ones stay below")
    func newOnTop() {
        let kept = Self.videos("c", "d", "e", "f")
        let head = Self.videos("a", "b", "c", "d")
        let result = ListingMerge.splice(head, onto: kept)
        #expect(Self.ids(result) == ["a", "b", "c", "d", "e", "f"])
        #expect(result?.added == 2)
    }

    @Test("Nothing new is no change")
    func nothingNew() {
        let kept = Self.videos("a", "b", "c")
        let result = ListingMerge.splice(Self.videos("a", "b"), onto: kept)
        #expect(Self.ids(result) == ["a", "b", "c"])
        #expect(result?.added == 0)
    }

    @Test("A head that never reaches the kept list is not spliced, so no hole opens")
    func noOverlap() {
        let kept = Self.videos("x", "y")
        #expect(ListingMerge.splice(Self.videos("a", "b"), onto: kept) == nil)
    }

    @Test("A kept video the head skips over has been taken down")
    func removedWithinHead() {
        let kept = Self.videos("b", "c", "d", "e")
        let head = Self.videos("a", "b", "d")   // c is gone
        #expect(Self.ids(ListingMerge.splice(head, onto: kept)) == ["a", "b", "d", "e"])
    }

    @Test("The head's copy of a video wins over the kept one")
    func freshCopyWins() {
        let kept = [Video(json: ["id": "a", "title": "Old title"])!]
        let head = [Video(json: ["id": "a", "title": "New title"])!]
        #expect(ListingMerge.splice(head, onto: kept)?.videos.first?.title == "New title")
    }

    @Test("Empty sides")
    func empties() {
        let some = Self.videos("a", "b")
        #expect(Self.ids(ListingMerge.splice([], onto: some)) == ["a", "b"])
        #expect(Self.ids(ListingMerge.splice(some, onto: [])) == ["a", "b"])
    }
}
