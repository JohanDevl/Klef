import IOKit.hid

/// Tracks which keyboard is currently dominant and emits a single `EVENT` log
/// line each time dominance changes.
///
/// V0.1 is read-only: we log "would switch to <layoutID>" but never call TIS.
/// Actual switching lands in V0.2 (FR-3).
final class DominantDeviceTracker {

    // MARK: - State

    private(set) var dominant: KeyboardDevice?
    private let mapping: DeviceLayoutMapping

    // MARK: - Init

    init(mapping: DeviceLayoutMapping) {
        self.mapping = mapping
    }

    // MARK: - Observation

    /// Called on every HID input value.
    ///
    /// Short-circuits if the device is already dominant. On dominance change,
    /// promotes the device and emits exactly one EVENT line. The `class=`
    /// field reports a coarse usage bucket (modifier / letter / digit / …)
    /// instead of the raw HID Usage ID — raw usage on the keyboard page is a
    /// scancode, and PRD §8 forbids logging keystroke content. The bucketed
    /// form is enough to answer PRD Q1 (do modifier-only events arrive
    /// before the first character key-down?) without being a keylog.
    func recordEvent(from device: KeyboardDevice, value: IOHIDValue) {
        guard device != dominant else { return }

        let previous = dominant
        dominant = device

        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        let usageClass = HIDUsageClass.classify(page: page, usage: usage)

        let target = mapping.inputSource(for: device.deviceID)
            ?? "<unmapped — add \"\(device.deviceID)\" to StaticMapping>"

        let from = previous.map { " (from \($0.deviceID))" } ?? " (first event)"
        Log.event(
            "\(device.deviceID)\(from) -> would switch to \(target) "
            + "[page=\(page) class=\(usageClass.rawValue) value=\(intValue)]"
        )
    }

    /// Called when a keyboard connects (matching callback).
    func keyboardConnected(_ device: KeyboardDevice) {
        let name = Log.redactSerialLike(device.productName)
        let mfg = Log.redactSerialLike(device.manufacturer)
        Log.info("matched:      \(device.deviceID)  \"\(name)\" [\(mfg)] transport=\(device.transport)")
    }

    /// Called when a keyboard disconnects (removal callback).
    func keyboardDisconnected(_ device: KeyboardDevice) {
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
