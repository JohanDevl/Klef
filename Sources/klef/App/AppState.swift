import Foundation

/// Single source of truth for the UI and the bridge between the HID layer and
/// SwiftUI views.
///
/// All `@Published` mutations MUST occur on the main thread. Callers (i.e.
/// `AppDelegate`) bridge HID callbacks — which fire on the main RunLoop today
/// (`HIDKeyboardManager` schedules on `CFRunLoopGetMain()`) — via
/// `DispatchQueue.main.async { state.keyboardConnected(device) }`. That async
/// bounce costs nothing today and protects against the V1.0 dedicated-RunLoop
/// migration (PRD §7) without any callers needing to change.
///
/// Not annotated `@MainActor`: the engine layer (`DominantDeviceTracker`,
/// `UserDefaultsMapping`) is non-isolated, and forcing `@MainActor` here would
/// require annotating every callsite up the chain. `dispatchPrecondition` on
/// each mutator carries the same load-bearing assertion at runtime.
final class AppState: ObservableObject {

    enum UpdateInstallState: Equatable {
        case idle
        case working(UpdateInstaller.Phase)
        case failed(String)
        /// The new version is on disk but could not be started; this process
        /// is still the old one.
        case restartRequired(AppVersion)

        /// A second install on top of one that is running, or one that is
        /// already on disk waiting for a restart, has nothing left to do.
        var allowsNewInstall: Bool {
            switch self {
            case .idle, .failed: return true
            case .working, .restartRequired: return false
            }
        }
    }

    // MARK: - Published state

    /// Device IDs currently physically connected.
    @Published private(set) var connectedDeviceIDs: Set<String> = []

    /// Union of connected and known-but-disconnected keyboards, keyed by
    /// `deviceID`. Mirrors UserDefaults via `MappingsStore`.
    @Published private(set) var devices: [String: DeviceMappingEntry] = [:]

    /// All enabled TIS keyboard input sources; refreshed on demand.
    @Published private(set) var availableInputSources: [InputSourceInfo] = []

    /// Current Input Monitoring permission status; refreshed on demand.
    @Published private(set) var permissionStatus: InputMonitoringStatus = .unknown

    /// Whether the HID manager is currently observing keyboard events. Flips
    /// to `false` when `IOHIDManagerOpen` fails (typically permission denied);
    /// the UI can surface a Retry button to call back into `AppDelegate`.
    @Published private(set) var hidIsRunning: Bool = false

    /// A published release newer than the running build, or `nil` when up to
    /// date or not yet checked.
    @Published private(set) var availableUpdate: AvailableUpdate?

    /// True while a check is in flight, so the UI can disable the command
    /// rather than let the user queue several requests at a rate-limited API.
    @Published private(set) var isCheckingForUpdate: Bool = false

    /// Outcome of the most recent *explicit* check, for display in Settings.
    /// Automatic launch checks leave this alone: a failed background check is
    /// not something to interrupt anyone about.
    @Published private(set) var updateCheckMessage: String?

    /// Where an in-app update install stands. `.failed` stays put until the
    /// next attempt so Settings can keep showing what went wrong.
    /// `AppDelegate` also reads it to hold off Quit during the swap.
    @Published private(set) var updateInstallState: UpdateInstallState = .idle

    // MARK: - Wiring (set by AppDelegate after init)

    /// Closure the UI calls to ask the app to (re-)start HID monitoring after
    /// the user has granted Input Monitoring permission. Set by `AppDelegate`
    /// in `applicationDidFinishLaunching`; remains `nil` in tests.
    var onRequestHIDStart: (() -> Void)?

    // MARK: - Private state

    private let store: MappingsStore

    // MARK: - Init

    init(store: MappingsStore) {
        self.store = store
        self.devices = store.load()
        self.availableInputSources = InputSourceLister.enabledKeyboardSources()
        self.permissionStatus = InputMonitoring.status()
    }

    // MARK: - HID-event mutators

    /// Called when a keyboard is detected (plug-in or already present at launch).
    func keyboardConnected(_ device: KeyboardDevice) {
        dispatchPrecondition(condition: .onQueue(.main))
        let id = device.deviceID
        connectedDeviceIDs.insert(id)

        if var existing = devices[id] {
            // Refresh snapshot fields; user-set fields are preserved.
            existing.lastSeenProductName = device.productName
            existing.lastSeenTransport = device.transport
            existing.lastSeenAt = Date()
            devices[id] = existing
        } else {
            devices[id] = DeviceMappingEntry(
                deviceID: id,
                inputSourceID: nil,
                ignored: false,
                displayName: nil,
                lastSeenProductName: device.productName,
                lastSeenTransport: device.transport,
                lastSeenAt: Date()
            )
        }
        persist()
    }

    /// Called when a keyboard is unplugged.
    func keyboardDisconnected(_ device: KeyboardDevice) {
        dispatchPrecondition(condition: .onQueue(.main))
        // Keep the entry in `devices` so the "Known but not connected" section
        // survives across sessions (PRD FR-2).
        connectedDeviceIDs.remove(device.deviceID)
    }

    // MARK: - Settings mutators

    /// Assigns (or clears) the TIS input-source ID for a keyboard.
    func setInputSource(deviceID: String, inputSourceID: String?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var existing = devices[deviceID] else { return }
        existing.inputSourceID = inputSourceID
        devices[deviceID] = existing
        persist()
    }

    /// Enables or disables the "don't switch" flag for a keyboard.
    func setIgnored(deviceID: String, ignored: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var existing = devices[deviceID] else { return }
        existing.ignored = ignored
        devices[deviceID] = existing
        persist()
    }

    // MARK: - Refresh helpers

