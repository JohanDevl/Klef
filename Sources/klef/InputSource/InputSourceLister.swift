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

    /// Returns the ID of the input source currently active system-wide, or
    /// `nil` if the Carbon call fails. Used by the engine to detect when an
    /// external actor has reverted a switch we issued — observed in practice
    /// on Sequoia/Tahoe where the keystroke that triggered our switch causes
    /// the kernel to reapply a per-device default *after* `TISSelectInputSource`
    /// returns `noErr`.
    static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// Looks up a TISInputSource by ID using `includeAllInstalled: true` so that
    /// disabled sources are included — required so the switcher can call
    /// TISEnableInputSource before selecting.
    ///
    /// `TISCreateInputSourceList(nil, true)` can return multiple instances
    /// sharing the same `kTISPropertyInputSourceID` (an enabled instance and a
    /// bundled-but-disabled instance). Prefer the enabled one; fall back to
    /// the first match so the switcher's `TISEnableInputSource` path still
    /// works for sources the user has not yet enabled.
    static func find(byID inputSourceID: String) -> TISInputSource? {
        guard
            let cfList = TISCreateInputSourceList(nil, true)?.takeRetainedValue(),
            let sources = cfList as? [TISInputSource]
        else { return nil }

        let matches = sources.filter { source in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            let id = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            return id == inputSourceID
        }

        return matches.first(where: isEnabled) ?? matches.first
    }

    private static func isEnabled(_ source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        return (Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue() as NSNumber).boolValue
    }
}
