import AVFoundation
import CoreAudio
import Foundation

/// One place this video's sound can go.
struct AudioOutput: Identifiable, Hashable, Sendable {
    /// The CoreAudio UID, which is exactly what `AVPlayer.audioOutputDeviceUniqueID`
    /// takes — so the id here is also the thing that does the routing.
    let id: String
    let name: String
    let icon: String
    let isSystemDefault: Bool
}

/// The output devices this video's audio can be sent to, and which one it is going to.
///
/// This exists because the system route picker, on macOS, presents the *system audio*
/// menu — a multi-select checklist, since macOS can fan audio out to several outputs at
/// once. That is not the single tap Control Center gives you, and none of the knobs that
/// would change it (`prioritizesVideoDevices`, `routingMethod`, `routePickerButtonStyle`)
/// are available on macOS; the SDK marks every one `API_UNAVAILABLE(macos)`.
///
/// So the list is built here instead, from CoreAudio, and a tap routes this one player
/// with `audioOutputDeviceUniqueID`. What it cannot do is *discover* an Apple TV or a Roku
/// that macOS has not already connected — that is private AirPlay machinery. Which is why
/// the system AirPlay button still sits next to it: this list is for choosing among the
/// outputs you have, that button is for finding new ones.
@MainActor
@Observable
final class AudioOutputs {
    private(set) var devices: [AudioOutput] = []
    /// `nil` means "whatever the system is using" — the state an untouched player is in,
    /// and the one to come back to.
    private(set) var selected: String?

    /// Read fresh every time the list is opened rather than watched continuously: this is
    /// a menu you open for a second, and a property listener on the device list would be a
    /// standing subscription to serve it.
    func refresh() {
        devices = Self.outputs()
    }

    func sync(from player: AVPlayer) {
        selected = player.audioOutputDeviceUniqueID
    }

    /// Passing `nil` hands the player back to the system's own output.
    func select(_ uid: String?, on player: AVPlayer) {
        player.audioOutputDeviceUniqueID = uid
        selected = uid
    }

    // MARK: - CoreAudio

    private static func outputs() -> [AudioOutput] {
        let systemDefault = defaultOutputUID()
        return deviceIDs().compactMap { id in
            guard hasOutputChannels(id),
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName)
            else { return nil }
            return AudioOutput(
                id: uid,
                name: name,
                icon: icon(forTransport: transportType(id)),
                isSystemDefault: uid == systemDefault
            )
        }
    }

    private static func deviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// A device with no output channels is an input — the built-in microphone sits in the
    /// same list as the built-in speakers.
    private static func hasOutputChannels(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0
        else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }

    /// CoreAudio hands back a +1 string, so it is taken retained rather than copied out of
    /// a plain `CFString` variable, which would leak one per device per refresh.
    private static func string(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        let text = value.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }

    private static func transportType(_ id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return value
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr else { return nil }
        return string(device, kAudioDevicePropertyDeviceUID)
    }

    /// How it is plugged in is the best guess at what it is, and it is the guess Control
    /// Center makes too — a laptop for the built-in speakers, earbuds for Bluetooth.
    private static func icon(forTransport transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:              "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:          "airpods"
        case kAudioDeviceTransportTypeAirPlay:              "airplayaudio"
        case kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort:          "tv"
        case kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypeThunderbolt:          "hifispeaker.fill"
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate:            "waveform"
        default:                                            "speaker.wave.2.fill"
        }
    }
}
