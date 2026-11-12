//
//  F75DriverTests.swift
//  F75DriverTests
//

import Testing
@testable import F75Driver

struct WiredProtocolTests {
    @Test func identityRequestMatchesVendorBytes() {
        let report = F75Protocol.wiredRequest(.identity)
        #expect(report.count == 520)
        #expect(Array(report.prefix(8)) == [0x06, 0x82, 0x01, 0x00, 0x01, 0x00, 0x06, 0x00])
        #expect(report.dropFirst(8).allSatisfy { $0 == 0 })
    }

    @Test func settingsAndBatteryRequests() {
        #expect(Array(F75Protocol.wiredRequest(.settings).prefix(7)) == [0x06, 0x84, 0x00, 0x00, 0x01, 0x00, 0x80])
        #expect(Array(F75Protocol.wiredRequest(.battery).prefix(8)) == [0x06, 0x87, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00])
    }

    /// Writes are the read commands without the top bit; none may be expressible.
    @Test func everyRequestIsARead() {
        for read in F75Protocol.WiredRead.allCases {
            #expect(read.command & 0x80 != 0)
        }
    }

    @Test func payloadIsTakenAfterHeader() {
        var reply = [UInt8](repeating: 0, count: 520)
        reply[0] = 0x06
        reply[1] = 0x82
        reply.replaceSubrange(8..<14, with: [0x03, 0x00, 0x00, 0x00, 0x00, 0xCD])
        let payload = F75Protocol.wiredPayload(of: reply, for: .identity)
        #expect(payload == [0x03, 0x00, 0x00, 0x00, 0x00, 0xCD])
        #expect(DeviceIdentity(payload: payload ?? [])?.modelName == "AULA F75")
    }

    @Test func staleOrEmptyRepliesAreRejected() {
        var reply = [UInt8](repeating: 0, count: 520)
        reply[0] = 0x06
        #expect(F75Protocol.wiredPayload(of: reply, for: .settings) == nil)
        reply[1] = 0x82
        #expect(F75Protocol.wiredPayload(of: reply, for: .settings) == nil)
        #expect(F75Protocol.wiredPayload(of: [0x06, 0x84], for: .settings) == nil)
    }
}

struct DongleProtocolTests {
    @Test func requestCarriesChecksumOverReportIDAndBody() {
        let report = F75Protocol.dongleRequest(.battery)
        #expect(report.count == 20)
        #expect(report[0] == 0x13)
        #expect(report[1] == 0x4A)
        // 0x13 + 0x4A = 0x5D
        #expect(report[19] == 0x5D)

        let identity = F75Protocol.dongleRequest(.identity)
        #expect(Array(identity.prefix(5)) == [0x13, 0x05, 0x01, 0x00, 0x00])
        #expect(identity[19] == 0x19)

        let settings = F75Protocol.dongleRequest(.settings)
        // 0x13 + 0x44 + 0x01 + 0x10 = 0x68
        #expect(settings[19] == 0x68)
    }

    @Test func onlyKnownReadCommandsExist() {
        #expect(Set(F75Protocol.DongleRead.allCases.map(\.command)) == [0x05, 0x44, 0x4A])
    }

    @Test func reassemblesOutOfOrderPackets() {
        var reassembler = F75Protocol.DongleReassembler(.settings)
        let page = (0..<140).map { UInt8($0) }
        var packets: [[UInt8]] = []
        for index in 0..<10 {
            var packet: [UInt8] = [0x44, 10, UInt8(index), 14]
            packet.append(contentsOf: page[(index * 14)..<(index * 14 + 14)])
            packet.append(0x00)
            packets.append(packet)
        }
        for packet in packets.reversed().dropLast() {
            let accepted = reassembler.add(packet)
            #expect(accepted)
            #expect(reassembler.payload == nil)
        }
        let acceptedLast = reassembler.add(packets[0])
        #expect(acceptedLast)
        #expect(reassembler.payload == Array(page.prefix(128)))
    }

    @Test func ignoresPacketsForOtherRequests() {
        var reassembler = F75Protocol.DongleReassembler(.battery)
        let otherCommand = reassembler.add([0x05, 1, 0, 6, 3, 0, 0, 0, 0, 0xCD, 0])
        let otherCount = reassembler.add([0x4A, 2, 0, 2, 80, 1, 0])
        #expect(!otherCommand)
        #expect(!otherCount)
        #expect(reassembler.payload == nil)
        let accepted = reassembler.add([0x4A, 1, 0, 2, 80, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x00])
        #expect(accepted)
        #expect(BatteryStatus(payload: reassembler.payload ?? [])?.level == 80)
    }

    @Test func onlineEvents() {
        #expect(F75Protocol.dongleOnlineEvent([0x0A, 0, 0, 0, 0x02, 0x01]) == true)
        #expect(F75Protocol.dongleOnlineEvent([0x0A, 0, 0, 0, 0x02, 0x00]) == false)
        #expect(F75Protocol.dongleOnlineEvent([0x4A, 1, 0, 2, 0x02, 0x01]) == nil)
    }
}

struct SettingsPageTests {
    private func page(_ changes: [Int: UInt8]) -> SettingsPage? {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[126] = 0x5A
        bytes[127] = 0xA5
        for (offset, value) in changes { bytes[offset] = value }
        return SettingsPage(payload: bytes)
    }

    @Test func decodesKnownFields() throws {
        let settings = try #require(page([0: 1, 1: 3, 3: 3, 10: 7, 15: 1, 24: 10, 70: 4, 71: 0x27]))
        #expect(settings.hasSignature)
        #expect(settings.macMode)
        #expect(settings.pollingRateHz == 1000)
        #expect(settings.lowLatency)
        #expect(settings.lightingEffect == 7)
        #expect(settings.lightingEffectName == "Ripples shining")
        #expect(settings.winLock)
        #expect(settings.sleepSeconds == 300)
        // Effect 7 lives at 58 + 6 * 2 = 70.
        #expect(settings.settings(forEffect: 7) == .init(brightness: 4, speed: 2, color: 7))
    }

    @Test func neverSleepAndUnknownValues() throws {
        let settings = try #require(page([1: 9, 10: 30]))
        #expect(settings.sleepSeconds == nil)
        #expect(settings.pollingRateHz == nil)
        #expect(settings.lightingEffectName == "Effect 30")
        #expect(settings.settings(forEffect: 0) == nil)
        #expect(settings.settings(forEffect: 35) == nil)
    }

    @Test func rejectsShortPagesAndDetectsMissingSignature() throws {
        #expect(SettingsPage(payload: [UInt8](repeating: 0, count: 100)) == nil)
        let unsigned = try #require(SettingsPage(payload: [UInt8](repeating: 0, count: 128)))
        #expect(!unsigned.hasSignature)
    }
}
