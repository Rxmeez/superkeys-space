# Changelog

All notable changes to Superkeys. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/): `0.x` while things are still settling.

## [Unreleased]

### Added

- **Welcome tour for new users.** A short, hands-on setup on first launch: grant Accessibility, hold Caps Lock and watch it light up, pick keys for the apps you use most, and try ☾ for desktops. Move through it with the buttons or with ✦ ← / →, which is also how it teaches the chord; the desktops step shows exactly which ⌘ is the ☾ key. Take it again any time from the menu bar (Welcome Tour…) or Settings → General.

## [0.2.1] - 2026-09-25

### Changed

- **Nothing runs while you're idle.** The helper that restores Caps Lock after a crash used to check every two seconds; it now sleeps until Superkeys actually exits, and restores the keys within a fraction of a second instead of up to two.
- Desktop chords read the list of desktops once instead of several times.
- **Less memory after closing Settings.** The Settings window, the installed-apps list and its icons, and the chord panel are now released when closed instead of kept for the life of the app, and the app list no longer caches every scanned app's bundle.
- The app picker shows apps by the name Finder uses (for example "Visual Studio Code" rather than "Code").
- The chord panel's snap line is shorter, so it no longer gets cut off.

## [0.2.0] - 2026-09-25

### Added

- **Multiple displays.** ✦ ← / → snap to a half, and pressed again at the edge walk the window onto the neighbouring display's facing half. ✦ ⌥ ← / → move the window to the next display as it is. ✦ ↩'s restore works across displays.
- **Desktops per display.** ☾ 1–9 switch the display under the pointer, ☾ ⇧ 1–9 move a window within its own display, and ☾ right ⌥ remembers the previous desktop separately for each display. The chord panel shows one row of desktops per display. Settings → Permissions checks that "Displays have separate Spaces" is on when more than one display is connected.
- **Caps Lock is never left dead.** If Superkeys crashes or is force-quit, Caps Lock and right ⌘ go back to normal right away instead of staying remapped until the next launch.
- **"Keys aren't working" is visible and fixable.** The menu bar logo shows an orange dot when the keys should be on but aren't, and Settings and the menu offer Reset Access for the case where the Accessibility switch looks on but macOS is holding an old entry.
- **What's New after an update**, in the menu until you've read it once.
- **Try it**: right after setup, General asks you to hold Caps Lock and confirms it works.
- Superkeys and Superkeys Dev (a development build) no longer run at the same time; launching one offers to quit the other.

### Fixed

- **☾ ⇧ 1–9 moves windows again.** A recent macOS change made it ignore the drag Superkeys uses to carry a window to another desktop; 0.1.x switched desktops but left the window behind.
- Moving a wide window no longer grabs a toolbar button instead of the title bar.
- New desktops are always added to the right display, and never more than needed.

### Changed

- **New app icon**: the moon-and-stars mark on a dark keycap, matching the menu bar and superkeys.space. Development builds get an indigo "DEV" version.
- The privacy note now mentions the once-a-day update check, which sends nothing but the app's version.
- Pressing ✦ ← or ✦ → again no longer restores the window's previous frame; ✦ ↩ still does.

## [0.1.2] - 2026-09-25

### Added

- The menu bar menu shows which version of Superkeys is running.

## [0.1.1] - 2026-09-25

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

[Unreleased]: https://github.com/Rxmeez/superkeys-space/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Rxmeez/superkeys-space/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Rxmeez/superkeys-space/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/Rxmeez/superkeys-space/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Rxmeez/superkeys-space/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Rxmeez/superkeys-space/releases/tag/v0.1.0
