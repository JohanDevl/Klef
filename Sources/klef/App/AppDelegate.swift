import AppKit

/// App entry point.
///
/// Activation policy is `.accessory` (no Dock icon) because `LSUIElement = true`
/// in `Info.plist`. `SettingsWindowController` temporarily flips to `.regular`
/// while the Settings window is open so it can receive keyboard focus.
///
/// `CFRunLoopRun()` and SIGINT/SIGTERM handlers are gone — `NSApp.run()` (which
/// `NSApplicationMain` starts) manages the run loop, and macOS routes Cmd-Q to
/// `applicationShouldTerminate:` automatically.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Entry point
    //
    // Swift's `@main` synthesizes an entry point for an `NSApplicationDelegate`
    // that does NOT wire `NSApp.delegate`. Without a main NIB (we ship none —
    // `NSPrincipalClass = NSApplication` and no NIB key in `Info.plist`), the
    // synthesized path runs `NSApplicationMain` with no delegate, so
    // `applicationDidFinishLaunching` never fires and the status item is never
    // created. We provide an explicit `main()` that constructs the delegate
    // ourselves, then enters the AppKit run loop.
    static func main() {
        // Force line-buffered stdout so `Log.info`/`event` lines appear in
        // real time when redirected to a file (stdout would otherwise be
        // block-buffered until the process exits).
        setlinebuf(stdout)

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - Owned objects (live for the app lifetime)
    //
    // Implicitly-unwrapped optionals because every dependency is wired in
    // `applicationDidFinishLaunching` and never accessed before. AppKit
    // instantiates the delegate before the bundle's run loop is up, so a
    // designated initialiser couldn't usefully build them earlier.

    private var store: MappingsStore!
    private var appState: AppState!
    private var mapping: UserDefaultsMapping!
    private var tracker: DominantDeviceTracker!
    private var hid: HIDKeyboardManager!
    private var settingsWindowController: SettingsWindowController!
    private var statusItemController: StatusItemController!

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Persistence + state
        store = MappingsStore()
        appState = AppState(store: store)

        // Log version + permission guidance (reuses V0.2 logic)
        Log.info("Klef v0.3")
        InputMonitoring.printGuidance(for: appState.permissionStatus)

        // Engine
        mapping = UserDefaultsMapping(appState: appState)
        tracker = DominantDeviceTracker(mapping: mapping)
        hid = HIDKeyboardManager()

        // Wire HID callbacks.
        //
        // onMatched / onRemoved: bounce through DispatchQueue.main.async even
        // though HIDKeyboardManager already schedules on CFRunLoopGetMain().
        // The async bounce is insurance for the V1.0 dedicated-RunLoop migration
        // (PRD §7): if HID callbacks move off-main, no callers need to change.
        //
        // onEvent: forwarded directly — hot path, every keystroke.
        hid.onMatched = { [weak self] device in
            DispatchQueue.main.async {
                guard let self else { return }
                self.appState.keyboardConnected(device)
                self.tracker.keyboardConnected(device)
            }
        }
        hid.onRemoved = { [weak self] device in
            DispatchQueue.main.async {
                guard let self else { return }
                self.appState.keyboardDisconnected(device)
                self.tracker.keyboardDisconnected(device)
            }
        }
        hid.onEvent = { [weak self] device, value in
            self?.tracker.recordEvent(from: device, value: value)
        }

        // Allow the Settings window to ask us to (re-)start HID after the user
        // grants Input Monitoring permission. Without this hook, granting
        // permission after a failed launch would require restarting Klef.
        appState.onRequestHIDStart = { [weak self] in
            self?.attemptHIDStart()
        }

        // First start attempt. Failure (typically permission denied) is not
        // fatal: the menu bar and Settings UI are still useful so the user
        // can navigate to System Settings and re-arm via the Settings window.
        attemptHIDStart()

        // UI
        settingsWindowController = SettingsWindowController(appState: appState)
        statusItemController = StatusItemController(
            appState: appState,
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.show()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if appState.hidIsRunning {
            hid.stop()
            appState.setHIDIsRunning(false)
        }
    }

    // MARK: - HID lifecycle

    /// Attempts to open the HID manager and reflects the result in `AppState`.
    /// Idempotent: if the manager is already running, a no-op `start()` returns
    /// `true` and the published flag stays consistent.
    private func attemptHIDStart() {
        dispatchPrecondition(condition: .onQueue(.main))
        if hid.start() {
            appState.setHIDIsRunning(true)
            Log.info("HID manager started.")
        } else {
            appState.setHIDIsRunning(false)
            Log.error("HID manager failed to start — check Input Monitoring permission.")
        }
        appState.refreshPermission()
    }
}
