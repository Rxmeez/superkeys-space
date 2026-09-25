# Changelog

All notable changes to Superkeys. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/): `0.x` while things are still settling.

## [Unreleased]

### Added

- **Updates install themselves.** Superkeys checks superkeys.space once a day and installs new versions in the background, with no Gatekeeper prompt and without losing Accessibility access. Turn it off, or check now, in Settings → General; "Check for Updates…" is also in the menu bar menu. Every update is verified against a signing key before it's installed.

### Changed

- Releases are signed as "Superkeys" instead of "Hypercaps Dev". Coming from 0.1.0, grant Accessibility once more after upgrading; later updates keep it.

## [0.1.0] - 2026-09-24

The first build anyone can install. It isn't signed with an Apple Developer ID or notarised yet, so macOS asks you to approve it once on first launch (see the README).

### Added

- **✦ Hyper Key on Caps Lock** and **☾ Meh Key on right ⌘**: private keys that never type, lock, or reach other apps. Everything pressed while one is held is caught.
- **Open apps** with ✦ plus any key you assign.
- **Snap windows**: ✦ ← / → for halves, ✦ ↩ to fill the screen and again to restore.
- **Arrange windows** with ✦ ↑: 2 side by side, 3 as one large and two stacked, 4 as quarters; again to undo. ✦ ⇧ arrow swaps a window with its neighbour. With five or more windows nothing moves and the menu bar icon shakes with the count.
- **Desktops**: ☾ 1–9 switches (creating desktops that don't exist yet), ☾ ⇧ 1–9 moves the window there and follows it, ☾ right ⌥ flips back to the previous desktop.
- **Chord panel**: hold ✦ or ☾ for a moment to see everything that key does, on Liquid Glass where available.
- **Settings file**: export and import app keys and preferences as readable JSON.
- Superkeys' own Settings window snaps and arranges like any other window.
- Menu bar logo that lights amber for ✦ and indigo for ☾ while held.

[Unreleased]: https://github.com/Rxmeez/superkeys-space/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Rxmeez/superkeys-space/releases/tag/v0.1.0
