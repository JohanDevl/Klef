import AppKit
import Foundation
import IOKit.hid

enum InputMonitoringStatus {
    case granted
    case denied
    case unknown
}

enum InputMonitoring {
    /// Honest read of current permission state. PRD FR-6: "honest read of current
    /// registration status (don't cache)."
    static func status() -> InputMonitoringStatus {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:  return .denied
        case kIOHIDAccessTypeUnknown: return .unknown
        default: return .unknown
        }
    }

    /// Print actionable instructions for the user when access isn't granted.
    /// V0.1 only — V1 will deeplink to System Settings (FR-6).
    static func printGuidance(for status: InputMonitoringStatus) {
        switch status {
        case .granted:
            return
        case .denied:
            Log.warn("Input Monitoring permission is DENIED.")
            Log.warn("Grant it in: System Settings → Privacy & Security → Input Monitoring, then re-launch klef.")
        case .unknown:
            Log.warn("Input Monitoring permission status is unknown — macOS will prompt on first HID access.")
            Log.warn("If no prompt appears, enable klef under System Settings → Privacy & Security → Input Monitoring.")
        }
    }

    /// Opens System Settings → Privacy & Security → Input Monitoring directly.
    ///
    /// Used by `SettingsView` when permission is denied so the user can
    /// recover without navigating the Settings tree manually.
    static func openSystemSettingsDeeplink() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
