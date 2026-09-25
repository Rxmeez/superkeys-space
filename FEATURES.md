# Feature ideas

Candidates for Superkeys, ranked by how much they help against how hard they are. Each one notes what macOS actually allows, because several obvious designs turned out to be blocked (see *Constraints* at the end).

Effort: **S** an afternoon, **M** a few days, **L** needs research or a new subsystem.

## Before launch

Required before the Download button and `brew install` go live on superkeys.space.

| # | Task | Why | Effort |
|---|---|---|---|
| 16 | **Apple Developer ID signing (optional)** | Not required for a pet project: 0.1.0 ships unsigned-by-Apple and users click Open Anyway once. Worth the $99/year only if Superkeys outgrows that: a Developer ID certificate plus `notarytool` notarisation removes the first-launch block and allows homebrew/cask submission. `Signing.xcconfig` already accepts a real identity via `Signing.local.xcconfig`. | M |
| 54 | **DMG and release pipeline** | A signed, notarised `.dmg` (or zip) attached to a GitHub release per version, built by a script so every release is reproducible. The landing page's Download button and the cask both point at it. | M |
| 57 | **"Get notified" signup** | The landing page's Coming Soon button becomes an email field through a hosted list (Buttondown or similar, no backend of our own), so launch day has an audience. Keep it one field, no tracking pixels, to match the privacy promise on the page. | S |
| 62 | **Site visit counts, no cookies** | Cloudflare Web Analytics (cookieless, no personal data, one script tag) to see whether the launch film and page are reaching anyone. Website only: the app itself keeps its no-analytics promise, and the page's privacy section should say so plainly. Optional. | S |
| 64 | **Downloads outside the private repo** | Release assets on a private GitHub repo aren't publicly downloadable, so until the source is open the signed DMG lives on Cloudflare R2 behind `superkeys.space/download/`. Switch to GitHub releases once the repo is public. | S |
| 65 | **One-tag release workflow** | Tagging `vX.Y.Z` runs GitHub Actions on a macOS runner: build, Developer ID sign, notarise, staple, DMG, upload, create the release from the changelog section, bump the tap's cask version and sha256, and let the site redeploy. Signing secrets wait on #16. | M |
| 66 | **Clean uninstall** | An "Uninstall Superkeys…" menu item that restores the user's own key mappings, removes the login item, deletes `space.superkeys` preferences, and moves the app to the Trash, and a matching `zap` stanza in the cask (`~/Library/Preferences/space.superkeys.plist`, the login item). Accessibility entries can't be removed by the app, so it opens that pane with a one-line note. Matters for trust in a tool that remaps keys. | S |
| 68 | **Build from source through Homebrew (free, no warning)** | Once the repo is public, a formula in `rxmeez/tap` that compiles Superkeys on the user's Mac: locally built apps aren't quarantined, so there's no Gatekeeper prompt and no signing cost. Needs a Swift Package build next to the Xcode project, the icon as a prebuilt `.icns` (asset catalogs need Xcode's `actool`), and a script that assembles the `.app`. Catch: an ad-hoc signature changes every build, so Accessibility must be re-granted after each upgrade, unless signing with an explicit designated requirement (`identifier "space.superkeys"`) keeps TCC matching; untested. Formulas install under `/opt/homebrew`, so link into `/Applications` in `post_install` or the caveats. Offer it alongside the prebuilt cask, not instead of it. | M |
| 84 | **Clean up config.toml on uninstall** | The cask's `zap` only removes `~/Library/Preferences/space.superkeys.plist`; add `~/.config/superkeys` so `brew uninstall --zap` leaves nothing behind (and mention it in #66). One line in the tap. | S |
| 72 | **Release check before shipping** | `scripts/release.sh` builds and signs, but nothing launches the built app before publishing. A smoke test (launch the Release build, wait for the event tap and remap, quit) would stop a release that can't start, like the missing runpath that stopped Sparkle from loading. | S |
| 73 | **Self-check for macOS behaviour changes** | Two things broke silently this week because macOS changed underneath: synthetic drags from the HID-system event source stopped moving windows, and Mission Control's add button moved outside its screen. A debug-only "diagnostics" run (drag a test window, add then remove a desktop on each display, flip back) would catch both after any macOS update, before users do. | M |
| 74 | **Remove a desktop with ☾ ⌫** | Mission Control exposes `AXRemoveDesktop` on each desktop button (used to clean up during testing). ☾ ⌫ could remove the current desktop on the display under the pointer, moving its windows to the previous one, the counterpart to ☾ n creating desktops. Supersedes #12. | S |
| 76 | **Memory and idle check in CI** | Launch the built app headless-ish, open and close Settings through AX, and fail if the footprint after close grows past a budget or if any process wakes while idle. Would have caught the polling watchdog and the retained Settings window automatically. Pairs with #72 and #73. | M |

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
| 34 | **Pause for a while** | "Pause for 1 hour" and "Pause until tomorrow" as a submenu of the on/off switch (so the menu stays three items), for gaming or screen sharing. Resumes on its own, so it can't be forgotten. One timer, cancelled on manual resume. | S |
| 41 | **Keyboard-only Shortcuts tab** | ↑/↓ to move through the app list, Return to rebind, ⌫ to remove, ⌘N to add. The add sheet is already keyboard-driven; the list it returns to isn't. | S |
| 46 | **Suggest a key** | When an app is picked in Add App, pre-fill its first letter, or the next free number if that's taken (the welcome tour's rule, in `AppPicks.assignKeys`), so Return, Return adds it. Recording a different key still works as now. `BindingsStore.validate` already knows what is free. | S |
| 47 | **Real Caps Lock on both Shift keys** | Some people still need Caps Lock now and then. Pressing left and right Shift together would toggle it, a common Linux convention. Opt-in; the existing `CapsLock` helper already talks to IOHIDSystem, it would set the lock instead of clearing it. | S |
| 51 | **Move focus between windows** | ✦ ⌃ + arrow focuses the window next to this one, without moving anything. After ✦ ↑ arranges four windows, this is how you get between them without the mouse. Reuses the arranger's neighbour search; ✦ ⌃ is unused. | S |
| 78 | **Keystrokes in the chord panel** | Holding ✦ lists your app keys but not your keystrokes, so ✦ C → ⌃ C is invisible once set up. Add them as a row group ("C ⌃C  D ⌃D  R ⌃R"). `CheatSheet` already reads `BindingsStore`. | S |
| 83 | **Give older config files a `[keys]` section** | Files written by 0.2.3 have no `[keys]` heading, so a hand-added `C = "ctrl+c"` lands under `[apps]` (now caught with a hint). On launch, if the file reads cleanly and has no `[keys]`, append the commented empty section without touching anything else. | S |
| 85 | **Update nudge on the icon** | What's New moved from the menu into Settings, so after an update nothing says so unless Settings is opened. A small dot on the menu bar icon until the notes are read (reusing the attention-dot drawing, in a neutral colour) brings that back without a menu item. | S |
| 87 | **Open the config in a code editor** | .toml usually has no default app, so Open falls back to TextEdit. Prefer an installed editor (Zed, VS Code, Sublime Text, BBEdit, Nova) when nothing is registered for .toml. | S |
| 88 | **Say when config.toml is broken** | A syntax error stops the file applying, but only Advanced says so. Show the orange attention dot on the menu bar icon (and a one-line fix-it in the menu, like missing access) until the file reads cleanly. | S |
| 58 | **Key labels that follow your keyboard layout** | Recorded keys take their label from the character typed at the time, which is right for that layout, but two things assume US ANSI: config.toml resolves keys like `"\\"` or `"§"` through a fixed US map (`KeyCodes.typed`), and labels don't update if you later switch layout (British ↔ US, or a German layout). Resolve and relabel with `TISCopyCurrentKeyboardLayoutInputSource` + `UCKeyTranslate`, watching for layout changes. Key codes stay the source of truth, so bindings never break. | M |

