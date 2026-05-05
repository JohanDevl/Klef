import Foundation
import IOKit.hid

/// Tracks which keyboard is currently dominant and calls `InputSourceSwitcher`
/// each time dominance changes or a mapped keyboard connects.
///
/// Threading invariant: every mutation of `dominant` and `lastEventAt` runs on
/// the main thread. HID callbacks today land on the main RunLoop, and the
/// switcher's completion is dispatched back to main. PRD §7 plans a dedicated
/// HID RunLoop in V1 — when that lands, the switcher's main-thread dispatch
/// keeps this invariant intact.
final class DominantDeviceTracker {

    // MARK: - State

    private(set) var dominant: KeyboardDevice?
    private let mapping: DeviceLayoutMapping
    private var lastEventAt: Date?
    /// Window after the last *mapped*-keyboard event during which a hot-plug
    /// is treated as "user is mid-typing on another keyboard, don't steal
    /// dominance". Outside the window a fresh connect is treated as a cold
    /// plug and switches immediately. Tuned by feel; not a PRD spec.
    /// Tracking is scoped to mapped devices so background HID traffic from a
    /// "don't switch" peripheral (Stream Deck, gamepad) does not suppress
    /// legitimate switch-on-connect.
    private static let activeSessionWindow: TimeInterval = 1.5

    // MARK: - Init

    init(mapping: DeviceLayoutMapping) {
        self.mapping = mapping
    }

    // MARK: - Observation

    /// Called on every HID input value.
    ///
    /// Two short-circuit paths:
    /// 1. Unmapped device, already dominant → no-op.
    /// 2. Mapped device, dominant, AND the system's current input source is
    ///    already the mapped layout → no-op.
    ///
    /// Otherwise: for mapped devices, optimistically promote the device, ask
    /// the switcher to switch, and roll back the promotion if the switch fails
    /// (and only if dominance hasn't moved on again in the meantime). For
    /// unmapped devices, promote dominance silently (no switch, no spam) and
    /// emit one info log per transition.
    ///
    /// **Why we re-check the current source on every event:** observed in
    /// practice that `TISSelectInputSource` returns `noErr` but the system
    /// reverts to a per-device default before the next keystroke is processed.
    /// Without a per-event re-assert, the user's first event triggers a switch,
    /// the system reverts, and the dominant guard then suppresses every
    /// subsequent event from the same keyboard — every following keystroke
    /// types under the wrong layout. The TIS query is cheap and pays for
    /// itself the moment any external actor reapplies a layout.
    ///
    /// The `class=` field reports a coarse usage bucket (modifier / letter /
    /// digit / …) instead of the raw HID Usage ID — raw usage on the keyboard
    /// page is a scancode, and PRD §8 forbids logging keystroke content.
    func recordEvent(from device: KeyboardDevice, value: IOHIDValue) {
        dispatchPrecondition(condition: .onQueue(.main))

        let isDominanceChange = (device != dominant)
        let previous = dominant

        guard let layoutID = mapping.inputSource(for: device.deviceID) else {
            if isDominanceChange {
                dominant = device
                Log.info("unmapped device \(device.deviceID) — skip switch")
            }
            return
        }

        // Only mapped events count as "user is typing" for the connect heuristic.
        lastEventAt = Date()

        let currentID = InputSourceLister.currentInputSourceID()

        // Skip the switch only when nothing needs doing: same dominant AND the
        // system already has the mapped layout active. Either condition failing
        // → re-assert.
        if !isDominanceChange && currentID == layoutID {
            return
        }

        dominant = device

        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        let usageClass = HIDUsageClass.classify(page: page, usage: usage)

        let from = previous.map { " (from \($0.deviceID))" } ?? " (first event)"
        let drift: String
        if !isDominanceChange, let currentID, currentID != layoutID {
            drift = " [drift: was \(currentID)]"
        } else {
            drift = ""
        }

        Log.event("\(device.deviceID)\(from) -> switching to \(layoutID)\(drift) [page=\(page) class=\(usageClass.rawValue) value=\(intValue)]")

        InputSourceSwitcher.switchTo(layoutID) { [weak self] success in
            guard let self else { return }
            if !success {
                // Roll back the optimistic promotion only if no newer event has
                // moved dominance again. Without this guard a stale rollback
                // could overwrite a good subsequent dominance change.
                if self.dominant == device {
                    self.dominant = previous
                    Log.warn("switch to \(layoutID) failed — rolled back dominant to \(previous?.deviceID ?? "nil")")
                }
            }
        }
    }

    /// Called when a keyboard connects (matching callback).
    ///
    /// On a mapped keyboard with no active typing session, attempts a
    /// switch-on-connect. Promotes dominance ONLY on success — a failed
    /// switch leaves the tracker untouched, so the next `recordEvent` from
    /// this keyboard takes the normal optimistic-with-rollback path.
    func keyboardConnected(_ device: KeyboardDevice) {
        dispatchPrecondition(condition: .onQueue(.main))
        let name = Log.redactSerialLike(device.productName)
        let mfg = Log.redactSerialLike(device.manufacturer)
        Log.info("matched:      \(device.deviceID)  \"\(name)\" [\(mfg)] transport=\(device.transport)")

        guard let layoutID = mapping.inputSource(for: device.deviceID) else { return }

        let now = Date()
        let noActiveSession = lastEventAt.map { now.timeIntervalSince($0) > Self.activeSessionWindow } ?? true
        guard noActiveSession else { return }

        InputSourceSwitcher.switchTo(layoutID) { [weak self] success in
            guard let self, success else { return }
            self.dominant = device
            Log.info("switch-on-connect: \(device.deviceID) -> \(layoutID)")
        }
    }

    /// Called when a keyboard disconnects (removal callback).
    func keyboardDisconnected(_ device: KeyboardDevice) {
        dispatchPrecondition(condition: .onQueue(.main))
        let name = Log.redactSerialLike(device.productName)
        Log.info("disconnected: \(device.deviceID)  \"\(name)\"")
        if device == dominant {
            dominant = nil
            Log.info("dominant device disconnected — resetting")
        }
    }
}

/// Coarse class for an HID input value — used in EVENT logs in place of the
/// raw HID Usage ID, which on `kHIDPage_KeyboardOrKeypad` is a scancode.
enum HIDUsageClass: String {
    case modifier
    case letter
    case digit
    case control
    case function
    case arrow
    case other
    case nonKeyboard = "non-keyboard"

    static func classify(page: UInt32, usage: UInt32) -> HIDUsageClass {
        guard page == UInt32(kHIDPage_KeyboardOrKeypad) else { return .nonKeyboard }
        switch usage {
        case 0xE0...0xE7:                   return .modifier
        case 0x04...0x1D:                   return .letter
        case 0x1E...0x27:                   return .digit
        case 0x28, 0x29, 0x2A, 0x2B, 0x2C:  return .control   // Enter, Esc, Backspace, Tab, Space
        case 0x39, 0x3A...0x45, 0x68...0x73: return .function // Caps, F1-F12, F13-F24
        case 0x4F...0x52:                   return .arrow
        default:                            return .other
        }
    }
}
