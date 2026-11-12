//
//  F75Protocol.swift
//  F75Driver
//
//  Wire format of the AULA F75's configuration protocol ("kb_by_v2" in the
//  vendor's online driver). Pure byte manipulation: no I/O happens here.
//
//  This milestone is read-only, so only read requests can be expressed.
//  See ACKNOWLEDGEMENTS.md for where the protocol knowledge comes from.
//

import Foundation

nonisolated enum F75Protocol {

    // MARK: Cable (USB feature reports)

    static let wiredVendorID = 0x258A
    static let wiredProductID = 0x010C
    /// Feature report carrying every wired command and reply.
    static let wiredReportID: UInt8 = 0x06
    /// Report length including the report ID byte.
    static let wiredReportLength = 520
    /// Reply layout: report ID, 7 header bytes, then the payload.
    static let wiredPayloadOffset = 8

    /// Read requests over the cable. Every read command has the top bit set;
    /// the matching write is the same value without it. The only write this
    /// app sends is the settings page, built by `wiredSettingsWrite`.
    enum WiredRead: CaseIterable {
        case identity, settings, battery

        var command: UInt8 { header[0] }

        var header: [UInt8] {
            switch self {
            case .identity: [0x82, 0x01, 0x00, 0x01, 0x00, 0x06, 0x00]
            case .settings: [0x84, 0x00, 0x00, 0x01, 0x00, 0x80]
            case .battery: [0x87, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00]
            }
        }

        var payloadLength: Int {
            switch self {
            case .identity: 6
            case .settings: SettingsPage.length
            case .battery: 2
            }
        }
    }

    /// The full feature report for a read request, report ID first.
    static func wiredRequest(_ read: WiredRead) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: wiredReportLength)
        report[0] = wiredReportID
        report.replaceSubrange(1...read.header.count, with: read.header)
        return report
    }

    /// Extracts the payload from a reply (report ID first), or nil when the
    /// reply is not an answer to `read`. The firmware returns stale or empty
    /// reports while it is busy, so callers retry on nil.
    static func wiredPayload(of reply: [UInt8], for read: WiredRead) -> [UInt8]? {
        guard reply.count >= wiredPayloadOffset + read.payloadLength,
              reply[0] == wiredReportID,
              reply[1] == read.command else { return nil }
        return Array(reply[wiredPayloadOffset..<(wiredPayloadOffset + read.payloadLength)])
    }

    // MARK: Writing the settings page (cable only)

    /// The only write this app sends: the stored settings page, command 0x04.
    static let wiredSettingsWriteHeader: [UInt8] = [0x04, 0x00, 0x00, 0x01, 0x00, 0x80, 0x00]

    /// The feature report that stores `updated`, or nil unless it is safe:
    /// both pages must be complete, and `updated` may differ from `current`
    /// (the page just read from the keyboard) only in the lighting bytes.
    static func wiredSettingsWrite(_ updated: SettingsPage, replacing current: SettingsPage) -> [UInt8]? {
        guard current.hasSignature, updated.hasSignature else { return nil }
        for offset in 0..<SettingsPage.length where updated.bytes[offset] != current.bytes[offset] {
            guard SettingsPage.lightingOffsets.contains(offset) else { return nil }
        }
        var report = [UInt8](repeating: 0, count: wiredReportLength)
        report[0] = wiredReportID
        report.replaceSubrange(1...wiredSettingsWriteHeader.count, with: wiredSettingsWriteHeader)
        report.replaceSubrange(wiredPayloadOffset..<(wiredPayloadOffset + SettingsPage.length), with: updated.bytes)
        return report
    }

    // MARK: 2.4 GHz dongle (output / input reports)

    static let dongleVendorID = 0x3554
    static let dongleProductID = 0xFA09
    static let dongleReportID: UInt8 = 0x13
    /// Output report length including the report ID byte.
    static let dongleReportLength = 20
    /// Packet layout after the report ID: command, packet count, packet
    /// index, length byte, data, checksum.
    static let donglePacketDataOffset = 4

    /// Read requests over the dongle. Replies arrive as input reports that
    /// echo the command, split over `replyPackets` packets.
    enum DongleRead: CaseIterable {
        case identity, settings, battery

        var command: UInt8 { header[0] }

        var header: [UInt8] {
            switch self {
            case .identity: [0x05, 0x01, 0x00, 0x00]
            case .settings: [0x44, 0x01, 0x00, 0x10]
            case .battery: [0x4A, 0x00, 0x00, 0x00]
            }
        }

        var replyPackets: Int {
            switch self {
            case .identity, .battery: 1
            case .settings: 10
            }
        }

        var payloadLength: Int {
            switch self {
            case .identity: 6
            case .settings: SettingsPage.length
            case .battery: 2
            }
        }
    }

    /// Sum of the report ID and every byte before the checksum, modulo 256.
    static func dongleChecksum(_ packet: some Collection<UInt8>) -> UInt8 {
        UInt8(truncatingIfNeeded: packet.reduce(Int(dongleReportID)) { $0 + Int($1) })
    }

    /// The full output report for a read request, report ID first.
    static func dongleRequest(_ read: DongleRead) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: dongleReportLength - 1)
        packet.replaceSubrange(0..<read.header.count, with: read.header)
        packet[packet.count - 1] = dongleChecksum(packet.dropLast())
        return [dongleReportID] + packet
    }

    /// Unsolicited dongle packet announcing that the keyboard joined or left
    /// the radio link. Returns nil for any other packet.
    static func dongleOnlineEvent(_ packet: [UInt8]) -> Bool? {
        guard packet.count > 5, packet[0] == 0x0A, packet[4] == 0x02 else { return nil }
        return packet[5] == 1
    }

    /// Collects the packets of one multi-packet dongle reply. Packets are
    /// given without the report ID.
    struct DongleReassembler {
        let read: DongleRead
        private var parts: [Int: [UInt8]] = [:]

        init(_ read: DongleRead) { self.read = read }

        /// Returns true when the packet belonged to this reply.
        @discardableResult
        mutating func add(_ packet: [UInt8]) -> Bool {
            guard packet.count > F75Protocol.donglePacketDataOffset + 1,
                  packet[0] == read.command,
                  Int(packet[1]) == read.replyPackets,
                  Int(packet[2]) < read.replyPackets else { return false }
            parts[Int(packet[2])] = Array(packet[F75Protocol.donglePacketDataOffset..<(packet.count - 1)])
            return true
        }

        /// The reassembled payload once every packet has arrived.
        var payload: [UInt8]? {
            guard parts.count == read.replyPackets else { return nil }
            let data = (0..<read.replyPackets).flatMap { parts[$0] ?? [] }
            guard data.count >= read.payloadLength else { return nil }
            return Array(data.prefix(read.payloadLength))
        }
    }
}

