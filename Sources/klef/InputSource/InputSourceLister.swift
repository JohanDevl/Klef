import Carbon.HIToolbox

/// Read-only summary of a TIS input source.
struct InputSourceInfo: Hashable, CustomStringConvertible {
    let id: String              // kTISPropertyInputSourceID, e.g. "com.apple.keylayout.French"
    let localizedName: String   // kTISPropertyLocalizedName, e.g. "French"
    let isEnabled: Bool

    var description: String { "\(localizedName) (\(id))\(isEnabled ? "" : " [disabled]")" }
}

/// Read-only Carbon TIS façade.
///
/// V0.1: listing only. No `TISSelectInputSource` calls — switching is V0.2 (FR-3).
///
/// Memory rules:
/// - `TISCreateInputSourceList` → Create rule → `.takeRetainedValue()`
/// - `TISGetInputSourceProperty` → Get rule → `Unmanaged.fromOpaque(...).takeUnretainedValue()`
enum InputSourceLister {
    /// Returns all currently enabled keyboard input sources.
    static func enabledKeyboardSources() -> [InputSourceInfo] {
        guard
            let cfList = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
            let sources = cfList as? [TISInputSource]
        else {
            Log.warn("TISCreateInputSourceList returned nil or unexpected type")
            return []
        }

        return sources.compactMap { source -> InputSourceInfo? in
            func strProp(_ key: CFString) -> String? {
                guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
                return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            }
            func boolProp(_ key: CFString) -> Bool {
                guard let raw = TISGetInputSourceProperty(source, key) else { return false }
                return (Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue() as NSNumber).boolValue
            }

            guard
                let sourceID = strProp(kTISPropertyInputSourceID),
                boolProp(kTISPropertyInputSourceIsEnabled)
            else { return nil }

            let name = strProp(kTISPropertyLocalizedName) ?? sourceID

            return InputSourceInfo(
                id: sourceID,
                localizedName: name,
                isEnabled: true
            )
        }
    }
}
