//
//  KeyboardMonitor.swift
//  F75Driver
//
//  Observable state for the status window: which connections exist and what
//  the keyboard reports over each. It sends the read requests defined in
//  F75Protocol and one write: lighting changes to the settings page, over
//  the cable only.
//

import Foundation
import IOKit.hid
import Observation

enum ConnectionKind: String, CaseIterable, Identifiable {
    case cable, dongle
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cable: "USB cable"
        case .dongle: "2.4 GHz dongle"
        }
    }
}

/// What one connection last reported.
struct ConnectionStatus {
    var identity: DeviceIdentity?
    var battery: BatteryStatus?
    var settings: SettingsPage?
    /// Raw payloads by request name, for checking the decoding.
    var raw: [(name: String, bytes: [UInt8])] = []
    var error: String?
    var updated: Date?
}

enum AccessState {
    case granted, denied, undetermined
}

@Observable
final class KeyboardMonitor {
    private(set) var access: AccessState = .undetermined
    private(set) var present: Set<ConnectionKind> = []
    private(set) var blocked: Set<ConnectionKind> = []
    private(set) var status: [ConnectionKind: ConnectionStatus] = [:]
    private(set) var isRefreshing = false
    /// Last radio-link announcement from the dongle, if any was seen.
    private(set) var dongleKeyboardOnline: Bool?
    /// Most recent battery reading from any connection. Kept while the
    /// keyboard sleeps and stops answering; cleared when nothing is attached.
    private(set) var lastBattery: BatteryStatus?

    private(set) var isWritingLighting = false
    private(set) var lightingError: String?

    private let transport = HIDTransport()
    private var reassembler: F75Protocol.DongleReassembler?
    private var refreshQueued = false
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        transport.onChange = { [weak self] in self?.connectionsChanged() }
        transport.onDonglePacket = { [weak self] packet in self?.received(packet) }
        updateAccess()
        transport.start()
        connectionsChanged()
        // Keep the battery reading reasonably fresh for the menu bar.
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    // MARK: Permission

