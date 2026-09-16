import Foundation
import Testing

@testable import YTChannelScraper

/// The family roster's own rules, which had none until a real family broke them.
///
/// Everything here is about one question the design cannot avoid: every device mints its
/// own id for whoever is setting it up, so one human ends up as two people, and anything
/// sent to one is invisible to the other. It presents as "drag and drop is broken", which
/// is why it survived three sittings.
struct FamilyIdentityTests {

    static let mac = UUID()
    static let phone = UUID()
    static let other = UUID()

    static func member(_ id: UUID, _ name: String, isMinor: Bool = false,
                       sameAs: UUID? = nil, removed: Bool = false) -> FamilyMember {
        var m = FamilyMember(id: id, name: name, isMinor: isMinor)
        m.sameAs = sameAs
        if removed { m.isRemoved = true }
        return m
    }

    // MARK: - Resolving

    @Test func anAliasResolvesToItsPerson() {
        let table = ShelfStore.aliasTable([
            Self.member(Self.mac, "David Anderson"),
            Self.member(Self.phone, "David", sameAs: Self.mac),
        ])
        #expect(table[Self.phone] == Self.mac)
        #expect(table[Self.mac] == nil, "the surviving identity is nobody's alias")
    }

    @Test func chainsFlattenToOneStep() {
        let third = UUID()
        let table = ShelfStore.aliasTable([
            Self.member(Self.mac, "David Anderson"),
            Self.member(Self.phone, "David", sameAs: Self.mac),
            Self.member(third, "D", sameAs: Self.phone),
        ])
        // Both land on the Mac, so a send has one place to go rather than a walk to do.
        #expect(table[Self.phone] == Self.mac)
        #expect(table[third] == Self.mac)
    }

    /// Two admins can each decide the other's id is the duplicate, and they write into
    /// separate files so nothing stops them. The table has to terminate anyway.
    @Test func aCycleDoesNotHang() {
        let table = ShelfStore.aliasTable([
            Self.member(Self.mac, "David Anderson", sameAs: Self.phone),
            Self.member(Self.phone, "David", sameAs: Self.mac),
        ])
        #expect(table.count <= 2)
    }

    @Test func pointingAtYourselfIsNotAnAlias() {
        let table = ShelfStore.aliasTable([Self.member(Self.mac, "David", sameAs: Self.mac)])
        #expect(table.isEmpty)
    }

    /// A tombstone already hides somebody. Honouring their `sameAs` as well would let a
    /// removed row keep steering where live sends go.
    @Test func aRemovedMemberContributesNoAlias() {
        let table = ShelfStore.aliasTable([
            Self.member(Self.phone, "David", sameAs: Self.mac, removed: true),
        ])
        #expect(table.isEmpty)
    }

    @Test func unrelatedPeopleAreLeftAlone() {
        let table = ShelfStore.aliasTable([
            Self.member(Self.mac, "David Anderson"),
            Self.member(Self.other, "Jillian Anderson"),
        ])
        #expect(table.isEmpty)
    }

    // MARK: - Decoding

    /// Every file already in a family's folder was written before this field existed, so
    /// a missing `sameAs` has to read as "not an alias" rather than as a broken file — a
    /// throw here would empty the roster on both devices at once.
    ///
    /// The shape is copied from a real people file. It matters that it is: a synthesised
    /// `Decodable` does not fall back to a property's default value for a missing key, so
    /// only `Optional` fields are actually safe to add later. `isClaimed` is not optional
    /// and is therefore load-bearing in every file ever written — worth knowing before
    /// adding the next field.
    @Test func filesWrittenBeforeAliasesStillDecode() throws {
        let json = """
        {"id":"\(Self.mac.uuidString)","name":"David Anderson",\
        "isMinor":false,"isClaimed":false}
        """
        let member = try JSONDecoder().decode(FamilyMember.self, from: Data(json.utf8))
        #expect(member.sameAs == nil)
        #expect(member.removed == false)
    }

    /// The rule the comment above depends on, pinned so it is a fact rather than a memory.
    @Test func aNonOptionalFieldWithADefaultIsStillRequired() {
        let json = """
        {"id":"\(Self.mac.uuidString)","name":"David Anderson","isMinor":false}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FamilyMember.self, from: Data(json.utf8))
        }
    }

    @Test func anAliasSurvivesTheRoundTrip() throws {
        let original = Self.member(Self.phone, "David", sameAs: Self.mac)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(FamilyMember.self, from: data)
        #expect(back.sameAs == Self.mac)
    }
}
