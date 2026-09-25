import Foundation
import Testing

@testable import YTChannelScraper

/// Which device records count as clutter, and that removing one sticks without being
/// able to hide a device that is genuinely still in use.
struct DeviceTidyTests {

    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static func t(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    static let wyatt = UUID()
    static let david = UUID()

    static func device(
        _ name: String,
        for person: UUID?,
        kind: DeviceRecord.Kind = .phone,
        seen offset: TimeInterval,
        id: UUID = UUID()
    ) -> DeviceRecord {
        DeviceRecord(deviceID: id, name: name, kind: kind, personID: person,
                     personName: nil, isMinor: person == wyatt, lastSeen: t(offset),
                     approved: 0, downloaded: 0)
    }

    // MARK: - Duplicates

    @Test("A reinstall's leftover record is a duplicate; the newest one is not")
    func reinstallLeavesADuplicate() {
        let old = Self.device("Wyatt's phone", for: Self.wyatt, seen: 0)
        let new = Self.device("Wyatt's phone", for: Self.wyatt, seen: 1_260)
        let found = DeviceTidy.duplicates(in: [new, old])
        #expect(found.map(\.deviceID) == [old.deviceID])
    }

    @Test("Two differently named phones for one child are both kept")
    func twoRealPhonesAreNotDuplicates() {
        let phone = Self.device("Wyatt's phone", for: Self.wyatt, seen: 0)
        let spare = Self.device("Wyatt's old phone", for: Self.wyatt, seen: 10)
        #expect(DeviceTidy.duplicates(in: [phone, spare]).isEmpty)
    }

    @Test("A phone and a tablet with the same owner are not duplicates")
    func differentKindsAreNotDuplicates() {
        let phone = Self.device("Wyatt's device", for: Self.wyatt, kind: .phone, seen: 0)
        let tablet = Self.device("Wyatt's device", for: Self.wyatt, kind: .tablet, seen: 10)
        #expect(DeviceTidy.duplicates(in: [phone, tablet]).isEmpty)
    }

    @Test("A record under an alias of the same person still counts as theirs")
    func aliasesAreFollowed() {
        let oldIdentity = UUID()
        let old = Self.device("Wyatt's phone", for: oldIdentity, seen: 0)
        let new = Self.device("Wyatt's phone", for: Self.wyatt, seen: 100)
        let found = DeviceTidy.duplicates(in: [old, new], aliases: [oldIdentity: Self.wyatt])
        #expect(found.map(\.deviceID) == [old.deviceID])
    }

    @Test("A device reporting for nobody is never called a duplicate")
    func unownedIsNotADuplicate() {
        let a = Self.device("Phone", for: nil, seen: 0)
        let b = Self.device("Phone", for: nil, seen: 10)
        #expect(DeviceTidy.duplicates(in: [a, b]).isEmpty)
    }

    // MARK: - Stale

    @Test("Silent for over a month is stale; a school break is not")
    func staleAfterAMonth() {
        let now = Self.t(40 * 86_400)
        let drawer = Self.device("Spare", for: Self.david, seen: 0)
        let breakTime = Self.device("Phone", for: Self.wyatt, seen: 20 * 86_400)
        #expect(DeviceTidy.stale(in: [drawer, breakTime], now: now).map(\.deviceID)
                == [drawer.deviceID])
    }

    @Test("Clean up lists a record that is both stale and a duplicate once")
    func clutterIsDeduplicated() {
        let now = Self.t(60 * 86_400)
        let old = Self.device("Wyatt's phone", for: Self.wyatt, seen: 0)
        let new = Self.device("Wyatt's phone", for: Self.wyatt, seen: 59 * 86_400)
        #expect(DeviceTidy.clutter(in: [old, new], now: now).map(\.deviceID) == [old.deviceID])
    }

    // MARK: - Forgetting

    @Test("A forgotten record stays hidden, even when a phone relays the same copy back")
    func forgottenStaysHidden() {
        let old = Self.device("Wyatt's phone", for: Self.wyatt, seen: 0)
        let tombstone = ForgottenDevice(deviceID: old.deviceID, lastSeen: old.lastSeen)
        #expect(DeviceTidy.visible([old], forgotten: [tombstone]).isEmpty)
    }

    @Test("A forgotten device that reports again comes back")
    func liveDeviceReturns() {
        let id = UUID()
        let removed = Self.device("Wyatt's phone", for: Self.wyatt, seen: 0, id: id)
        let tombstone = ForgottenDevice(deviceID: id, lastSeen: removed.lastSeen)
        let reportedAgain = Self.device("Wyatt's phone", for: Self.wyatt, seen: 60, id: id)
        #expect(DeviceTidy.visible([reportedAgain], forgotten: [tombstone]).count == 1)
    }

    @Test("A forgotten device survives the trip through JSON")
    func tombstoneSurvivesEncoding() throws {
        let file = PeopleFile(guardianID: UUID(), writtenAt: Self.t0, people: [],
                              forgottenDevices: [.init(deviceID: UUID(), lastSeen: Self.t(5))])
        let (encoder, decoder) = LibraryArchive.coders()
        let back = try decoder.decode(PeopleFile.self, from: encoder.encode(file))
        #expect(back.forgottenDevices == file.forgottenDevices)
    }

    @Test("A report from before file lists still decodes, and says nothing about files")
    func oldReportDecodes() throws {
        let json = """
        {"approved":26,"deviceID":"AFCE0207-C3CD-4D6C-B9E2-D642C464AD5D","downloaded":26,
         "isMinor":true,"kind":"phone","lastSeen":"2026-09-24T15:44:03Z",
         "name":"Wyatt's phone","personID":"F7461A88-6FBE-48EF-AAF9-C0E82BDCA6BE",
         "personName":"Wyatt"}
        """
        let (_, decoder) = LibraryArchive.coders()
        let record = try decoder.decode(DeviceRecord.self, from: Data(json.utf8))
        #expect(record.files == nil)
        #expect(record.usedBytes == nil)
    }
}
