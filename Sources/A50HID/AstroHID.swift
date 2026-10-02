import Foundation
import IOKit
import IOKit.hid

/// HID client for the Astro A50 base station (vendor 0x9886, product 0x002C).
///
/// Protocol (interface 6, usage page 0xFF32 / usage 0x74, Report ID 0x02):
///   request  = output report: [0x02, command, length, payload...]
///   response = input report:  [0x02, status, length, payload...]
///     status: 0 = NO_RESPONSE, 1 = ERROR, 2 = OK
///
/// Feature reports are not supported by this device (maxFeatureReportSize == 1),
/// so everything goes over interrupt OUT/IN.
///
/// Threading: all HID work runs on a single private worker thread that owns the
/// device and its run loop — scheduling, sending, and pumping the run loop for
/// the reply happen there, so callbacks are delivered reliably.
public final class AstroHID {
    public init() { startWorker() }

    enum Command {
        static let getHeadsetStatus: UInt8 = 0x54
        static let getBatteryStatus: UInt8 = 0x7C
    }

    public struct HeadsetStatus {
        public var isDocked: Bool
        public var isOn: Bool
    }

    public struct BatteryStatus {
        public var chargePercent: Int
        public var isCharging: Bool
    }

    public enum HIDError: Error, CustomStringConvertible {
        case deviceNotFound
        case deviceBusy
        case noResponse(UInt8)
        case deviceError(String)
        case openFailed(IOReturn)
        case badFrame

        public var description: String {
            switch self {
            case .deviceNotFound:
                return "Astro A50 HID interface not found (VID 0x9886 / PID 0x002C). Is the base station plugged in?"
            case .deviceBusy:
                return "Astro A50 interface is claimed by another process (ASTRO Command Center or another A50 client). Close it and retry."
            case .noResponse(let cmd):
                return String(format: "No valid response for cmd 0x%02X", cmd)
            case .deviceError(let message):
                return "Device error: \(message)"
            case .openFailed(let code):
                return "IOHIDDeviceOpen failed: 0x\(String(UInt32(bitPattern: code), radix: 16))"
            case .badFrame:
                return "Unexpected response frame"
            }
        }
    }

    /// Description of a matched HID interface, for diagnostics.
    public struct DeviceDescription {
        public var product: String
        public var transport: String
        public var vendorID: Int
        public var productID: Int
        public var usagePage: Int
        public var usage: Int
        public var openable: Bool
    }

    private static let reportID: CFIndex = 0x02

    // MARK: - Worker thread
    //
    // All HID work runs on one dedicated thread (not a GCD queue, which may hop
    // threads): the device must be scheduled and pumped on the same run loop.

    private var workerThread: Thread?
    private let workerLock = NSLock()
    private let workReady = DispatchSemaphore(value: 0)
    private let workDone = DispatchSemaphore(value: 0)
    private var pendingWork: (() -> Void)?

    private func startWorker() {
        workerLock.lock()
        defer { workerLock.unlock() }
        guard workerThread == nil else { return }
        let thread = Thread { [weak self] in
            while true {
                guard let self else { return }
                self.workReady.wait()
                let work = self.pendingWork
                self.pendingWork = nil
                work?()
                self.workDone.signal()
            }
        }
        thread.name = "a50-hid-worker"
        thread.start()
        workerThread = thread
    }

    /// Runs `body` synchronously on the worker thread. Callers are serialized.
    private func sync<T>(_ body: @escaping () throws -> T) throws -> T {
        startWorker()
        callLock.lock()
        defer { callLock.unlock() }
        var result: Result<T, Error>?
        workerLock.lock()
        pendingWork = {
            do { result = .success(try body()) }
            catch { result = .failure(error) }
        }
        workerLock.unlock()
        workReady.signal()
        workDone.wait()
        return try result!.get()
    }

    private let callLock = NSLock()

    // MARK: - Response sink

    private final class ResponseSink {
        private let lock = NSLock()
        private var bytes: [UInt8] = []
        private var sequence = 0

        func push(_ report: [UInt8]) {
            lock.lock()
            bytes = report
            sequence += 1
            lock.unlock()
        }

        /// Returns (report, sequence) — sequence lets callers ignore stale replies.
        func snapshot() -> ([UInt8], Int) {
            lock.lock()
            defer { lock.unlock() }
            return (bytes, sequence)
        }
    }

