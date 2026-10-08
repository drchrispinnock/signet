import Foundation
import IOKit
import IOKit.hid

/// Ledger's USB HID framing: an APDU is cut into 64-byte reports, each headed by the channel
/// (0x0101), a tag (0x05) and a sequence number; the first report also carries the total length.
/// Responses come back the same way. Pure functions, so the tests can cover them.
enum LedgerFraming {
    static let packetSize = 64
    static let channel: [UInt8] = [0x01, 0x01]
    static let tag: UInt8 = 0x05

    static func packets(for apdu: [UInt8]) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        var offset = 0
        var sequence: UInt16 = 0
        repeat {
            var packet = channel + [tag, UInt8(sequence >> 8), UInt8(sequence & 0xff)]
            if sequence == 0 {
                packet += [UInt8(apdu.count >> 8), UInt8(apdu.count & 0xff)]
            }
            let room = packetSize - packet.count
            let chunk = apdu[offset ..< min(apdu.count, offset + room)]
            packet += chunk
            packet += [UInt8](repeating: 0, count: packetSize - packet.count)
            packets.append(packet)
            offset += chunk.count
            sequence += 1
        } while offset < apdu.count
        return packets
    }

    /// Collects incoming reports until a whole response has arrived.
    struct Reassembler {
        enum FramingError: Error { case badHeader, outOfOrder(expected: Int, got: Int) }

        private var expectedLength: Int?
        private var data: [UInt8] = []
        private var nextSequence = 0

        init() {}

        /// Feeds one report. Returns the complete response once the last report is in.
        mutating func add(_ packet: [UInt8]) throws -> [UInt8]? {
            guard packet.count >= 5, Array(packet[0..<2]) == channel, packet[2] == tag else { throw FramingError.badHeader }
            let sequence = Int(packet[3]) << 8 | Int(packet[4])
            guard sequence == nextSequence else { throw FramingError.outOfOrder(expected: nextSequence, got: sequence) }
            var body: ArraySlice<UInt8>
            if sequence == 0 {
                guard packet.count >= 7 else { throw FramingError.badHeader }
                expectedLength = Int(packet[5]) << 8 | Int(packet[6])
                body = packet[7...]
            } else {
                body = packet[5...]
            }
            guard let expectedLength else { throw FramingError.badHeader }
            body = body.prefix(expectedLength - data.count)
            data += body
            nextSequence += 1
            guard data.count >= expectedLength else { return nil }
            let complete = data
            self = Reassembler()
            return complete
        }
    }
}

/// A Ledger plugged in over USB, as the HID layer sees it.
struct LedgerDevice: Identifiable, Hashable, Sendable, Codable {
    /// IOKit registry entry id: stable while the device stays plugged in.
    let id: String
    let name: String
    let productID: Int

    /// Model name from the product id when the product string is missing or generic.
    var model: String {
        switch productID >> 8 {
        case 0x10: "Ledger Nano S"
        case 0x40: "Ledger Nano X"
        case 0x50: "Ledger Nano S Plus"
        case 0x60: "Ledger Stax"
        case 0x70: "Ledger Flex"
        default: name.isEmpty ? "Ledger" : name
        }
    }
}

/// Talks to Ledger devices over USB HID with IOKit. One exchange at a time per device; the
/// device's input reports arrive on a private run-loop thread, which is also where all state
/// lives. Callers get their answer on `completionQueue`.
final class LedgerHID: @unchecked Sendable {
    enum HIDError: LocalizedError {
        case noSuchDevice
        case openFailed(IOReturn)
        case writeFailed(IOReturn)
        case timeout
        case busy
        case unplugged

        var errorDescription: String? {
            switch self {
            case .noSuchDevice: "No Ledger is connected. Plug it in, unlock it and open the Tezos app."
            case .openFailed(let code): "Could not open the Ledger (IOKit error \(String(code, radix: 16)))."
            case .writeFailed(let code): "Could not write to the Ledger (IOKit error \(String(code, radix: 16)))."
            case .timeout: "The Ledger did not answer in time."
            case .busy: "The Ledger is busy with another request."
            case .unplugged: "The Ledger was unplugged."
            }
        }
    }

    static let shared = LedgerHID()
    static let vendorID = 0x2c97
    /// Ledger's vendor-specific HID interface; the same devices also show keyboard/U2F interfaces.
    static let usagePage = 0xffa0

    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private var open: [String: OpenDevice] = [:]

