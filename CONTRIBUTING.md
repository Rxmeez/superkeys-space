# Contributing to Superkeys

Thanks for helping. Superkeys is small on purpose: two keys, done well. That shapes what gets merged, so a little context first saves you time.

## Ideas and problems

- **An idea:** [suggest a feature](https://github.com/Rxmeez/superkeys-space/issues/new?template=feature.yml). If it's already there, a 👍 on it is the best vote.
- **Something broken:** [report a problem](https://github.com/Rxmeez/superkeys-space/issues/new?template=bug.yml). Settings → General → Report a Problem fills in your versions for you.
- **A security problem:** report it privately, as [SECURITY.md](SECURITY.md) describes.

## Before you build something

Fixes are welcome straight away. For a new feature or anything that changes behaviour, **open an issue first** so we can agree on the shape before you spend time on it. Some things are ruled out on purpose:

- Superkeys never types, records or sends what you type. Anything that needs to is out.
- No accounts, analytics or background network traffic beyond the update check.
- The ✦ and ☾ keys stay Superkeys' own keys, invisible to other apps (they aren't ⌃⌥⇧⌘).
- It stays a small menu bar app, not a full window manager or scripting engine.

## Building

1. Xcode 16 or later on macOS 14 or later.
2. Open `Superkeys.xcodeproj` and run the **Superkeys** scheme. Debug builds are **Superkeys Dev** (`space.superkeys.dev`), with their own settings (`~/.config/superkeys-dev/`) and their own Accessibility entry.
3. Quit any installed Superkeys first: both remap the same keys.
4. Grant Accessibility when asked. The ad-hoc signature changes on every build, so macOS forgets the grant; the README's "Keeping Accessibility across rebuilds" shows how to keep it.

The Xcode project is generated. To add a file, add its name to `scripts/generate_project.py` and run it; don't edit the `.pbxproj` by hand.

## Tests

```bash
xcodebuild -scheme Superkeys -configuration Debug -derivedDataPath build test
```

The tests feed made-up key events to the event tap and parse sample config files, so nothing is typed, launched or remapped. They run on every push and pull request. Add a test with anything that changes how keys are handled or how the config is read.

## Pull requests

- Keep to the style of the code around you: its naming, comment density and idioms. Comments say *why*, briefly.
- User-facing text is short, plain and specific. Use the glyphs the app uses: ✦ for Hyper, ☾ for Meh, ⌃ ⌥ ⇧ ⌘ for modifiers.
- Note user-facing changes under `## [Unreleased]` in `CHANGELOG.md`, in the same voice as the entries already there.
- One change per pull request, with a sentence on what it does and how you checked it. For anything visual, a screenshot.

## License

Superkeys is under the [GNU GPL v3](LICENSE). By contributing, you agree your work is released under the same license.