// MARK: - Decoded replies

/// The 6-byte model identifier the keyboard reports (the vendor calls it a UUID).
nonisolated struct DeviceIdentity: Equatable {
    let bytes: [UInt8]

    init?(payload: [UInt8]) {
        guard payload.count >= 6 else { return nil }
        bytes = Array(payload.prefix(6))
    }

    var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

    /// Model names from the vendor's device table, keyed by identifier.
    private static let models: [[UInt8]: String] = [
        [0x03, 0x00, 0x00, 0x00, 0x00, 0xCD]: "AULA F75",
        [0x03, 0x00, 0x00, 0x00, 0x03, 0x5C]: "AULA F75",
        [0x03, 0x00, 0x00, 0x00, 0x00, 0xA4]: "AULA F99",
        [0x03, 0x00, 0x00, 0x00, 0x01, 0x0B]: "AULA F87",
    ]

    var modelName: String? { Self.models[bytes] }
}

nonisolated struct BatteryStatus: Equatable {
    /// Percentage as reported by the keyboard.
    let level: Int
    /// Second byte of the reply. The vendor stores it as "battery status"
    /// without interpreting it; the meanings below come from readings taken
    /// on an F75: 0x10 plugged in at 99%, 0x11 plugged in at 100%, 0x01 unplugged.
    let statusCode: Int

    enum Power: Equatable {
        case onBattery, charging, pluggedInFull
    }

    /// Bit 4 is set while the cable supplies power. Bit 0 was clear only
    /// while the battery was still filling, so it is read as "not charging".
    var power: Power {
        guard statusCode & 0x10 != 0 else { return .onBattery }
        return statusCode & 0x01 == 0 ? .charging : .pluggedInFull
    }

    init?(payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        level = Int(payload[0])
        statusCode = Int(payload[1])
    }
}

