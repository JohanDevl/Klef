import AppKit
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+) used to register
/// Klef as a login item.
///
/// The system is the single source of truth — no UserDefaults caching — since
/// the user can also toggle this in System Settings → General → Login Items
/// independently of the app.
enum LaunchAtLogin {

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Opens System Settings → General → Login Items. Mirrors the
    /// `InputMonitoring.openSystemSettingsDeeplink()` pattern used elsewhere
    /// for permission deeplinks.
    static func openSystemSettingsDeeplink() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
