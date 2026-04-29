import Foundation
import Carbon.HIToolbox
import os.signpost

/// Performs the Carbon TIS input source switch.
///
/// The only site in the codebase that calls `TISEnableInputSource` and
/// `TISSelectInputSource`. Concrete enum — no protocol (YAGNI: one implementation).
///
/// Memory rules: `TISEnableInputSource` and `TISSelectInputSource` take a
/// `TISInputSource` obtained from `InputSourceLister.find(byID:)` (Get rule);
/// no `Unmanaged` dance is needed here. Both calls return an `OSStatus`.
///
/// Threading: the body is dispatched to `DispatchQueue.main.async` (FR-3) and
/// the completion fires on main as well — callers can mutate state from the
/// completion without locks.
enum InputSourceSwitcher {

    private static let signpostLog = OSLog(subsystem: "com.klef.engine", category: "tis-switch")

    /// Switches the active input source to the given ID. Fire-and-forget by
    /// default; pass `completion` to learn whether the switch actually landed.
    ///
    /// Always dispatched to the main thread explicitly — insurance for the V1
    /// HID RunLoop migration (PRD §7) where callers may be on a non-main thread.
    /// The completion is invoked on the main thread.
    static func switchTo(_ inputSourceID: String, completion: @escaping (Bool) -> Void = { _ in }) {
        DispatchQueue.main.async {
            let success = performSwitch(inputSourceID)
            completion(success)
        }
    }

    /// Synchronous body of the switch, intended to run on the main thread.
    /// Returns `true` only if `TISSelectInputSource` returned `noErr`.
    private static func performSwitch(_ inputSourceID: String) -> Bool {
        if IsSecureEventInputEnabled() {
            Log.warn("Secure Input is active — TIS switch may silently fail (best-effort)")
        }

        guard let source = InputSourceLister.find(byID: inputSourceID) else {
            Log.error("input source not found: \(inputSourceID)")
            return false
        }

        os_signpost(.begin, log: signpostLog, name: "switch", "id=%{public}s", inputSourceID)
        defer { os_signpost(.end, log: signpostLog, name: "switch") }

        let enableStatus = TISEnableInputSource(source)
        if enableStatus != noErr {
            // Bail: kawa and ohueter/autokbisw both treat enable failure as terminal.
            // Selecting a still-disabled source is a no-op or undefined.
            Log.error("TISEnableInputSource failed: OSStatus=\(enableStatus) — aborting switch to \(inputSourceID)")
            return false
        }

        let selectStatus = TISSelectInputSource(source)
        if selectStatus != noErr {
            Log.error("TISSelectInputSource failed: OSStatus=\(selectStatus)")
            return false
        }

        Log.info("switched to \(inputSourceID)")
        return true
    }
}
