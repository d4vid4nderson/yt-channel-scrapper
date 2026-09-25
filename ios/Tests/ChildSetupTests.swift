import Foundation
import Testing

@testable import YTChannelScraper

/// What the Mac hands a child's phone. The phone acts on it without asking anyone, so
/// what it will accept is worth pinning down.
struct ChildSetupTests {

    static let wyatt = Profiles.Minor(id: UUID(), name: "Wyatt")

    @Test func survivesTheTripThroughJSON() throws {
        let setup = ChildSetup(minor: Self.wyatt, pin: "1234", folderName: "Anderson Family")
        let back = try #require(ChildSetup.decode(try setup.encoded()))
        #expect(back.minor == Self.wyatt)
        #expect(back.folderName == "Anderson Family")
        #expect(back.pinRecord == setup.pinRecord)
    }

    /// The digits never travel — only the salted hash, in the Keychain's own shape.
    @Test func carriesAHashNotThePIN() throws {
        let setup = ChildSetup(minor: Self.wyatt, pin: "1234", folderName: nil)
        #expect(setup.pinRecord.count == Profiles.pinRecordLength)
        let text = String(decoding: try setup.encoded(), as: UTF8.self)
        #expect(!text.contains("1234"))
    }

    /// Salted, so two setups with the same PIN do not share a record.
    @Test func eachRecordIsSaltedAfresh() {
        let a = ChildSetup(minor: Self.wyatt, pin: "1234", folderName: nil)
        let b = ChildSetup(minor: Self.wyatt, pin: "1234", folderName: nil)
        #expect(a.pinRecord != b.pinRecord)
    }

    @Test func refusesARecordOfTheWrongLength() throws {
        let setup = ChildSetup(minor: Self.wyatt, pin: "1234", folderName: nil)
        var json = try #require(try JSONSerialization.jsonObject(with: setup.encoded()) as? [String: Any])
        json["pinRecord"] = Data([1, 2, 3]).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: json)
        #expect(ChildSetup.decode(tampered) == nil)
    }

    @Test func refusesAChildWithNoName() throws {
        let setup = ChildSetup(minor: Profiles.Minor(id: UUID(), name: "  "), pin: "1234", folderName: nil)
        #expect(ChildSetup.decode(try setup.encoded()) == nil)
    }

    @Test func readsTheLaunchArgument() throws {
        let setup = ChildSetup(minor: Self.wyatt, pin: "4321", folderName: nil)
        let arguments = ["app", ChildSetup.argument, try setup.encoded().base64EncodedString()]
        #expect(ChildSetup.fromLaunchArguments(arguments)?.minor == Self.wyatt)
    }

    @Test func ignoresALaunchWithoutOne() {
        #expect(ChildSetup.fromLaunchArguments(["app"]) == nil)
        #expect(ChildSetup.fromLaunchArguments(["app", ChildSetup.argument]) == nil)
        #expect(ChildSetup.fromLaunchArguments(["app", ChildSetup.argument, "not base64!"]) == nil)
    }
}
