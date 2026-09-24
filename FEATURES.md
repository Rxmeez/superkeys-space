# Feature ideas

Candidates for Superkeys, ranked by how much they help against how hard they are. Each one notes what macOS actually allows, because several obvious designs turned out to be blocked (see *Constraints* at the end).

Effort: **S** an afternoon, **M** a few days, **L** needs research or a new subsystem.

## Before launch

Required before the Download button and `brew install` go live on superkeys.space.

| # | Task | Why | Effort |
|---|---|---|---|
| 16 | **Apple Developer Program + Developer ID signing** | Buy the Apple Developer Program membership ($99/year), create a **Developer ID Application** certificate, sign with the hardened runtime, and notarise with `notarytool`, then staple. Without it Gatekeeper blocks the download, Homebrew's main cask repo won't accept it, and Accessibility access has to be re-granted after every unsigned update. `Signing.xcconfig` already takes a real identity via `Signing.local.xcconfig`; the self-signed "Hypercaps Dev" identity is for local builds only. | M |
| 54 | **DMG and release pipeline** | A signed, notarised `.dmg` (or zip) attached to a GitHub release per version, built by a script so every release is reproducible. The landing page's Download button and the cask both point at it. | M |
| 55 | **Homebrew cask** | Start with an own tap (`brew install --cask rxmeez/tap/superkeys`), since homebrew/cask expects a notable, notarised app. Move to plain `brew install --cask superkeys` once accepted; the landing page already shows that command as "Soon". Note the established app **Superkey** (superkey.app) is already cask `superkey`, one letter away. | S |
| 56 | **Updates** | Signed builds can update in place. Decide between a Sparkle-style updater (currently listed under "Decided against") and relying on Homebrew and GitHub releases. | S |
| 57 | **"Get notified" signup** | The landing page's Coming Soon button becomes an email field through a hosted list (Buttondown or similar, no backend of our own), so launch day has an audience. Keep it one field, no tracking pixels, to match the privacy promise on the page. | S |

## Next up

| # | Feature | Why it helps | Effort |
|---|---|---|---|
| 3 | **Press again to cycle widths** | ✦ ← pressed again steps ½ → ⅓ → ⅔, as Rectangle does. Today a second press restores the old frame, which only makes sense for ✦ ↩. | S |
| 4 | **Hide when already in front** | ✦ B brings Zen forward; pressing it again while Zen is frontmost hides it. Turns every app key into a toggle. Should be a setting, since some people prefer cycling windows. | S |
| 5 | **Next and previous desktop** | ☾ ← / → walks desktops without counting. Uses the system's own "Move left/right a space" shortcuts (symbolic hotkeys 79 and 81), the same mechanism that makes switching reliable. | S |
| 18 | **Desktop number in the menu bar** | macOS never shows which desktop you are on. A small number beside the ✦ icon ("2") answers it at a glance and confirms every ☾ n. Update on `activeSpaceDidChangeNotification`; the active-space lookup is trustworthy now that switches go through the system shortcuts. | S |
| 19 | **Move without following** | ☾ ⌃ n parks the window on desktop n and leaves you where you are, alongside ☾ ⇧ n which follows it. Both are common workflows, and ☾ ⌃ is currently unused. The carry already knows the desktop it started on. | S |
| 20 | **Undo the last window change** | ✦ Z puts the last snapped, filled, or moved window back where it was. The snap code already stores previous frames; this makes that one stack across all actions. | S |
| 26 | **Flip to the previous app** | ✦ with right ⌥ jumps back to the app you were just in, and again to return. It mirrors ☾ right ⌥ for desktops, so right ⌥ means "back" on both keys. Track `didActivateApplicationNotification`. | S |
| 33 | **Respect Reduce Transparency and Increase Contrast** | The chord panel is now Liquid Glass. With either accessibility setting on it should fall back to a solid dark panel with a visible border, as system HUDs do. Read `NSWorkspace.accessibilityDisplayShouldReduceTransparency` and watch its change notification. | S |
| 34 | **Pause for a while** | "Pause for 1 hour" and "Pause until tomorrow" in the menu bar menu, alongside the on/off toggle, for gaming or screen sharing. Resumes on its own, so it can't be forgotten. One timer, cancelled on manual resume. | S |
| 35 | **Merge on import** | Import currently replaces every app shortcut. A second button, "Add to Mine", would keep existing keys and bring in only keys that are free, listing the conflicts it skipped. Useful for sharing one or two bindings. | S |
| 41 | **Keyboard-only Shortcuts tab** | ↑/↓ to move through the app list, Return to rebind, ⌫ to remove, ⌘N to add. The add sheet is already keyboard-driven; the list it returns to isn't. | S |
| 46 | **Suggest a key** | When an app is picked in Add App, pre-fill the first free letter of its name (Zen → Z, Ghostty → G, or the next letter if taken), so Return, Return adds it. Recording a different key still works as now. `BindingsStore.validate` already knows what is free. | S |
| 47 | **Real Caps Lock on both Shift keys** | Some people still need Caps Lock now and then. Pressing left and right Shift together would toggle it, a common Linux convention. Opt-in; the existing `CapsLock` helper already talks to IOHIDSystem, it would set the lock instead of clearing it. | S |
| 51 | **Move focus between windows** | ✦ ⌃ + arrow focuses the window next to this one, without moving anything. After ✦ ↑ arranges four windows, this is how you get between them without the mouse. Reuses the arranger's neighbour search; ✦ ⌃ is unused. | S |
| 58 | **Key labels that follow your keyboard layout** | Recorded keys take their label from the character typed at the time, which is right for that layout, but two things assume US ANSI: importing a settings file resolves `"key": "\\"` or `"§"` through a fixed US map (`KeyCodes.typed`), and labels don't update if you later switch layout (British ↔ US, or a German layout). Resolve and relabel with `TISCopyCurrentKeyboardLayoutInputSource` + `UCKeyTranslate`, watching for layout changes. Key codes stay the source of truth, so bindings never break. | M |
| 59 | **Caps Lock never left dead** | If Superkeys crashes or is force-quit, Caps Lock stays mapped to F18 (which does nothing) until Superkeys starts again. A tiny launchd agent, or a `KeepAlive` login item that clears Superkeys' two `UserKeyMapping` entries when the app isn't running, would make the keys fall back to normal within seconds. | M |

