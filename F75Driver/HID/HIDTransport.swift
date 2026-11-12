//
//  HIDTransport.swift
//  F75Driver
//
//  Finds the keyboard's configuration interfaces with IOKit and moves raw
//  reports. Everything runs on the main run loop.
//

import Foundation
import IOKit.hid

nonisolated enum HIDError: Error, LocalizedError {
    case notConnected
    case openFailed(IOReturn)
    case sendFailed(IOReturn)
    case receiveFailed(IOReturn)
    case noReply

    var errorDescription: String? {
        func code(_ r: IOReturn) -> String { "0x" + String(UInt32(bitPattern: r), radix: 16) }
        switch self {
        case .notConnected: return "Not connected."
        case .openFailed(let r):
            return r == kIOReturnNotPermitted
                ? "macOS blocked access to the keyboard. Input Monitoring permission is required."
                : "Could not open the keyboard (\(code(r)))."
        case .sendFailed(let r): return "Sending to the keyboard failed (\(code(r)))."
        case .receiveFailed(let r): return "Reading from the keyboard failed (\(code(r)))."
        case .noReply: return "The keyboard did not answer."
        }
    }
}

/// Main-thread only. Marked unchecked-Sendable so the IOKit C callbacks can
/// carry it through their context pointer.
nonisolated final class HIDTransport: @unchecked Sendable {
    /// One of the keyboard's interfaces, with the result of opening it.
    struct Link {
        let device: IOHIDDevice
        let openResult: IOReturn
        var isOpen: Bool { openResult == kIOReturnSuccess }
    }

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let inputBufferLength = 64

    private(set) var wired: Link?
    private(set) var dongle: Link?

    /// Opening a keyboard interface without Input Monitoring permission makes
    /// macOS show its prompt and blocks the caller until it is answered, so
    /// interfaces are only opened once the owner says permission is in place.
    var mayOpenDevices = false

    /// Called on the main thread when an interface appears or disappears.
    var onChange: (@MainActor () -> Void)?
    /// Called on the main thread with each dongle input packet (report ID removed).
    var onDonglePacket: (@MainActor ([UInt8]) -> Void)?

    func start() {
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDVendorIDKey: F75Protocol.wiredVendorID, kIOHIDProductIDKey: F75Protocol.wiredProductID],
            [kIOHIDVendorIDKey: F75Protocol.dongleVendorID, kIOHIDProductIDKey: F75Protocol.dongleProductID],
        ] as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let changed: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().rescan()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, changed, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, changed, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        rescan()
    }

    /// Re-evaluates which interfaces are present and (re)opens them. Also
    /// used to retry after the user grants permission.
    func rescan(reopen: Bool = false) {
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        func int(_ device: IOHIDDevice, _ key: String) -> Int { IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0 }

        let config = devices.first {
            int($0, kIOHIDVendorIDKey) == F75Protocol.wiredVendorID
                && int($0, kIOHIDMaxFeatureReportSizeKey) >= F75Protocol.wiredReportLength
        }
        let radio = devices.first {
            int($0, kIOHIDVendorIDKey) == F75Protocol.dongleVendorID
                && int($0, kIOHIDPrimaryUsagePageKey) >= 0xFF00
                && int($0, kIOHIDMaxOutputReportSizeKey) >= F75Protocol.dongleReportLength
        }

        let before = (wired?.device, wired?.isOpen, dongle?.device, dongle?.isOpen)
        wired = link(for: config, current: wired, reopen: reopen)
        let newDongle = link(for: radio, current: dongle, reopen: reopen)
        if let newDongle, newDongle.isOpen, newDongle.device !== dongle?.device || dongle?.isOpen != true {
            listen(to: newDongle.device)
        }
        dongle = newDongle

        if before.0 !== wired?.device || before.1 != wired?.isOpen || before.2 !== dongle?.device || before.3 != dongle?.isOpen {
            MainActor.assumeIsolated { onChange?() }
        }
    }

    private func link(for device: IOHIDDevice?, current: Link?, reopen: Bool) -> Link? {
        guard let device else { return nil }
        if let current, current.device === device, current.isOpen || !reopen { return current }
        guard mayOpenDevices else { return Link(device: device, openResult: kIOReturnNotPermitted) }
        return Link(device: device, openResult: IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)))
    }

    private func listen(to device: IOHIDDevice) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, inputBufferLength, { context, _, _, _, reportID, report, length in
            guard let context, length > 0 else { return }
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            // Numbered reports arrive with their ID in front.
            if reportID != 0, bytes.first == UInt8(truncatingIfNeeded: reportID) { bytes.removeFirst() }
            let transport = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { transport.onDonglePacket?(bytes) }
        }, context)
    }

    // MARK: Raw reports

    func setWiredFeature(_ report: [UInt8]) throws {
        let device = try open(wired)
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(report[0]), report, report.count)
        guard result == kIOReturnSuccess else { throw HIDError.sendFailed(result) }
    }

    /// Returned bytes start with the report ID.
    func getWiredFeature(reportID: UInt8, length: Int) throws -> [UInt8] {
        let device = try open(wired)
        var buffer = [UInt8](repeating: 0, count: length)
        buffer[0] = reportID
        var received = CFIndex(length)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), &buffer, &received)
        guard result == kIOReturnSuccess else { throw HIDError.receiveFailed(result) }
        return Array(buffer.prefix(received))
    }

    func sendDongleOutput(_ report: [UInt8]) throws {
        let device = try open(dongle)
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        guard result == kIOReturnSuccess else { throw HIDError.sendFailed(result) }
    }

    private func open(_ link: Link?) throws -> IOHIDDevice {
        guard let link else { throw HIDError.notConnected }
        guard link.isOpen else { throw HIDError.openFailed(link.openResult) }
        return link.device
    }
}
