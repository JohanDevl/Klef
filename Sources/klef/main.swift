import Foundation
import IOKit.hid

// Force line-buffered stdout so EVENT/INFO lines appear in real time when the
// process is piped or run as a background task (stdout would otherwise be
// block-buffered until exit).
setlinebuf(stdout)

// ─────────────────────────────────────────────────────────────────────────────
// Banner (user-facing CLI presentation — not routed through Log)
// ─────────────────────────────────────────────────────────────────────────────

print("klef v0.2 — per-keyboard input source switcher")
print("Press Ctrl-C to quit.\n")

// ─────────────────────────────────────────────────────────────────────────────
// Permission check
// ─────────────────────────────────────────────────────────────────────────────

let permStatus = InputMonitoring.status()
Log.info("Input Monitoring permission: \(permStatus)")
InputMonitoring.printGuidance(for: permStatus)

// ─────────────────────────────────────────────────────────────────────────────
// List enabled keyboard input sources
// ─────────────────────────────────────────────────────────────────────────────

let sources = InputSourceLister.enabledKeyboardSources()
if sources.isEmpty {
    Log.warn("No enabled keyboard input sources found.")
} else {
    print("Enabled keyboard input sources:")
    for source in sources {
        print("  \(source.localizedName)  (\(source.id))")
    }
    print()
}

// ─────────────────────────────────────────────────────────────────────────────
// Static mapping: DeviceID → InputSourceID
//
// V0.2 performs the real switch via InputSourceSwitcher on each dominance change.
// Run klef once to discover your keyboards' DeviceIDs from the "matched:" lines,
// then fill in entries here. Example:
//
//   "v<vendorID>-p<productID>-loc<locationID>": "com.apple.keylayout.French",
//   "v<vendorID>-p<productID>-loc<locationID>": "com.apple.keylayout.ABC"
//
// V0.3 will replace this with a UI + UserDefaults (FR-4).
// ─────────────────────────────────────────────────────────────────────────────

let staticMapping = StaticMapping(entries: [:])

// ─────────────────────────────────────────────────────────────────────────────
// Engine setup
// ─────────────────────────────────────────────────────────────────────────────

let tracker = DominantDeviceTracker(mapping: staticMapping)

// IMPORTANT: `hid` must stay alive for the entire CFRunLoopRun() lifetime.
// Callbacks are bridged via Unmanaged.passUnretained — deallocation would crash.
let hid = HIDKeyboardManager()

hid.onMatched = { device in
    tracker.keyboardConnected(device)
}
hid.onRemoved = { device in
    tracker.keyboardDisconnected(device)
}
hid.onEvent = { device, value in
    tracker.recordEvent(from: device, value: value)
}

guard hid.start() else {
    Log.error("Failed to open HID manager. Check Input Monitoring permission and re-launch.")
    exit(EXIT_FAILURE)
}

Log.info("HID manager started — listening for keyboard events.")

// ─────────────────────────────────────────────────────────────────────────────
// Signal handling — clean shutdown on SIGINT / SIGTERM
// ─────────────────────────────────────────────────────────────────────────────

// Disarm the default C-level handlers BEFORE arming the GCD sources. Signals
// arriving in the gap are coalesced by the kernel and delivered when the
// dispatch source resumes — no signal is lost. Reordering this would break.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

func makeShutdownSource(for sig: Int32) -> DispatchSourceSignal {
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        print("\nShutdown requested.")
        CFRunLoopStop(CFRunLoopGetMain())
    }
    src.resume()
    return src
}

let sigintSource  = makeShutdownSource(for: SIGINT)
let sigtermSource = makeShutdownSource(for: SIGTERM)

// Keep signal sources alive for the run-loop lifetime.
_ = sigintSource
_ = sigtermSource

// ─────────────────────────────────────────────────────────────────────────────
// Run
// ─────────────────────────────────────────────────────────────────────────────

CFRunLoopRun()

// `exit()` does not run Swift deinitializers — explicitly tear down the HID
// manager before the process exits so callbacks are unregistered cleanly.
hid.stop()

print("klef stopped.")
exit(EXIT_SUCCESS)