    private let sink = ResponseSink()
    private var device: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var scheduledLoop: CFRunLoop?

    // MARK: - Device discovery

    private static func matchedDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x9886,
            kIOHIDProductIDKey as String: 0x002C,
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [match] as CFArray)
        // Open can return kIOReturnExclusiveAccess if some *other* interface is
        // claimed elsewhere in the registry; that doesn't stop us enumerating.
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }
        return Array(set)
    }

    /// Lists every HID interface the OS exposes for the A50 base station.
    public static func listMatchedDevices() -> [DeviceDescription] {
        matchedDevices().map { dev in
            func intProp(_ key: String) -> Int? {
                (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue
            }
            func strProp(_ key: String) -> String {
                IOHIDDeviceGetProperty(dev, key as CFString) as? String ?? "?"
            }
            let openResult = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            if openResult == kIOReturnSuccess {
                IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            return DeviceDescription(
                product: strProp(kIOHIDProductKey),
                transport: strProp(kIOHIDTransportKey),
                vendorID: intProp(kIOHIDVendorIDKey) ?? -1,
                productID: intProp(kIOHIDProductIDKey) ?? -1,
                usagePage: intProp(kIOHIDPrimaryUsagePageKey) ?? -1,
                usage: intProp(kIOHIDPrimaryUsageKey) ?? -1,
                openable: openResult == kIOReturnSuccess
            )
        }
        .sorted { ($0.usagePage, $0.usage) < ($1.usagePage, $1.usage) }
    }

    // MARK: - Open / close (worker thread only)

    private func ensureDeviceLocked() throws -> IOHIDDevice {
        if let device { return device }

        var foundButSeized = false
        for candidate in Self.matchedDevices() {
            // Seize the interface: input reports are broadcast to every open
            // client, so if a second process (probe, Command Center) also opens
            // the device we would misread *its* replies as ours (e.g. a battery
            // read catching someone else's headset-status answer). Seizing makes
            // a second client fail loudly instead of silently corrupting us.
            guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess else {
                foundButSeized = true
                continue
            }

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65)
            buffer.initialize(repeating: 0, count: 65)
            let sinkRef = Unmanaged.passUnretained(sink).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(candidate, buffer, 65, { context, _, _, _, _, report, length in
                guard let context else { return }
                let sink = Unmanaged<ResponseSink>.fromOpaque(context).takeUnretainedValue()
                sink.push([UInt8](UnsafeBufferPointer(start: report, count: Int(length))))
            }, sinkRef)

            // Schedule on the worker queue's thread run loop and pump it during
            // exchange() so callbacks are delivered while we wait.
            let loop = CFRunLoopGetCurrent()!
            IOHIDDeviceScheduleWithRunLoop(candidate, loop, CFRunLoopMode.defaultMode.rawValue)

            device = candidate
            reportBuffer = buffer
            scheduledLoop = loop
            return candidate
        }
        if foundButSeized { throw HIDError.deviceBusy }
        throw HIDError.deviceNotFound
    }

    private func closeLocked() {
        guard let device else { return }
        if let loop = scheduledLoop {
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBuffer?.deallocate()
        reportBuffer = nil
        scheduledLoop = nil
        self.device = nil
    }

    /// Closes the device so the next query reopens it.
    public func close() {
        try? sync { self.closeLocked() }
    }

    // MARK: - Protocol

    private func buildRequest(_ command: UInt8, payload: [UInt8]?) -> [UInt8] {
        var frame: [UInt8] = [0x02, command]  // 0x02 = report ID
        if let payload, !payload.isEmpty {
            frame.append(UInt8(payload.count & 0xFF))
            frame.append(contentsOf: payload.map { $0 & 0xFF })
        } else {
            frame.append(0x00)
        }
        return frame
    }

    private func parseResponse(_ report: [UInt8]) throws -> [UInt8] {
        guard report.count >= 3, report[0] == 0x02 else { throw HIDError.badFrame }
        let status = report[1]
        let length = min(Int(report[2]), report.count - 3)
        let data = Array(report[3..<(3 + max(0, length))])
        switch status {
        case 2:
            return data
        case 1:
            // Error responses carry 4 unknown bytes, then a NUL-terminated message.
            let msgData = data.count > 4 ? Array(data[4...]) : data
            let message = msgData.prefix { $0 != 0 }.map { String(UnicodeScalar($0)) }.joined()
            throw HIDError.deviceError(message)
        default:
            throw HIDError.noResponse(0)
        }
    }

    /// One exchange: write an output report, pump the run loop for the reply.
    /// Must run on the worker thread (which owns the device run loop).
    private func exchangeLocked(_ command: UInt8, payload: [UInt8]?, timeout: Double) throws -> [UInt8] {
        let dev = try ensureDeviceLocked()
        let (_, before) = sink.snapshot()

        var request = buildRequest(command, payload: payload)
        let count = request.count
        let setResult = request.withUnsafeMutableBytes { ptr -> IOReturn in
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, Self.reportID,
                                 ptr.baseAddress!.assumingMemoryBound(to: UInt8.self), count)
        }
        guard setResult == kIOReturnSuccess else { throw HIDError.openFailed(setResult) }

        // Pump this thread's run loop until a *parseable* input report arrives.
        // The base station can hand back a malformed report while it is busy —
        // observed immediately after SAVE_VALUES acknowledges — and dropping
        // that one frame beats failing the whole exchange.
        let deadline = Date().addingTimeInterval(timeout)
        var lastSeen = before
        var sawJunk = false
        while Date() < deadline {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, true)
            let (report, sequence) = sink.snapshot()
            guard sequence > lastSeen else { continue }
            lastSeen = sequence
            do {
                return try parseResponse(report)
            } catch HIDError.badFrame {
                sawJunk = true   // stray frame: keep waiting for the real reply
            }
        }
        throw sawJunk ? HIDError.badFrame : HIDError.noResponse(command)
    }

    private func queryLocked(_ command: UInt8, payload: [UInt8]?, retries: Int, timeout: Double) throws -> [UInt8] {
        var lastError: Error = HIDError.noResponse(command)
        for _ in 0..<retries {
            do {
                return try exchangeLocked(command, payload: payload, timeout: timeout)
            } catch {
                lastError = error
                if case HIDError.deviceNotFound = error { closeLocked() }
                if case HIDError.deviceBusy = error { closeLocked() }
            }
            usleep(60_000)
        }
        throw lastError
    }

    // MARK: - Public API

    /// Sends an arbitrary command and returns the raw payload — used by a50probe
    /// for protocol diagnostics.
    ///
    /// `timeout` is per attempt. Most commands answer in well under 100ms, but
    /// `SAVE_VALUES` (0x61) takes ~2s before it replies.
    public func rawQuery(_ command: UInt8, payload: [UInt8]? = nil, retries: Int = 4, timeout: Double = 1.0) throws -> [UInt8] {
        try sync { try self.queryLocked(command, payload: payload, retries: retries, timeout: timeout) }
    }

    /// Which usage/usagePage the client currently talks to (nil when not open).
    public func currentInterfaceInfo() -> String? {
        guard let device else { return nil }
        func intProp(_ key: String) -> Int? {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
        }
        guard let page = intProp(kIOHIDPrimaryUsagePageKey), let usage = intProp(kIOHIDPrimaryUsageKey) else { return nil }
        return String(format: "usage page 0x%02X / usage 0x%02X", page, usage)
    }

    public func getHeadsetStatus() throws -> HeadsetStatus {
        let payload = try rawQuery(Command.getHeadsetStatus)
        guard let first = payload.first else { throw HIDError.badFrame }
        // Only bits 0 (docked) and 1 (on) are defined. Anything else means we
        // caught a reply meant for another client — treat as stale and retry.
        guard first <= 0x03 else { throw HIDError.badFrame }
        return HeadsetStatus(isDocked: (first & 0x01) != 0, isOn: (first & 0x02) != 0)
    }

    public func getBatteryStatus() throws -> BatteryStatus {
        var lastError: Error = HIDError.noResponse(Command.getBatteryStatus)
        for _ in 0..<6 {
            do {
                let payload = try rawQuery(Command.getBatteryStatus)
                guard let first = payload.first else { continue }
                let status = BatteryStatus(chargePercent: Int(first & 0x7F), isCharging: (first & 0x80) != 0)
                if (0...100).contains(status.chargePercent) { return status }
            } catch {
                lastError = error
            }
            usleep(50_000)
        }
        throw lastError
    }
}
