import Foundation
import IOKit
import IOKit.hid

func enumTestMain() {

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    // No matching filter — list everything
    IOHIDManagerSetDeviceMatching(manager, nil)
    let open = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    print("manager open: 0x\(String(UInt32(bitPattern: open), radix: 16))")

    if let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
        print("total HID devices: \(set.count)")
        for dev in set {
            func prop(_ k: String) -> String {
                (IOHIDDeviceGetProperty(dev, k as CFString) as? NSNumber)?.stringValue
                    ?? (IOHIDDeviceGetProperty(dev, k as CFString) as? String) ?? "?"
            }
            let vid = prop(kIOHIDVendorIDKey)
            if vid == "39046" || prop(kIOHIDProductKey).contains("Astro") {
                print("  ASTRO: product=\(prop(kIOHIDProductKey)) vid=\(vid) pid=\(prop(kIOHIDProductIDKey)) page=\(prop(kIOHIDPrimaryUsagePageKey)) usage=\(prop(kIOHIDPrimaryUsageKey))")
            }
        }
    } else {
        print("CopyDevices returned nil / cast failed")
    }

    // Now with matching filter like the app uses
    let manager2 = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let match: [String: Any] = [
        kIOHIDVendorIDKey as String: 0x9886,
        kIOHIDProductIDKey as String: 0x002C,
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager2, [match] as CFArray)
    _ = IOHIDManagerOpen(manager2, IOOptionBits(kIOHIDOptionsTypeNone))
    if let set2 = IOHIDManagerCopyDevices(manager2) as? Set<IOHIDDevice> {
        print("matched with filter: \(set2.count)")
    } else {
        print("matched with filter: nil")
    }

    // Try vendor-only filter
    let manager3 = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager3, [kIOHIDVendorIDKey as String: 0x9886] as CFDictionary)
    _ = IOHIDManagerOpen(manager3, IOOptionBits(kIOHIDOptionsTypeNone))
    if let set3 = IOHIDManagerCopyDevices(manager3) as? Set<IOHIDDevice> {
        print("matched vendor-only: \(set3.count)")
    } else {
        print("matched vendor-only: nil")
    }

}
