# Contributing to Klef

## Branches

- `develop` — integration branch. All work lands here first.
- `main` — release branch. Only ever updated by merging `develop`.

Open feature branches off `develop` and PR back into it. When `develop` is in a
state worth shipping, PR `develop` → `main`; merging that is what triggers the
release machinery.

## Commit messages

Klef uses [Conventional Commits](https://www.conventionalcommits.org/). This is
not a style preference — release-please parses these to compute the next version
and write `CHANGELOG.md`. A commit that doesn't follow the format is silently
dropped from the changelog.

```
feat(settings): add launch at login toggle
fix: re-assert input source on every event from a mapped device
docs: explain the Input Monitoring permission flow
```

Only `feat` drives a minor bump; **every other type bumps the patch**. What the
type really controls is where — and whether — the commit shows up in the
changelog.

| Prefix | Bump | Changelog section |
| ------ | ---- | ----------------- |
| `feat:` | minor | **Features** |
| `fix:` | patch | **Bug Fixes** |
| `perf:` | patch | **Performance** |
| `refactor:` | patch | **Refactoring** |
| `docs:` | patch | **Documentation** |
| `build:` | patch | **Build & Packaging** |
| `revert:` | patch | **Reverts** |
| `chore:`, `ci:`, `test:` | patch | hidden |

A `!` after the type (`feat!:`) or a `BREAKING CHANGE:` footer would normally
force a major bump. While Klef is pre-1.0 it bumps the minor instead
(`bump-minor-pre-major` in `release-please-config.json`).

## Releasing

Releases are fully automated — there is nothing to tag or bump by hand.

1. Merge `develop` → `main` with a merge commit. Give that PR a plain title
   such as `Merge develop into main`, not a Conventional Commit one: GitHub
   copies the PR title into the merge commit body, release-please parses it,
   and a `feat:` title shows up in the changelog a second time.
2. The `Release` workflow opens (or updates) a PR titled
   `chore(main): release X.Y.Z` containing the version bump and the generated
   changelog. Review it.
3. Merge that PR. release-please tags the commit, cuts the GitHub release, and a
   macOS job builds and attaches `Klef-X.Y.Z.dmg` plus its `.sha256`.
4. **Back-merge into `develop`:**

   ```bash
   git checkout develop && git merge --ff-only origin/main && git push
   ```

   The version bump and changelog land on `main` only. Skipping this leaves
   `develop` behind, and the next `develop` → `main` PR conflicts on
   `version.txt` and `CHANGELOG.md` — or silently reverts them.

**Never hand-edit** `version.txt`, `.release-please-manifest.json`, or the
version keys in `Resources/Info.plist`. `version.txt` is the source of truth;
the plist keys are placeholders substituted at bundle time.

> **v0.3.0** was the first automated release. The baseline was seeded at `0.2.0`
> with no earlier tags, which is why its changelog sweeps the full history and
> its compare link points at a `v0.2.0` tag that does not exist.

### Code signing

Releases currently ship ad-hoc signed and unnotarized. The pipeline already
handles Developer ID — adding these four repository secrets is the only step
needed, no workflow change:

| Secret | What it is |
| ------ | ---------- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application cert, base64-encoded `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)` |
| `AC_NOTARY_KEY_P8` / `AC_NOTARY_KEY_ID` / `AC_NOTARY_ISSUER_ID` | App Store Connect API key for notarization |

When `MACOS_SIGN_IDENTITY` is absent the scripts fall back to ad-hoc signing, so
forks and local builds keep working unchanged.

## Building and checking your work

```bash
swift build -c release
./scripts/bundle-app.sh --force
open Klef.app
```

CI runs exactly this on `macos-15`, plus the DMG step, for every push and PR to
`main` and `develop`.

Xcode 15+ is required; the Command Line Tools alone lack SwiftUI's macro plugins
and the build fails with a misleading "external macro implementation could not
be found" error.

## Scope

Please read the **Non-goals** section of the README before proposing a feature.
Per-app switching, key remapping, and CJKV input methods are deliberately out of
scope and better served by other tools.
