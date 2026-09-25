# Security

Superkeys asks for Accessibility access, which lets it see every key you press. That deserves a plain account of what it does with it, and a private way to tell me if something's wrong.

## What Superkeys can see, and what it does with it

- **Every key event passes through it.** Superkeys installs a keyboard event tap (`HyperEventTap.swift`). While neither ✦ Caps Lock nor ☾ right ⌘ is held, each key goes straight on to the app you're typing in, unread.
- **While ✦ or ☾ is held**, it looks at the key's code to decide what to do (snap a window, open an app, send ⌃ C), then drops the event so nothing leaks into the app in front.
- **Nothing you type is stored or logged.** The only things written to disk are your settings: `~/.config/superkeys/config.toml` and `~/Library/Preferences/space.superkeys.plist`.
- **Nothing you type leaves your Mac.** Superkeys makes two kinds of network request, both to superkeys.space: a daily update check (turn it off in Settings → General), and the release notes when you open What's New. Neither carries anything but the app's version. Suggest a Feature and Report a Problem open GitHub in your browser, and send nothing until you submit the form yourself.
- **Accessibility** is also used to move and resize windows. Superkeys reads window positions and sizes for that, and keeps none of it.

Updates are signed with an EdDSA key and verified by Sparkle before they install. The app itself is signed with the same certificate every release.

## Reporting a vulnerability

Please report it privately, not in a public issue: use **[Report a vulnerability](https://github.com/Rxmeez/superkeys-space/security/advisories/new)** on this repository. Describe what you found and how to reproduce it; I'll reply within a few days and credit you in the fix's release notes unless you'd rather not be named.

Only the latest release is supported. Superkeys updates itself, so fixes ship as a new version.
