# Klef

> Per-keyboard automatic input source switching for macOS.

Klef is a macOS menu bar app that automatically switches your keyboard layout based on which physical keyboard you're typing on. Map each detected keyboard once — internal AZERTY, external QWERTY, Bluetooth French-PC — and Klef takes care of switching the layout when you change keyboards.

## Status

**V0.2 engine.** Klef is still a CLI binary, but it now actually switches the macOS input source when you change keyboards (V0.1 only logged what it would have done). Mappings remain hardcoded in `main.swift` — the menu bar UI lands in V0.3.

## Why

macOS has no native per-device input source switching. The built-in "Automatically switch to a document's input source" works per-app, not per-keyboard. The only existing CLI tool ([autokbisw](https://github.com/ohueter/autokbisw)) has no GUI and known device-classification bugs. Klef closes that gap.

## Goals

- Detect every connected keyboard (built-in, USB, Bluetooth) and surface them in a menu bar UI.
- Map each keyboard to one input source from the system's enabled list.
- Switch the active input source automatically on keyboard change, with the lowest practical latency.
- Polished onboarding for the required Input Monitoring permission.
- Signed and notarized DMG, macOS 13 (Ventura) and later.

## Non-goals

- Per-app or per-website switching (use [Input Source Pro](https://inputsource.pro/) for that).
- Key remapping or modifier customization (use Karabiner-Elements).
- CJKV input methods.
- Mac App Store distribution (sandbox blocks IOHIDManager).

## Tech

Swift 5.10+, SwiftUI for settings, AppKit `NSStatusItem` for the menu bar, `IOHIDManager` for keyboard detection, Carbon TIS for input source switching, `SMAppService` for launch at login.

## Building (V0.2)

### Requirements

- macOS 13 (Ventura) or later
- Swift 5.10+ / Xcode 15+

### Build & run

```bash
swift build
./.build/debug/klef
```

### Input Monitoring permission

On first launch macOS will either prompt for Input Monitoring access or `klef`
will exit with guidance. If no prompt appears:

1. Open **System Settings → Privacy & Security → Input Monitoring**.
2. Enable the terminal application you are running `klef` from.
3. Re-launch `klef`.

### Mapping keyboards to input sources

On startup `klef` prints a `matched:` line for each connected keyboard, including
its stable `DeviceID` (e.g. `v1452-p641-loc337641472`). To configure switching,
open `Sources/klef/main.swift` and fill in the `staticMapping` dictionary:

```swift
let staticMapping = StaticMapping(entries: [
    "v1452-p641-loc337641472":  "com.apple.keylayout.French",
    "v1133-p49970-loc336592896": "com.apple.keylayout.ABC",
])
```

Rebuild and relaunch. The enabled source IDs are printed at startup under
"Enabled keyboard input sources".

### Running as a LaunchAgent (dogfooding)

```bash
swift build -c release
./scripts/install-launch-agent.sh
```

View live logs: `tail -f ~/Library/Logs/klef-stdout.log`

Stop / remove: `./scripts/uninstall-launch-agent.sh`

> **Caveat:** After each `swift build`, the binary's code-sign hash changes. macOS may invalidate Input Monitoring permission and silently stop switching. If that happens, re-grant in System Settings → Privacy & Security → Input Monitoring.

### Known limitations (V0.2)

- **First-keystroke race remains.** A single character key-down as the very
  first input on a freshly-promoted keyboard can still race the switch
  (PRD §4 — measured improvement, not a fix).
- **Secure Input.** When `IsSecureEventInputEnabled()` is true (e.g. password
  fields, some Terminal contexts), the switch is attempted but may silently
  fail. Logged as a warning.
- **No GUI yet.** Mappings are still hardcoded in `main.swift`. V0.3 brings
  the menu bar app.
- **Two identical keyboards on the same Mac** are indistinguishable —
  `locationID`-based identity. PRD §7.

## License

MIT.
