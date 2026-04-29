import Foundation

/// `DeviceLayoutMapping` conformer that reads live from `AppState`.
///
/// Holds a `weak` reference to `AppState` to break the retain cycle:
///   AppDelegate → AppState (strong)
///   AppDelegate → DominantDeviceTracker → UserDefaultsMapping → AppState (weak)
///
/// If `appState` has been deallocated the mapping returns `nil`, which causes
/// the engine to skip the switch — a safe default.
final class UserDefaultsMapping: DeviceLayoutMapping {

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Returns the TIS input-source ID for `deviceID`, or `nil` if:
    /// - the device is marked "ignored", or
    /// - no input source has been assigned yet, or
    /// - `appState` has been deallocated.
    ///
    /// Reading `@Published var devices` requires the main thread. The engine
    /// calls into this from HID callbacks scheduled on `CFRunLoopGetMain()`,
    /// so the precondition holds today; it will fire loudly if the V1.0
    /// dedicated-RunLoop migration (PRD §7) moves callbacks off-main without
    /// updating the call path.
    func inputSource(for deviceID: String) -> String? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let state = appState else { return nil }
        guard let entry = state.devices[deviceID] else { return nil }
        guard !entry.ignored else { return nil }
        return entry.inputSourceID
    }
}
