<p align="center">
  <img src="Resources/logo/klef-icon.png" alt="Klef" width="160" height="160">
</p>

<h1 align="center">Klef</h1>

<p align="center">
  <strong>Per-keyboard automatic input source switching for macOS.</strong>
</p>

<p align="center">
  <a href="https://github.com/JohanDevl/Klef/actions/workflows/ci.yml"><img src="https://github.com/JohanDevl/Klef/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/JohanDevl/Klef/releases/latest"><img src="https://img.shields.io/github/v/release/JohanDevl/Klef?sort=semver" alt="Latest release"></a>
  <a href="https://github.com/JohanDevl/Klef/releases"><img src="https://img.shields.io/github/downloads/JohanDevl/Klef/total" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.10+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/JohanDevl/Klef" alt="MIT License"></a>
</p>

---

Klef is a macOS menu bar app that automatically switches your keyboard layout
based on which physical keyboard you're typing on. Map each detected keyboard
once — internal AZERTY, external QWERTY, Bluetooth French-PC — and Klef takes
care of switching the layout when you change keyboards.

macOS has no native per-device input source switching. The built-in
"Automatically switch to a document's input source" works per-app, not
per-keyboard. The only existing CLI tool
([autokbisw](https://github.com/ohueter/autokbisw)) has no GUI and known
device-classification bugs. Klef closes that gap.

> **Status: V0.3.** Fully functional menu bar app. Builds are **not yet signed
> with a Developer ID or notarized** — see [Installing](#installing) for the
> extra step macOS requires on first launch.

## Installing

Download the latest `Klef-x.y.z.dmg` from the
[releases page](https://github.com/JohanDevl/Klef/releases/latest), open it, and
drag **Klef** to Applications.

### First launch

Because the build is ad-hoc signed rather than notarized, macOS will refuse to
open it the first time with a message about being unable to verify the
developer. To approve it:

1. Try to open **Klef** once and dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the Security section — there is now an **Open Anyway** button for
   Klef. Click it and confirm.

Only needed once. On macOS 15 (Sequoia) and later, the old Control-click → Open
shortcut [no longer bypasses Gatekeeper](https://appleinsider.com/articles/24/08/06/apple-removes-control-click-option-for-skipping-gatekeeper-in-macos-sequoia);
System Settings is the only route.

You can verify your download against the `.sha256` file published alongside each
release:

```bash
shasum -a 256 -c Klef-0.3.0.dmg.sha256
```

### Input Monitoring permission

Klef needs Input Monitoring access to know which keyboard an event came from.
macOS should prompt on first launch. If no prompt appears:

1. Open **System Settings → Privacy & Security → Input Monitoring**.
2. Add and enable **Klef**.
3. Relaunch Klef.

## Privacy

Klef requests Input Monitoring, the same permission a keylogger would need, so
here is exactly what it does with it — every claim below is checkable against
the source.

- **Keystroke content is never read.** For each HID event Klef reads only the
  usage page and usage code to classify the key into a coarse bucket
  (`letter`, `digit`, `modifier`, `arrow`, …) — see
  [`HIDUsageClass.classify`](Sources/klef/Engine/DominantDeviceTracker.swift).
  The specific key is never stored, logged, or acted on. What actually drives a
  switch is *which device* the event came from, not what was typed.
- **Klef never seizes the input stream.** `IOHIDManager` is opened with
  `kIOHIDOptionsTypeNone` (shared monitoring), not exclusive capture — see
  [`HIDKeyboardManager`](Sources/klef/HID/HIDKeyboardManager.swift).
- **Exactly one outbound request, and you can switch it off.** No telemetry, no
  analytics, no crash reporting. The only network call Klef ever makes is an
  unauthenticated `GET` to
  `api.github.com/repos/JohanDevl/Klef/releases/latest`, at most once a day, to
  see whether a newer release exists — see
  [`UpdateChecker`](Sources/klef/Updates/UpdateChecker.swift). It sends no
  request body and no identifiers beyond the IP address and `User-Agent` that
  any HTTP client sends. Turn it off in Settings and Klef makes no network
  requests at all.
- **Nothing is downloaded or installed automatically.** The update check only
  ever shows a menu item linking to the release page. Klef never writes outside
  its own preferences.
- **No third-party dependencies.** Beyond the system Swift/AppKit stack the only
  frameworks linked are `IOKit` and `Carbon` — see
  [`Package.swift`](Package.swift). `otool -L Klef.app/Contents/MacOS/klef`
  shows the full list.
- **Everything stays local.** Your keyboard-to-layout mappings live in
  `UserDefaults` under `klef.mappings.v1`. Nothing leaves your Mac.
- **Logs are redacted.** Device names are passed through
  [`Log.redactSerialLike`](Sources/klef/Diagnostics/Logger.swift), which strips
  trailing serial-looking tokens before anything is written.

Klef is MIT-licensed and the whole thing is ~2000 lines of Swift with no
third-party dependencies. If you'd rather not trust a downloaded binary,
[build it yourself](#building-from-source).

## Goals

- Detect every connected keyboard (built-in, USB, Bluetooth) and surface them in
  a menu bar UI.
- Map each keyboard to one input source from the system's enabled list.
- Switch the active input source automatically on keyboard change, with the
  lowest practical latency.
- Polished onboarding for the required Input Monitoring permission.
- Signed and notarized DMG, macOS 13 (Ventura) and later.

## Non-goals

- Per-app or per-website switching (use [Input Source Pro](https://inputsource.pro/)
  for that).
- Key remapping or modifier customization (use Karabiner-Elements).
- CJKV input methods.
- Mac App Store distribution (the sandbox blocks `IOHIDManager`).

## Using it

1. Click the keyboard icon in the menu bar.
2. Select **Open Klef Settings…**.
3. For each detected keyboard, pick an input source from the dropdown.

Mappings persist across relaunches. Keyboards you have seen before appear in a
"Known, not connected" section even when unplugged.

### Updates

Klef checks GitHub once a day for a newer release and, if it finds one, shows it
in the menu with a link to the download page. It never downloads or installs
anything by itself — use **Check for Updates…** in the menu to look right away,
or turn the daily check off entirely in Settings.

> **Re-grant Input Monitoring after every update.** macOS ties the permission to
> the app binary's code signature hash, and because Klef's builds are ad-hoc
> signed rather than Developer ID signed, that hash changes with every release.
> After installing a new version, Klef will appear to run normally but switch
> nothing until you re-enable it under System Settings → Privacy & Security →
> Input Monitoring. The menu bar icon shows a warning badge whenever this has
> happened. Developer ID signing fixes it permanently and is planned for V1.0.

## Building from source

### Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ (the Command Line Tools alone are not enough — SwiftUI's macro
  plugins ship inside Xcode)

### Build & run

```bash
swift build -c release && ./scripts/bundle-app.sh --force && open Klef.app
```

`bundle-app.sh` assembles `Klef.app`, stamps the version, and ad-hoc signs it.
Drop `-c release` for a faster debug build.

To produce a DMG the way CI does:

```bash
./scripts/make-dmg.sh          # → dist/Klef-<version>.dmg
```

> **Note:** after each rebuild the binary's code-sign hash changes, so macOS may
> invalidate the Input Monitoring grant and silently stop switching. Re-grant in
> System Settings → Privacy & Security → Input Monitoring when that happens.

### Versioning

`version.txt` is the single source of truth for the marketing version and is
maintained automatically by release-please. `Resources/Info.plist` carries
placeholders that `bundle-app.sh` substitutes at bundle time — the build number
comes from the commit count. Don't hand-edit either version key.

### App icon

`Resources/Klef.icns` and `Resources/logo/klef-icon.png` are committed. Only
re-run this after changing the artwork in `Resources/logo/`:

```bash
./scripts/make-icon.sh
```

### Tech

Swift 5.10+, SwiftUI for settings, AppKit `NSStatusItem` for the menu bar,
`IOHIDManager` for keyboard detection, Carbon TIS for input source switching.
No third-party dependencies.

### LaunchAgent scripts

`scripts/install-launch-agent.sh` and `uninstall-launch-agent.sh` are left over
from the pre-menu-bar V0.2 dogfood path. They still work if you want to run the
raw binary as a background daemon, but the `.app` bundle is the supported route.

## Known limitations (V0.3)

- **First-keystroke race.** A single character key-down as the very first input
  on a freshly-promoted keyboard can still race the switch — a measured
  improvement, not a fix.
- **Secure Input.** When `IsSecureEventInputEnabled()` is true (password fields,
  some Terminal contexts), the switch is attempted but may silently fail. Logged
  as a warning.
- **Two identical keyboards on the same Mac** are indistinguishable — identity
  is `locationID`-based.
- **Builds are ad-hoc signed only.** Developer ID signing and notarization are
  planned for V1.0; the release pipeline is already wired for them. Until then,
  every update revokes the Input Monitoring grant (see [Updates](#updates)),
  which is also why Klef only *notifies* about new versions instead of
  installing them — a silent in-app update would leave a dead app behind.
- **No first-launch onboarding.** The Settings window opens the Input Monitoring
  pane directly when permission is denied, but there is no welcome flow. V1.0.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow
[Conventional Commits](https://www.conventionalcommits.org/) — that's what drives
the changelog and the version bump.

## License

[MIT](LICENSE).
