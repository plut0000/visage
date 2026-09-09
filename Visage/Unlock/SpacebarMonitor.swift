import Foundation
import IOKit.hid

@MainActor
final class SpacebarMonitor {
    var onSpaceKeyDown: (() -> Void)?
    private var manager: IOHIDManager?

    static func hasListenAccess() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            || KeystrokeTyper.isAccessibilityTrusted()
    }

    func start() {
        guard manager == nil else { return }
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Int] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(hid, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(hid, { context, _, _, value in
            guard let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardSpacebar),
                  IOHIDValueGetIntegerValue(value) == 1
            else { return }
            let monitor = Unmanaged<SpacebarMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.onSpaceKeyDown?() }
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let open = IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        guard open == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        manager = hid
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }
}