    private final class OpenDevice {
        let device: IOHIDDevice
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: LedgerFraming.packetSize)
        var reassembler = LedgerFraming.Reassembler()
        var pending: (completion: (Result<[UInt8], Error>) -> Void, timer: Timer?)?
        init(device: IOHIDDevice) { self.device = device }
        deinit { buffer.deallocate() }
    }

    private init() {
        let thread = Thread { [unowned self] in self.threadMain() }
        thread.name = "org.tezos.signet.ledger-hid"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
    }

    private func threadMain() {
        runLoop = CFRunLoopGetCurrent()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Self.vendorID, kIOHIDPrimaryUsagePageKey: Self.usagePage] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LedgerHID>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        ready.signal()
        while true { CFRunLoopRun() }
    }

    /// Runs `body` on the HID thread and waits for it.
    private func onThread<T>(_ body: @escaping () -> T) -> T {
        guard let runLoop else { fatalError("LedgerHID thread not started") }
        if CFRunLoopGetCurrent() == runLoop { return body() }
        let done = DispatchSemaphore(value: 0)
        var result: T?
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            result = body()
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
        return result!
    }

    private func async(_ body: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, body)
        CFRunLoopWakeUp(runLoop)
    }

    /// Ledgers currently plugged in (vendor-specific HID interface only).
    func devices() -> [LedgerDevice] {
        onThread { [self] in
            guard let manager, let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
            return set.compactMap(Self.describe).sorted { $0.id < $1.id }
        }
    }

    private static func describe(_ device: IOHIDDevice) -> LedgerDevice? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &entryID) == KERN_SUCCESS else { return nil }
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return LedgerDevice(id: String(entryID), name: name, productID: pid)
    }

    private func device(withID id: String) -> IOHIDDevice? {
        guard let manager, let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        return set.first { Self.describe($0)?.id == id }
    }

    /// Sends one APDU and delivers the response (data ‖ status word) or an error.
    func exchange(deviceID: String, apdu: [UInt8], timeout: TimeInterval, completionQueue: DispatchQueue, completion: @escaping @Sendable (Result<[UInt8], Error>) -> Void) {
        async { [self] in
            let finish: (Result<[UInt8], Error>) -> Void = { result in completionQueue.async { completion(result) } }
            do {
                let open = try openDevice(id: deviceID)
                guard open.pending == nil else { throw HIDError.busy }
                open.reassembler = LedgerFraming.Reassembler()
                let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
                    self?.timedOut(deviceID: deviceID)
                }
                RunLoop.current.add(timer, forMode: .default)
                open.pending = (finish, timer)
                for packet in LedgerFraming.packets(for: apdu) {
                    let status = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(open.device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, packet.count) }
                    guard status == kIOReturnSuccess else {
                        open.pending = nil
                        timer.invalidate()
                        throw HIDError.writeFailed(status)
                    }
                }
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func openDevice(id: String) throws -> OpenDevice {
        if let existing = open[id] { return existing }
        guard let device = device(withID: id) else { throw HIDError.noSuchDevice }
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw HIDError.openFailed(status) }
        let entry = OpenDevice(device: device)
        let context = Unmanaged.passUnretained(entry).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, entry.buffer, LedgerFraming.packetSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            let entry = Unmanaged<OpenDevice>.fromOpaque(context).takeUnretainedValue()
            let packet = Array(UnsafeBufferPointer(start: report, count: length))
            LedgerHID.shared.received(packet, on: entry)
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        open[id] = entry
        return entry
    }

    private func timedOut(deviceID: String) {
        guard let entry = open[deviceID], let pending = entry.pending else { return }
        entry.pending = nil
        pending.completion(.failure(HIDError.timeout))
    }

    private func received(_ packet: [UInt8], on entry: OpenDevice) {
        guard let pending = entry.pending else { return }
        do {
            guard let response = try entry.reassembler.add(packet) else { return }
            entry.pending = nil
            pending.timer?.invalidate()
            pending.completion(.success(response))
        } catch {
            entry.pending = nil
            pending.timer?.invalidate()
            pending.completion(.failure(error))
        }
    }

    private func removed(_ device: IOHIDDevice) {
        for (id, entry) in open where entry.device == device {
            open[id] = nil
            if let pending = entry.pending {
                entry.pending = nil
                pending.timer?.invalidate()
                pending.completion(.failure(HIDError.unplugged))
            }
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