## Worth doing

| # | Feature | Why it helps | Effort |
|---|---|---|---|
| 7 | **Bind keys to more than apps** | A URL, a folder, a file, or a Shortcuts.app shortcut on a Hyper key (✦ N runs a "New note" shortcut). The launcher already opens URLs through NSWorkspace; Shortcuts runs via `shortcuts run`. Keystrokes (built) cover key combinations; this adds the rest as new config sections (`[open]`, `[shortcuts]`). | M |
| 80 | **Keystrokes for some apps only** | The same ✦ key doing different things per app: ✦ C → ⌃ C in terminals, nothing (or ⌘ C) elsewhere. `[keys]` stays the default; `[keys."com.mitchellh.ghostty"]` overrides it. The tap already knows the front app via `NSWorkspace`; look it up only when a keystroke key is pressed. | M |
| 81 | **Type a snippet** | ✦ plus a key types a saved piece of text (an email address, a sign-off) through `CGEventKeyboardSetUnicodeString`, under `[text]` in the config. Skipped in secure input fields (passwords), and the file is plain text, so the README should say not to store secrets there. | M |
| 82 | **Keep your comments in config.toml** | Any change in Settings rewrites the whole file, dropping comments and ordering you added by hand. Rewrite only the lines that changed (the reader already knows every entry's line), appending new entries at the end of their section. | M |
| 86 | **Bring keys over from other tools** | People arrive from Karabiner-Elements (complex hyper-key rules), Hyperkey, or Rectangle. A one-time "Import from…" in Advanced that reads their app-launch bindings and window shortcuts and proposes the Superkeys equivalents, listing anything it can't map. Karabiner's JSON is the hard part; Rectangle's shortcuts are plain defaults. | M |
| 8 | **Exclude apps** | Turn the Hyper Key off automatically while a game, VM, or remote-desktop client is frontmost, where Caps Lock may matter. Watch `didActivateApplicationNotification` and pause the tap. | M |
| 9 | **Choose the Hyper Key** | Let people with an external keyboard pick right ⌘, right ⌥, or an F-key instead of Caps Lock. The remap already goes through `UserKeyMapping`; only the source usage changes. | M |
| 11 | **Adjustable gap** | The 8pt gap around snapped windows is hard-coded. A 0–24pt slider in General. | S |
| 21 | **Drag and resize with ✦ and the mouse** | Hold ✦ and move the mouse to drag the window under the pointer from anywhere, or hold ✦ ⌥ to resize it, as on many Linux desktops. To keep typing fast, the mouse tap would exist only while ✦ is held, created on press and removed on release. | M |
| 22 | **Cycle an app's windows** | ✦ Tab steps through the frontmost app's windows in place, without the ⌘ \` guesswork or Mission Control. Reads `kAXWindowsAttribute` and raises the next one. | M |
| 23 | **Forward unmapped chords as ⌃⌥⇧⌘** | Opt-in, off by default. When ✦ plus a key does nothing in Superkeys, send it on as the classic four-modifier "Hyper" so Raycast, Alfred, or app menus can bind it too. Keeps the default promise that the Hyper Key never reaches other apps. | M |
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

## Later

| # | Feature | Why it helps | Effort |
|---|---|---|---|
| 13 | **Desktop 10** | ☾ 0 currently reports "No Desktop 10". Symbolic hotkey 127 may be "Switch to Desktop 10", but that is unverified and needs ten desktops to test. | M |
| 15 | **Rebind the built-in chords** | Let the snap and desktop chords move to other keys, for people who want ✦ H/J/K/L. The recorder and validation already exist. | M |
| 17 | **Tests** | Unit tests for the remap merge, key labels, key validation, snap geometry, the config.toml reader (round trips, problems, syntax errors) and the keystroke tap logic (the DEBUG `selfTestKeystrokes` harness is a ready-made starting point). The remap merge was verified by hand this time; it should not have to be again. | M |
| 67 | **Build check on every push** | A GitHub Actions job on a macOS runner that builds the app (ad hoc signing, no secrets) and runs the tests from #17 for every push and pull request, so a broken build is caught before a release tag, not during it. Also a place to run `swift-format --lint`. Private repos get 2,000 free Actions minutes a month; macOS minutes count 10×, so keep it to one build per push. | S |
| 25 | **Save and restore layouts** | ☾ S saves where every window sits across desktops; ☾ R puts them back, after a display reconnect or a reboot. Restoring onto other desktops reuses the carry, one window at a time, so it will be slow for large layouts. | L |
| 40 | **Glass window chrome** | Build with an Xcode 26+ SDK so the Settings window's toolbar and controls get Liquid Glass natively, and replace the run-time `NSGlassEffectView` lookup with the public API. Blocked only on the installed Xcode (16.4). | S |
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

- **Release plumbing (was #55, #61, #63, #69).** Homebrew cask in `rxmeez/tap`, `/changelog` and `/privacy` pages generated by `scripts/build_pages.py`, Keep a Changelog + SemVer, and releases signed as "Superkeys". The config file also covers the old "keep settings in sync" idea (#44): symlink `~/.config/superkeys` into iCloud Drive or a dotfiles repo.
- **Keystrokes.** ✦ + key sends a combination (✦ C → ⌃ C) to the front app; repeats while held, and the release goes out even if ✦ is let go first. Settings → Shortcuts → Keystrokes (recorders for the key and the combination) and `[keys]` in config.toml. A key is either an app or a keystroke, never both. Chosen over "all unassigned ✦ keys act as ⌃" so stray ✦ presses stay silent. ✦ C / D / R → ⌃ C / D / R are offered, never on by default: step 5 of the welcome tour and "Add All Three" in an empty Keystrokes list (was #77, #79).
- **Welcome tour.** New users get a five-step, hands-on setup instead of Settings on first launch: welcome, Accessibility (moves on by itself when granted), hold Caps Lock and watch the keycap light, your most-used apps (Spotlight use counts from the last 60 days, then Dock and running apps; no extra permission) each offered its first letter, or the next free number on a collision, reassigned live as you tick, then ☾ and the main chords with an Open at login switch. Shown once; closing counts as done but quitting mid-tour doesn't (so "Quit & Reopen" after granting access resumes it). People upgrading skip it. Replay from the menu (Welcome Tour…) or General (Take the Tour).
- **App icon matches the logo.** Moon and stars (the site logo's own paths, not an SF Symbol, whose licence excludes app icons) on a dark keycap; Superkeys Dev uses an indigo keycap with a DEV badge. Sources in `design/`; also the site's apple-touch-icon.
- **Safety and first-run polish.** Crash watchdog restores Caps Lock and right ⌘ within 2 s after a crash or force quit (was #59); orange dot on the menu bar logo plus Reset Access when the keys should work but don't; What's New after an update; a one-time "Try it: hold Caps Lock" confirmation in General (was #60); Superkeys and Superkeys Dev refuse to run together.
- **Multiple displays (built, needs a two-display test).** ✦ ← / → walk a window across displays half by half; ✦ ⌥ ← / → throw it as it is; each display has its own desktops, with ☾ acting on the display under the pointer, per-display flip back, per-display rows in the chord panel, and a "separate Spaces" check in Permissions. Open question for real hardware: whether macOS numbers Switch to Desktop n across displays (default assumption) or per display (`desktopNumbering` setting).
- **First-launch guide.** superkeys.space/install walks through Done (not Move to Bin), Open Anyway, and Accessibility with real screenshots and rings on the exact controls; linked from the site's install box, the README, and the cask caveats.
- **Self-updating releases (0.1.1+).** Sparkle checks superkeys.space/appcast.xml daily; updates are EdDSA-signed and signed with the stable "Superkeys" certificate, so they install with no Gatekeeper prompt and keep Accessibility. Verified 2026-09-25 by updating 0.1.1 → 0.1.2 in place. Keys live in the 1Password vault "Superkeys"; `scripts/release.sh x.y.z` publishes everything. Next: the GitHub Actions release job (#65).
- **0.1.0, installable.** `brew trust --tap rxmeez/tap && brew install --cask rxmeez/tap/superkeys` installs a universal build signed with the stable self-signed identity (so Accessibility survives updates); macOS asks for a one-time Open Anyway until Developer ID notarisation (#16). Release checklist until #65 exists: bump `MARKETING_VERSION`, update CHANGELOG, Release build with `ARCHS="arm64 x86_64"`, `ditto` zip into `site/download/`, push, tag, then update `version` and `sha256` in the tap's `Casks/superkeys.rb`.
- **Superkeys identity.** Renamed from Hypercaps (bundle id `space.superkeys`, settings migrated on first launch); moon-and-stars menu bar logo whose stars light amber for ✦ and moon lights indigo for ☾.
- **Too many windows.** With five or more windows, ✦ ↑ leaves them alone and the menu bar icon turns red, shakes once, and shows the count, instead of beeping.
- **Launch presence.** superkeys.space (static page in `site/`, Cloudflare Pages, deploys on every push) with the autoplaying launch film, and the public Homebrew tap `Rxmeez/homebrew-tap`, which is ready for a cask once a signed build exists.
- **Arrange windows.** ✦ ↑ lays out up to four windows on the current screen (2 → halves, 3 → large plus two stacked, 4 → quarters) and undoes on a second press; ✦ ⇧ arrows swap the focused window with its neighbour. Windows with a minimum size stay pinned to their slot's outer edge. Design notes below.
- **Key colours and glass.** ✦ is warm amber and ☾ moonlight indigo across keycaps, the lit key tiles in Settings, and the menu bar icon while held; everything else keeps the system accent. The chord panel sits on tinted Liquid Glass on macOS 26 and later, with a blur fallback before that.
- **Config file.** `~/.config/superkeys/config.toml` replaces JSON import/export: synced both ways (Settings writes it; saving it applies it, watching both the file and its folder so in-place and replace-style saves work). Keys as typed or `"code:N"`; bad entries skipped with a line number in Settings → Advanced; a syntax error applies nothing and blocks writes so an edit in progress is never overwritten. Dev builds use `superkeys-dev/`.
- **Tidier Settings.** Five tabs: General (on/off, preferences, updates, tour), Keys (the chord reference), Apps, Permissions, Advanced (config file, Reset Access). `desktop_numbering` stays in the file only: it describes how macOS numbers its shortcuts (verified global), not a preference, so it has no switch in Settings.
- **Back and forth.** ☾ with right ⌥ flips to the previous desktop, AeroSpace's workspace-back-and-forth. It tracks every desktop change, not only Superkeys' own, and remembers desktops by ID so adding one never points it at the wrong desktop.
- **Cheat sheet on long hold.** Hold ✦ or ☾ for 0.6s without pressing anything and a panel lists that key's chords; ☾ also shows every desktop with the current one highlighted, which covers most of #18. Off switch in General.
- **Meh Key.** Right ⌘ is a second private key (☾) for desktops: ☾ 1–9 switches, ☾ ⇧ 1–9 moves the window and follows it. Holding ✦ and ☾ together is deliberately unused, left free for a future layer.

## Decided against

- **Tap Caps Lock for Escape.** Removed on purpose: the Hyper Key should never reach other apps. If it returns, it should be opt-in and off by default.
- **Animations, sounds, onboarding carousels.** Out of character for a quiet utility. (The welcome tour isn't a carousel: every step waits for you to do the thing, and it never shows again unless asked.)
- **Analytics, accounts.** Explicit non-goals. (Sparkle updates were too, until the no-$99 distribution plan needed a way to update without Gatekeeper prompts; see #56.)
- **AeroSpace-style features.** Emulated desktops, app home desktops, layer lock, automatic tiling that re-arranges on its own, and a URL scheme were considered and set aside by choice. The on-demand arrange (#50) is different: it runs only when asked.
- **Settings in a separate helper app.** Would keep memory at ~17 MB instead of ~42 MB after Settings is first opened, but means two bundles, an XPC link for live state, slower opening and more release risk. Decided 2026-09-25: not worth the cost for ~25 MB.
- **Naming desktops.** Little benefit with a handful of desktops when the ☾ panel already shows which one you're on.
- **App keys in the menu bar menu (was #24).** The menu was cut to the on/off switch, Settings and Quit on 2026-09-25; lists belong in Settings and the chord panel.
- **Show a window on every desktop.** macOS offers this only for an app's own windows. Doing it to another app's window would need the same kind of cross-process SkyLight call that is ignored for moves. Untested, so it stays off the list until someone proves it works.

## Constraints learned the hard way

- Moving a window between desktops through SkyLight (`CGSMoveWindowsToManagedSpace`, `CGSAddWindowsToSpaces`) is ignored for other processes unless SIP is disabled. Moves have to carry the window through a system desktop switch.
- `CGSManagedDisplaySetCurrentSpace` updates bookkeeping without switching the display. Visible switching has to use the system shortcuts.
- `SLSSpaceCreate` makes a detached space that never joins Mission Control. New desktops come only from pressing `mc.spaces.add` in WindowManager's accessibility tree, which exists only while Mission Control is open.
- Arrow-key system shortcuts carry the function modifier, so their stored flags must be posted as-is.
- Security dialogs ignore synthetic input, so nothing can approve a keychain prompt on the user's behalf.