    /// Re-queries TIS for the current set of enabled keyboard input sources.
    func refreshInputSources() {
        dispatchPrecondition(condition: .onQueue(.main))
        availableInputSources = InputSourceLister.enabledKeyboardSources()
    }

    /// Re-checks the Input Monitoring permission state.
    func refreshPermission() {
        dispatchPrecondition(condition: .onQueue(.main))
        permissionStatus = InputMonitoring.status()
    }

    /// Sets the HID-running flag. Called by `AppDelegate` after every
    /// `hid.start()` / `hid.stop()` so the UI reflects whether monitoring is
    /// actually live.
    func setHIDIsRunning(_ running: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        hidIsRunning = running
    }

    // MARK: - Update checks

    /// Asks GitHub whether a newer release exists.
    ///
    /// - Parameter explicit: `true` when the user asked (menu / Settings
    ///   button), which surfaces the outcome — including "you're up to date"
    ///   and failures — via `updateCheckMessage`. `false` is the silent launch
    ///   check, which only ever populates `availableUpdate`.
    func checkForUpdates(explicit: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        // An install owns `availableUpdate` while it runs; a check landing in
        // the middle would pull the banner, and its progress row, out from
        // under it.
        guard !isCheckingForUpdate, !isInstallingUpdate else { return }

        if explicit {
            isCheckingForUpdate = true
            updateCheckMessage = nil
        }

        let handler: (Result<AvailableUpdate?, Error>) -> Void = { [weak self] result in
            guard let self else { return }
            self.isCheckingForUpdate = false
            switch result {
            case .success(let update):
                self.availableUpdate = update
                if explicit {
                    self.updateCheckMessage = update.map { "Klef \($0.version) is available." }
                        ?? "Klef is up to date."
                }
            case .failure(let error):
                Log.warn("update check failed: \(error.localizedDescription)")
                if explicit {
                    self.updateCheckMessage = error.localizedDescription
                }
            }
        }

        if explicit {
            UpdateChecker.check(completion: handler)
        } else {
            UpdateChecker.checkIfDue(completion: handler)
        }
    }

    // MARK: - Update install

    var isInstallingUpdate: Bool {
        if case .working = updateInstallState { return true }
        return false
    }

    /// True once the download is in hand and files beside the app are being
    /// worked on. Quitting then could strand a half-staged bundle, so
    /// `AppDelegate` refuses to terminate until it is over. The download
    /// itself is excluded: abandoning it harms nothing, and it can take a
    /// while on a bad connection.
    var isReplacingApp: Bool {
        switch updateInstallState {
        case .working(.verifying), .working(.installing): return true
        default: return false
        }
    }

    /// Downloads and installs the update the user just confirmed, then
    /// relaunches into it.
    ///
    /// Only ever called from an explicit click. On success this does not
    /// return to its caller in any useful sense: Klef quits and reopens.
    func installUpdate() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let confirmed = availableUpdate, updateInstallState.allowsNewInstall else { return }

        updateInstallState = .working(.downloading)

        // Klef only checks at launch and can then sit in the menu bar for
        // weeks, so what `availableUpdate` describes may be stale: the image
        // re-uploaded (new checksum) or a newer release out. Ask again, and
        // only go ahead with exactly the version the user said yes to.
        UpdateChecker.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.failInstall(error.localizedDescription)

            case .success(nil):
                // The release was withdrawn since the banner appeared.
                self.availableUpdate = nil
                self.updateInstallState = .idle
                self.updateCheckMessage = "Klef is up to date."

            case .success(let fresh?):
                self.availableUpdate = fresh
                guard fresh.version == confirmed.version else {
                    self.failInstall(
                        "Klef \(fresh.version) has been published since. Review it, then click Install Update again."
                    )
                    return
                }
                self.download(fresh)
            }
        }
    }

    private func download(_ update: AvailableUpdate) {
        UpdateInstaller.install(
            update,
            onPhase: { [weak self] phase in
                self?.updateInstallState = .working(phase)
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    // Leaves `.working` first, or `AppDelegate` would refuse
                    // the very termination the relaunch ends with.
                    self.updateInstallState = .idle
                    UpdateInstaller.relaunch(afterInstalling: update.version) { [weak self] _ in
                        self?.updateInstallState = .restartRequired(update.version)
                    }
                case .failure(let error):
                    self.failInstall(error.localizedDescription)
                }
            }
        )
    }

    private func failInstall(_ reason: String) {
        Log.warn("update install failed: \(reason)")
        updateInstallState = .failed(reason)
    }

    /// Turns the automatic daily check on or off. Clears any pending banner on
    /// the way out so disabling the feature also removes its UI.
    func setUpdateChecksEnabled(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isInstallingUpdate else { return }
        UpdateChecker.isEnabled = enabled
        if !enabled {
            availableUpdate = nil
            updateCheckMessage = nil
        }
    }

    // MARK: - Computed helpers

    /// Devices partitioned by connectivity and sorted within each bucket. The
    /// view computes both lists on every render; the partition is materialised
    /// here so `SettingsView`'s body doesn't traverse `devices` twice.
    var partitionedDevices: (connected: [DeviceMappingEntry], disconnected: [DeviceMappingEntry]) {
        var connected: [DeviceMappingEntry] = []
        var disconnected: [DeviceMappingEntry] = []
        for entry in devices.values {
            if connectedDeviceIDs.contains(entry.deviceID) {
                connected.append(entry)
            } else {
                disconnected.append(entry)
            }
        }
        let byLabel: (DeviceMappingEntry, DeviceMappingEntry) -> Bool = {
            $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending
        }
        connected.sort(by: byLabel)
        disconnected.sort(by: byLabel)
        return (connected, disconnected)
    }

    // MARK: - Private helpers

    private func persist() {
        store.save(devices)
    }
}
