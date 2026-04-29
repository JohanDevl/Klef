import Foundation
import IOKit.hid

/// Manages an `IOHIDManager` for all Generic Desktop / Keyboard devices.
///
/// Uses `kIOHIDOptionsTypeNone` (shared monitoring) so Klef never seizes the
/// keyboard away from other apps.
///
/// Callbacks are bridged from C via `Unmanaged.passUnretained(self)` — the
/// caller MUST keep the `HIDKeyboardManager` instance alive for the entire
/// `CFRunLoopRun()` lifetime, OR call `stop()` before releasing the last
/// strong reference. `stop()` unregisters callbacks before closing the
/// manager so a dangling Swift pointer can never be dereferenced. (V1
/// upgrade path: move to a dedicated RunLoop per PRD §7.)
final class HIDKeyboardManager {

    // MARK: - Public callbacks

    var onMatched: ((KeyboardDevice) -> Void)?
    var onRemoved: ((KeyboardDevice) -> Void)?
    var onEvent: ((KeyboardDevice, IOHIDValue) -> Void)?

    // MARK: - Private state

    private let manager: IOHIDManager
    private var deviceCache: [ObjectIdentifier: KeyboardDevice] = [:]
    private var started = false

    // MARK: - Init / deinit

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey:     kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Registers callbacks, schedules on the main run loop, and opens the HID manager.
    ///
    /// Returns `false` if `IOHIDManagerOpen` fails (e.g. permission denied).
    @discardableResult
    func start() -> Bool {
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        // Device matched
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let ctx = context else { return }
                let mgr = Unmanaged<HIDKeyboardManager>.fromOpaque(ctx).takeUnretainedValue()
                mgr.handleMatched(device: device)
            },
            ctx
        )

        // Device removed
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let ctx = context else { return }
                let mgr = Unmanaged<HIDKeyboardManager>.fromOpaque(ctx).takeUnretainedValue()
                mgr.handleRemoved(device: device)
            },
            ctx
        )

        // Input value
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, _, _, value in
                guard let ctx = context else { return }
                let mgr = Unmanaged<HIDKeyboardManager>.fromOpaque(ctx).takeUnretainedValue()
                mgr.handleValue(value: value)
            },
            ctx
        )

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let ret = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard ret == kIOReturnSuccess else {
            let hex = String(format: "0x%08X", UInt32(bitPattern: ret))
            let symbolic: String = {
                switch ret {
                case kIOReturnNotPermitted: return " (kIOReturnNotPermitted — Input Monitoring denied)"
                case kIOReturnNotOpen:      return " (kIOReturnNotOpen)"
                case kIOReturnNoDevice:     return " (kIOReturnNoDevice)"
                default:                    return ""
                }
            }()
            Log.error("IOHIDManagerOpen failed: \(hex)\(symbolic)")
            return false
        }

        started = true
        return true
    }

    /// Unregisters all callbacks, unschedules from the run loop, and closes
    /// the manager. Idempotent and safe to call multiple times. Always call
    /// before the last strong reference to `self` is dropped if you can't
    /// guarantee the manager outlives the run loop.
    func stop() {
        guard started else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        started = false
    }

    // MARK: - Callback handlers

    private func handleMatched(device: IOHIDDevice) {
        guard let kb = KeyboardDevice.from(device) else {
            Log.warn("Matched device could not be parsed (no vendor/product/location) — skipping")
            return
        }
        deviceCache[ObjectIdentifier(device)] = kb
        onMatched?(kb)
    }

    private func handleRemoved(device: IOHIDDevice) {
        guard let kb = deviceCache.removeValue(forKey: ObjectIdentifier(device)) else { return }
        onRemoved?(kb)
    }

    private func handleValue(value: IOHIDValue) {
        let device = IOHIDElementGetDevice(IOHIDValueGetElement(value))
        guard let kb = deviceCache[ObjectIdentifier(device)] else { return }
        onEvent?(kb, value)
    }
}
