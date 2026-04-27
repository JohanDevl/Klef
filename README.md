# Klef

> Per-keyboard automatic input source switching for macOS.

Klef is a macOS menu bar app that automatically switches your keyboard layout based on which physical keyboard you're typing on. Map each detected keyboard once — internal AZERTY, external QWERTY, Bluetooth French-PC — and Klef takes care of switching the layout when you change keyboards.

## Status

Early development. No release yet.

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

## License

MIT.