    private func updateAccess() {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: access = .granted
        case kIOHIDAccessTypeDenied: access = .denied
        default: access = .undetermined
        }
        transport.mayOpenDevices = access == .granted
    }

    /// Shows the system prompt the first time; afterwards macOS only changes
    /// the answer in System Settings. The request blocks until the prompt is
    /// answered, so it runs off the main thread.
    func requestAccess() {
        Task {
            _ = await Task.detached { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }.value
            retry()
        }
    }

    /// Re-checks permission and reopens interfaces that were blocked.
    func retry() {
        updateAccess()
        transport.rescan(reopen: true)
        connectionsChanged()
    }

    // MARK: Connections

    private func connectionsChanged() {
        updateAccess()
        var present: Set<ConnectionKind> = []
        var blocked: Set<ConnectionKind> = []
        for (kind, link) in [(ConnectionKind.cable, transport.wired), (.dongle, transport.dongle)] {
            guard let link else { continue }
            present.insert(kind)
            if !link.isOpen { blocked.insert(kind) }
        }
        self.present = present
        self.blocked = blocked
        for kind in ConnectionKind.allCases where !present.contains(kind) { status[kind] = nil }
        if !present.contains(.dongle) { dongleKeyboardOnline = nil }
        if present.isEmpty { lastBattery = nil }
        Task { await refresh() }
    }

    private func received(_ packet: [UInt8]) {
        if let online = F75Protocol.dongleOnlineEvent(packet) {
            dongleKeyboardOnline = online
            if online { Task { await refresh() } }
            return
        }
        reassembler?.add(packet)
    }

    // MARK: Reading

    func refresh() async {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            for kind in ConnectionKind.allCases where present.contains(kind) && !blocked.contains(kind) {
                let result = await read(kind)
                status[kind] = result
                if let battery = result.battery { lastBattery = battery }
            }
        } while refreshQueued
    }

    // MARK: Writing

    /// Stores a lighting change on the keyboard. Cable only: the page is read
    /// fresh, changed in its lighting bytes alone, written, and read back.
    func setLighting(effect: Int, brightness: Int, speed: Int) async {
        guard !isWritingLighting else { return }
        isWritingLighting = true
        lightingError = nil
        defer { isWritingLighting = false }
        // Keep refreshes from interleaving their reports with the write.
        while isRefreshing { try? await Task.sleep(for: .milliseconds(20)) }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard let current = SettingsPage(payload: try await readWired(.settings)), current.hasSignature else {
                throw LightingError.unreadable
            }
            guard let updated = current.settingLighting(effect: effect, brightness: brightness, speed: speed),
                  let report = F75Protocol.wiredSettingsWrite(updated, replacing: current) else {
                throw LightingError.rejected
            }
            if updated != current {
                try transport.setWiredFeature(report)
                try await Task.sleep(for: .milliseconds(150))
                let stored = SettingsPage(payload: try await readWired(.settings))
                guard stored == updated else { throw LightingError.notStored }
            }
        } catch {
            lightingError = error.localizedDescription
        }
        status[.cable] = await read(.cable)
    }

    private enum LightingError: LocalizedError {
        case unreadable, rejected, notStored

        var errorDescription: String? {
            switch self {
            case .unreadable: "Could not read the keyboard's current settings, so nothing was changed."
            case .rejected: "That lighting setting is outside what the keyboard is known to accept. Nothing was changed."
            case .notStored: "The keyboard did not report the new lighting back. Check the keyboard and refresh."
            }
        }
    }

    private func read(_ kind: ConnectionKind) async -> ConnectionStatus {
        var result = ConnectionStatus()
        do {
            let identity = try await payload(kind, wired: .identity, dongle: .identity)
            result.raw.append(("Identity", identity))
            result.identity = DeviceIdentity(payload: identity)

            let battery = try await payload(kind, wired: .battery, dongle: .battery)
            result.raw.append(("Battery", battery))
            result.battery = BatteryStatus(payload: battery)

            let settings = try await payload(kind, wired: .settings, dongle: .settings)
            result.raw.append(("Settings page", settings))
            // Only trust the decoding when the page carries its signature.
            if let page = SettingsPage(payload: settings), page.hasSignature { result.settings = page }
        } catch HIDError.noReply where kind == .dongle && result.identity == nil {
            result.error = "The dongle is plugged in but the keyboard is not answering. Check that it is switched to 2.4G and awake."
        } catch {
            result.error = error.localizedDescription
        }
        result.updated = .now
        return result
    }

    private func payload(_ kind: ConnectionKind, wired: F75Protocol.WiredRead, dongle: F75Protocol.DongleRead) async throws -> [UInt8] {
        switch kind {
        case .cable: try await readWired(wired)
        case .dongle: try await readDongle(dongle)
        }
    }

    private func readWired(_ read: F75Protocol.WiredRead) async throws -> [UInt8] {
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(70)) }
            try transport.setWiredFeature(F75Protocol.wiredRequest(read))
            try await Task.sleep(for: .milliseconds(30))
            let reply = try transport.getWiredFeature(reportID: F75Protocol.wiredReportID, length: F75Protocol.wiredReportLength)
            if let payload = F75Protocol.wiredPayload(of: reply, for: read) { return payload }
        }
        throw HIDError.noReply
    }

    private func readDongle(_ read: F75Protocol.DongleRead) async throws -> [UInt8] {
        defer { reassembler = nil }
        for _ in 0..<3 {
            reassembler = F75Protocol.DongleReassembler(read)
            try transport.sendDongleOutput(F75Protocol.dongleRequest(read))
            // Replies arrive on the main run loop while this task sleeps.
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(20))
                if let payload = reassembler?.payload { return payload }
            }
        }
        throw HIDError.noReply
    }
}
