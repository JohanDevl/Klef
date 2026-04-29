import AppKit
import SwiftUI

/// Owns the lazy Settings `NSWindow`.
///
/// - `show()` brings an existing window to the front or creates a new one.
/// - The window hosts `SettingsView` via `NSHostingController`.
/// - Activation policy is flipped to `.regular` on open and back to
///   `.accessory` on close so the window can receive keyboard focus.
/// - `isReleasedWhenClosed = false` keeps the window alive across close/reopen
///   cycles; the strong reference is dropped only when `NSWindow.willCloseNotification`
///   fires, which triggers the policy revert.
/// - Whenever the window becomes key (open or returns to focus), `AppState`'s
///   permission and input-source caches are refreshed and a stalled HID
///   manager is re-armed if permission has just been granted.
final class SettingsWindowController {

    // MARK: - Private state

    private let appState: AppState
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?

    // MARK: - Init

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public API

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        refreshAndMaybeRetry()

        let hostingController = NSHostingController(
            rootView: SettingsView().environmentObject(appState)
        )

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Klef Settings"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("KlefSettings")
        win.center()

        // Refresh state every time the window comes back to focus — handles
        // "user went to System Settings, granted permission, switched back".
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAndMaybeRetry()
        }

        // Observe close to revert activation policy and drop strong references.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.window = nil
            self?.removeObservers()
        }

        window = win

        // Temporarily become a regular app so the window can take focus.
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private helpers

    /// Refreshes permission + input-source state and asks `AppDelegate` to
    /// retry `hid.start()` if permission has now been granted but the manager
    /// is still dormant. Cheap to call repeatedly — refresh helpers are O(N)
    /// over the system input-source list.
    private func refreshAndMaybeRetry() {
        appState.refreshPermission()
        appState.refreshInputSources()
        if appState.permissionStatus == .granted, !appState.hidIsRunning {
            appState.onRequestHIDStart?()
        }
    }

    private func removeObservers() {
        if let obs = closeObserver {
            NotificationCenter.default.removeObserver(obs)
            closeObserver = nil
        }
        if let obs = keyObserver {
            NotificationCenter.default.removeObserver(obs)
            keyObserver = nil
        }
    }
}