/// The keyboard's 128-byte stored settings page.
nonisolated struct SettingsPage: Equatable {
    static let length = 128
    static let effectTableOffset = 58
    static let effectCount = 34

    let bytes: [UInt8]

    init?(payload: [UInt8]) {
        guard payload.count >= Self.length else { return nil }
        bytes = Array(payload.prefix(Self.length))
    }

    /// The page ends in `5A A5` when it is complete.
    var hasSignature: Bool { bytes[Self.length - 2] == 0x5A && bytes[Self.length - 1] == 0xA5 }

    var macMode: Bool { bytes[0] == 1 }
    var pollingLevel: Int { Int(bytes[1]) }
    var lowLatency: Bool { bytes[3] == 3 }
    var lightingEffect: Int { Int(bytes[9]) << 8 | Int(bytes[10]) }
    var winLock: Bool { bytes[15] == 1 }
    /// Idle time before sleep in 30-second units; 0 means never.
    var sleepLevel: Int { Int(bytes[24]) }

    var pollingRateHz: Int? {
        switch pollingLevel {
        case 1: 250
        case 2: 500
        case 3: 1000
        default: nil
        }
    }

    var sleepSeconds: Int? { sleepLevel == 0 ? nil : sleepLevel * 30 }

    struct EffectSettings: Equatable {
        let brightness: Int
        let speed: Int
        let color: Int
    }

    /// Stored brightness, speed and colour for an effect (1-based id).
    func settings(forEffect id: Int) -> EffectSettings? {
        guard (1...Self.effectCount).contains(id) else { return nil }
        let at = Self.effectTableOffset + (id - 1) * 2
        return EffectSettings(brightness: Int(bytes[at]), speed: Int(bytes[at + 1] >> 4), color: Int(bytes[at + 1] & 0x0F))
    }

    fileprivate static let effectNames: [Int: String] = [
        0: "Off", 1: "Fixed on", 2: "Respire", 3: "Rainbow", 4: "Flash away",
        5: "Raindrops", 6: "Rainbow wheel", 7: "Ripples shining", 8: "Stars twinkle",
        9: "Shadow disappear", 10: "Retro snake", 11: "Neon stream", 12: "Reaction",
        13: "Sine wave", 14: "Retinue scanning", 15: "Rotating windmill",
        16: "Colorful waterfall", 17: "Blossoming", 18: "Rotating storm",
        // The vendor driver's code for per-key custom lighting (0x0115).
        277: "Custom",
    ]

    var lightingEffectName: String {
        Self.effectName(lightingEffect)
    }
}

// MARK: Changing lighting

extension SettingsPage {
    static let maxBrightness = 9
    static let maxSpeed = 4
    /// Onboard effects offered for selection. 6 and 14 stay dark on the F75
    /// according to the aula-f75-mac-driver project, so they are left out.
    static let selectableEffects: [Int] = (0...18).filter { $0 != 6 && $0 != 14 }

    /// Bytes a lighting change may touch: the per-key flag, the active
    /// effect, and the per-effect brightness/speed table.
    static let lightingOffsets: Set<Int> = Set([9, 10]).union(effectTableOffset..<(length - 2))

    static func effectName(_ id: Int) -> String { effectNames[id] ?? "Effect \(id)" }

    /// A copy with `effect` active and, for a real effect, its stored
    /// brightness and speed replaced. The effect's colour is kept. Returns
    /// nil for values outside what the keyboard is known to accept.
    func settingLighting(effect: Int, brightness: Int, speed: Int) -> SettingsPage? {
        guard Self.selectableEffects.contains(effect),
              (0...Self.maxBrightness).contains(brightness),
              (0...Self.maxSpeed).contains(speed) else { return nil }
        var updated = bytes
        updated[9] = 0
        updated[10] = UInt8(effect)
        if effect != 0 {
            let at = Self.effectTableOffset + (effect - 1) * 2
            updated[at] = UInt8(brightness)
            updated[at + 1] = UInt8(speed) << 4 | (updated[at + 1] & 0x0F)
        }
        return SettingsPage(payload: updated)
    }
}
