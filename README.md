# Klef

> Per-keyboard automatic input source switching for macOS.

Klef is a macOS menu bar app that automatically switches your keyboard layout based on which physical keyboard you're typing on. Map each detected keyboard once — internal AZERTY, external QWERTY, Bluetooth French-PC — and Klef takes care of switching the layout when you change keyboards.

## Status

**V0.3 menu bar app.** Klef now runs as a native macOS menu bar app with a Settings window, per-keyboard input source mapping via dropdown, and UserDefaults persistence. No hardcoded mappings.

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

Swift 5.10+, SwiftUI for settings, AppKit `NSStatusItem` for the menu bar, `IOHIDManager` for keyboard detection, Carbon TIS for input source switching.

## Build & run (V0.3)

### Requirements

- macOS 13 (Ventura) or later
- Swift 5.10+ / Xcode 15+

### Build & launch

```bash
swift build && ./scripts/bundle-app.sh && open Klef.app
```

For a release build:

```bash
swift build -c release && ./scripts/bundle-app.sh && open Klef.app
```

Use `--force` to overwrite an existing bundle:

```bash
./scripts/bundle-app.sh --force
```

### App icon

`Resources/Klef.icns` is committed and copied into the bundle by `bundle-app.sh`. It is rasterised from `Resources/logo/klef-icon-brass.svg` — only re-run this after changing the artwork:

```bash
./scripts/make-icon.sh
```

### Input Monitoring permission

On first launch macOS will prompt for Input Monitoring access. If no prompt appears:

1. Open **System Settings → Privacy & Security → Input Monitoring**.
2. Add and enable `Klef`.
3. Relaunch `Klef.app`.

> **Note:** After each `swift build` + `bundle-app.sh`, the binary's code-sign hash changes. macOS may invalidate Input Monitoring permission and silently stop switching. If that happens, re-grant in System Settings → Privacy & Security → Input Monitoring.

### Mapping keyboards to input sources

1. Click the keyboard icon in the menu bar.
2. Select **Open Klef Settings…**.
3. For each detected keyboard, pick an input source from the dropdown.

Mappings are stored in `UserDefaults` under `klef.mappings.v1` and persist across relaunches. Keyboards you have seen before appear in a "Known, not connected" section even when unplugged.

### Running as a LaunchAgent (legacy V0.2 dogfood path)

The LaunchAgent scripts remain for reference but the preferred path is now the `.app` bundle above.

```bash
swift build -c release
./scripts/install-launch-agent.sh
```

View live logs: `tail -f ~/Library/Logs/klef-stdout.log`

Stop / remove: `./scripts/uninstall-launch-agent.sh`

### Known limitations (V0.3)

- **First-keystroke race remains.** A single character key-down as the very
  first input on a freshly-promoted keyboard can still race the switch
  (PRD §4 — measured improvement, not a fix).
- **Secure Input.** When `IsSecureEventInputEnabled()` is true (e.g. password
  fields, some Terminal contexts), the switch is attempted but may silently
  fail. Logged as a warning.
- **Two identical keyboards on the same Mac** are indistinguishable —
  `locationID`-based identity. PRD §7.
- **Builds are ad-hoc-signed only.** Developer ID signing and notarization are
  V1.0.
- **No first-launch onboarding.** The Settings window opens the Input Monitoring
  pane directly when permission is denied, but there is no welcome flow. V1.0.

## License

MIT.