## Worth doing

| # | Feature | Why it helps | Effort |
|---|---|---|---|
| 6 | **Move window to the next display** | ✦ ⌥ ← / → throws the window to the adjacent screen and keeps its relative size. Pure Accessibility work, no private APIs. | M |
| 7 | **Bind keys to more than apps** | A URL, a folder, a file, or a Shortcuts.app shortcut on a Hyper key (✦ N runs a "New note" shortcut). The launcher already opens URLs through NSWorkspace; Shortcuts runs via `shortcuts run`. | M |
| 8 | **Exclude apps** | Turn the Hyper Key off automatically while a game, VM, or remote-desktop client is frontmost, where Caps Lock may matter. Watch `didActivateApplicationNotification` and pause the tap. | M |
| 9 | **Choose the Hyper Key** | Let people with an external keyboard pick right ⌘, right ⌥, or an F-key instead of Caps Lock. The remap already goes through `UserKeyMapping`; only the source usage changes. | M |
| 11 | **Adjustable gap** | The 8pt gap around snapped windows is hard-coded. A 0–24pt slider in General. | S |
| 12 | **Close empty desktops** | ☾ ⌫ removes the current desktop if it has no windows. Mission Control exposes a close button per desktop in WindowManager's accessibility tree, next to `mc.spaces.add`. Needs checking. | M |
| 21 | **Drag and resize with ✦ and the mouse** | Hold ✦ and move the mouse to drag the window under the pointer from anywhere, or hold ✦ ⌥ to resize it, as on many Linux desktops. To keep typing fast, the mouse tap would exist only while ✦ is held, created on press and removed on release. | M |
| 22 | **Cycle an app's windows** | ✦ Tab steps through the frontmost app's windows in place, without the ⌘ \` guesswork or Mission Control. Reads `kAXWindowsAttribute` and raises the next one. | M |
| 23 | **Forward unmapped chords as ⌃⌥⇧⌘** | Opt-in, off by default. When ✦ plus a key does nothing in Superkeys, send it on as the classic four-modifier "Hyper" so Raycast, Alfred, or app menus can bind it too. Keeps the default promise that the Hyper Key never reaches other apps. | M |
| 24 | **Shortcuts in the menu bar menu** | A short list of assigned app keys in the menu, so checking ✦ G doesn't need Settings. A lighter companion to the cheat sheet (#1). | S |
| 36 | **New window with ✦ ⇧ key** | ✦ B brings Zen forward; ✦ ⇧ B opens a fresh window of it (⌘N sent to that app only, after it activates). Shift is already the "do more" modifier on ☾. Needs a per-app opt-out for apps where ⌘N means something else. | M |
| 37 | **Warn about conflicting remappers** | Karabiner-Elements, Hyperkey, or a manual `hidutil` mapping on Caps Lock or right ⌘ fight the remap silently. Detect them (running bundle IDs and foreign `UserKeyMapping` entries on those keys) and explain in General rather than just not working. | M |
| 38 | **VoiceOver announcements** | Spoken feedback for chords that change something off-screen: "Desktop 3", "Moved Safari to Desktop 2", "Snapped left". `NSAccessibility.post(... .announcementRequested)`. Silent unless VoiceOver is running. | S |
| 39 | **Your own key colours** | Let people pick the ✦ and ☾ accent colours in General (a few curated swatches, not a full picker), carried through the settings file. The palette is already a single place (`Accent`). | S |
| 42 | **A system layer on ✦ + ☾ together** | Holding both keys is deliberately unused. It could hold a small fixed set of Mac actions: lock screen, sleep the display, toggle Dark Mode, mute the microphone. All have public or scriptable routes, none needs an app binding, and the cheat sheet would show them after the usual hold. | M |
| 43 | **Copy diagnostics** | A button in Permissions that copies a plain-text report (macOS version, status, remap installed or not, desktop shortcuts on, desktop count, conflicting apps from #37) for bug reports. Nothing that could identify what was typed. | S |
| 48 | **Frequent apps first in Add App** | Before anything is typed, the app picker lists all apps alphabetically. Showing the apps you open most at the top (counted locally from `didLaunchApplicationNotification`, never sent anywhere) makes the first few bindings one click each. | S |
| 49 | **Hide the menu bar icon** | For people who don't want another icon. Opening Superkeys again from Finder or Spotlight shows Settings, where the icon can come back; `applicationShouldHandleReopen` already does this. | S |
| 52 | **Resize the split** | ✦ − / ✦ = moves the edge between the focused window and its neighbours in 10% steps, so the 3-split can become 60/40 and quarters can go 2:1. The neighbours shrink to match. Takes − and = away from app keys, so it should be opt-in or use ✦ ⌃ ⇧ arrows instead. | M |
| 53 | **The 4 most recent when there are more** | With 5 or more windows ✦ ↑ does nothing, as designed. An option could arrange the 4 most recently used instead and leave the rest behind them. Off by default. | S |
| 60 | **"Try it" check after setup** | Right after Accessibility is granted, General shows one line, "Hold Caps Lock", that turns into a lit ✦ with "You're set" the first time the key is held. Proves the setup worked without a tour or carousel (those stay decided against). | S |

## Later

| # | Feature | Why it helps | Effort |
|---|---|---|---|
| 13 | **Desktop 10** | ☾ 0 currently reports "No Desktop 10". Symbolic hotkey 127 may be "Switch to Desktop 10", but that is unverified and needs ten desktops to test. | M |
| 14 | **Per-display desktops** | With "Displays have separate Spaces", switch and move should act on the display under the pointer, not always the main one. | L |
| 15 | **Rebind the built-in chords** | Let the snap and desktop chords move to other keys, for people who want ✦ H/J/K/L. The recorder and validation already exist. | M |
| 17 | **Tests** | Unit tests for the remap merge, key labels, key validation, and snap geometry. The remap merge was verified by hand this time; it should not have to be again. | M |
| 25 | **Save and restore layouts** | ☾ S saves where every window sits across desktops; ☾ R puts them back, after a display reconnect or a reboot. Restoring onto other desktops reuses the carry, one window at a time, so it will be slow for large layouts. | L |
| 40 | **Glass window chrome** | Build with an Xcode 26+ SDK so the Settings window's toolbar and controls get Liquid Glass natively, and replace the run-time `NSGlassEffectView` lookup with the public API. Blocked only on the installed Xcode (16.4). | S |
| 44 | **Keep settings in sync** | Point Superkeys at a settings file in iCloud Drive or Dropbox and it re-reads it when the file changes, so two Macs share app keys. Builds directly on the settings file; conflicts resolve to the newest file. | M |
| 45 | **Localisation** | All strings are short and in a handful of views. String catalogs would let the app ship in other languages; the key labels (`KeyCodes.named`) need care because they describe physical keys. | M |


## Design: Arrange windows (built)

A layout you ask for, applied once. Not tiling: new windows are left alone, nothing re-arranges on its own, and a window you drag stays where you put it.

**Which windows count.** Standard, resizable, visible windows on the current desktop and the focused window's display. Minimised, hidden, full-screen, and non-resizable windows (panels, System Settings) are left out and don't count towards the 4. Each window counts, not each app, so two Ghostty windows fill two slots.

**Who goes where.** The focused window always takes slot 1 (the left half, or the large pane, or top-left). The rest follow front-to-back order from `CGWindowListCopyWindowInfo`, so the windows you were just using land nearest.

| Windows | Layout |
|---|---|
| 1 | Fills the screen, same as ✦ ↩ |
| 2 | Two columns, 50/50 |
| 3 | Slot 1 is the left half; slots 2 and 3 split the right half top and bottom |
| 4 | Equal quarters: 1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right |
| 5+ | Nothing moves; the menu bar shows "Too many windows to arrange" |

The same 8pt gap as snapping, inside the visible frame (below the menu bar, above the Dock).

**Moving windows between slots: ✦ ⇧ + arrow.** Swaps the focused window with whichever arranged window lies in that direction, found by geometry (the nearest window whose frame is past this one's edge and overlaps it on the other axis). It works on any windows side by side, not only ones Superkeys arranged. Focus stays with the window you moved.
- 2 columns: ⇧ ← / → swaps the two.
- 3 split: ⇧ ← on either small window swaps it with the large one (the "promote" case); ⇧ ↑ / ↓ swaps the two small ones; ⇧ → on the large one swaps it with the small window it overlaps most (the top one on a tie).
- Quarters: ⇧ + any arrow swaps with that neighbour.

**Press again.** ✦ ↑ a second time, with nothing moved in between, puts every window back where it was before arranging (the same restore stack as ✦ ↩ and #20 undo).

**Chord changes this forces.** ✦ ↑ was pencilled in for top/bottom halves (#2, dropped: quarters and the 3-split cover it). ✦ ⇧ ← / → was pencilled in for moving to the next display (#6, now ✦ ⌥ ← / →). ✦ ↓ stays free.

**Things to watch.**
- Apps with a minimum size (some chat apps won't go below ~800pt wide) can't shrink into a quarter. Set the size, read it back, and if it's larger, keep the window anchored at the slot's outer corner so it overlaps inwards rather than off-screen.
- Four windows is four Accessibility round trips (~25–50ms each). Set position and size per window without re-reading in between; ~150ms total is acceptable for a one-shot chord.
- Ratio of the large pane in the 3-split starts at 50%. A later setting could offer 60/40.
- Cheat sheet and General gain two rows: ✦ ↑ "Arrange the windows on this screen" and ✦ ⇧ arrows "Swap with the window next to it".

## Built

- **Arrange windows.** ✦ ↑ lays out up to four windows on the current screen (2 → halves, 3 → large plus two stacked, 4 → quarters) and undoes on a second press; ✦ ⇧ arrows swap the focused window with its neighbour. Windows with a minimum size stay pinned to their slot's outer edge. Design notes below.
- **Key colours and glass.** ✦ is warm amber and ☾ moonlight indigo across keycaps, the lit key tiles in Settings, and the menu bar icon while held; everything else keeps the system accent. The chord panel sits on tinted Liquid Glass on macOS 26 and later, with a blur fallback before that.
- **Settings file.** Export and import app shortcuts and preferences as readable JSON. Keys can be written by hand ("B", "F5"); reserved keys, duplicates, and unknown keys are skipped with a reason, and nothing changes until you confirm.
- **Back and forth.** ☾ with right ⌥ flips to the previous desktop, AeroSpace's workspace-back-and-forth. It tracks every desktop change, not only Superkeys' own, and remembers desktops by ID so adding one never points it at the wrong desktop.
- **Cheat sheet on long hold.** Hold ✦ or ☾ for 0.6s without pressing anything and a panel lists that key's chords; ☾ also shows every desktop with the current one highlighted, which covers most of #18. Off switch in General.
- **Meh Key.** Right ⌘ is a second private key (☾) for desktops: ☾ 1–9 switches, ☾ ⇧ 1–9 moves the window and follows it. Holding ✦ and ☾ together is deliberately unused, left free for a future layer.

## Decided against

- **Tap Caps Lock for Escape.** Removed on purpose: the Hyper Key should never reach other apps. If it returns, it should be opt-in and off by default.
- **Animations, sounds, onboarding carousels.** Out of character for a quiet utility.
- **Sparkle updates, analytics, accounts.** Explicit non-goals.
- **AeroSpace-style features.** Emulated desktops, app home desktops, layer lock, automatic tiling that re-arranges on its own, and a URL scheme were considered and set aside by choice. The on-demand arrange (#50) is different: it runs only when asked.
- **Naming desktops.** Little benefit with a handful of desktops when the ☾ panel already shows which one you're on.
- **Show a window on every desktop.** macOS offers this only for an app's own windows. Doing it to another app's window would need the same kind of cross-process SkyLight call that is ignored for moves. Untested, so it stays off the list until someone proves it works.

## Constraints learned the hard way

- Moving a window between desktops through SkyLight (`CGSMoveWindowsToManagedSpace`, `CGSAddWindowsToSpaces`) is ignored for other processes unless SIP is disabled. Moves have to carry the window through a system desktop switch.
- `CGSManagedDisplaySetCurrentSpace` updates bookkeeping without switching the display. Visible switching has to use the system shortcuts.
- `SLSSpaceCreate` makes a detached space that never joins Mission Control. New desktops come only from pressing `mc.spaces.add` in WindowManager's accessibility tree, which exists only while Mission Control is open.
- Arrow-key system shortcuts carry the function modifier, so their stored flags must be posted as-is.
- Security dialogs ignore synthetic input, so nothing can approve a keychain prompt on the user's behalf.
