#!/usr/bin/env python3
"""Builds the plain pages of superkeys.space that aren't hand-made:

  site/changelog.html  from CHANGELOG.md (released versions only)
  site/privacy.html    from the text below

They share the look of site/install.html. Run from the repository root;
scripts/release.sh runs it on every release.
"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STYLE = (ROOT / "scripts/_site_style.css.txt").read_text()
EXTRA_STYLE = """
    <style>
      .release { margin-top: 48px; }
      .release h2 { display: flex; align-items: baseline; gap: 14px; margin: 0; font-size: 28px; }
      .release time { font-size: 15px; font-weight: 400; color: var(--faint); }
      .release h3 { margin: 22px 0 6px; font-size: 14px; letter-spacing: 0.06em; text-transform: uppercase; color: var(--amber); }
      .release ul { margin: 0; padding-left: 20px; color: var(--muted); }
      .release li { margin: 8px 0; }
      .release li strong, .prose strong { color: var(--text); }
      .release p { color: var(--muted); }
      .prose h2 { margin: 48px 0 10px; font-size: 24px; }
      .prose p, .prose li { color: var(--muted); }
      .prose ul { padding-left: 20px; }
      .prose li { margin: 8px 0; }
    </style>"""


def page(title, description, path, body):
    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{html.escape(title)}</title>
    <meta name="description" content="{html.escape(description)}" />
    <meta name="color-scheme" content="dark" />
    <meta property="og:title" content="{html.escape(title)}" />
    <meta property="og:description" content="{html.escape(description)}" />
    <meta property="og:image" content="https://superkeys.space/assets/superkeys-poster.jpg" />
    <meta property="og:url" content="https://superkeys.space/{path}" />
    <link rel="icon" href="assets/favicon.svg" type="image/svg+xml" />
    <link rel="apple-touch-icon" href="assets/apple-touch-icon.png" />
{STYLE}{EXTRA_STYLE}
  </head>
  <body>
    <nav>
      <div class="wrap">
        <a class="brand" href="index.html"><img src="assets/favicon.svg" alt="" />Superkeys</a>
      </div>
    </nav>

    <main class="wrap">
{body}
    </main>

    <footer>
      <div class="wrap">
        <a href="index.html">superkeys.space</a> · <a href="install.html">First launch</a> ·
        <a href="changelog.html">Changelog</a> · <a href="privacy.html">Privacy</a> ·
        <a href="https://github.com/Rxmeez/superkeys-space">Source</a> · <a href="https://github.com/Rxmeez/superkeys-space/issues/new?template=feature.yml">Suggest a feature</a>
      </div>
    </footer>
  </body>
</html>
"""


def inline(text):
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return re.sub(r"\[(.+?)\]\((.+?)\)", r'<a href="\2">\1</a>', text)


def changelog():
    text = (ROOT / "CHANGELOG.md").read_text()
    releases = re.findall(r"^## \[(\d+\.\d+\.\d+)\] - (\S+)\n(.*?)(?=^## \[|^\[)", text, re.S | re.M)
    parts = []
    for version, date, section in releases:
        out, in_list = [f'      <section class="release" id="v{version}">',
                        f'        <h2>{version} <time datetime="{date}">{date}</time></h2>'], False
        for line in section.strip().splitlines():
            if line.startswith("- "):
                if not in_list:
                    out.append("        <ul>")
                    in_list = True
                out.append(f"          <li>{inline(line[2:])}</li>")
                continue
            if in_list:
                out.append("        </ul>")
                in_list = False
            if line.startswith("### "):
                out.append(f"        <h3>{inline(line[4:])}</h3>")
            elif line.strip():
                out.append(f"        <p>{inline(line)}</p>")
        if in_list:
            out.append("        </ul>")
        out.append("      </section>")
        parts.append("\n".join(out))
    body = """      <header>
        <h1>Changelog</h1>
        <p class="lede">Every release of Superkeys. Installed copies update themselves; this is what changed.</p>
      </header>
""" + "\n".join(parts)
    return page("Superkeys changelog", "What changed in each release of Superkeys.", "changelog", body)


PRIVACY = """      <header>
        <h1>Privacy</h1>
        <p class="lede">
          Superkeys needs deep access to your Mac to do its job, so here is exactly what it can see, what it keeps,
          and what it sends. Short version: nothing about you leaves your Mac.
        </p>
      </header>
      <div class="prose">
        <h2>What it can see</h2>
        <ul>
          <li><strong>Your keyboard, only while ✦ or ☾ is held.</strong> Superkeys listens for key presses so it can tell
            when Caps Lock or right ⌘ is held. Every other key passes straight through untouched. Keys pressed while one
            is held are read to find the chord, then discarded. Nothing is logged or stored.</li>
          <li><strong>Windows.</strong> Through Accessibility it reads the position and size of windows so it can snap,
            arrange and move them, and which app is in front so it knows which window to act on.</li>
          <li><strong>Desktops.</strong> It reads the list of desktops on each display so ☾ can switch and move between
            them.</li>
          <li><strong>Installed apps.</strong> The app picker lists the apps in your Applications folders so you can assign
            keys. The list stays in memory.</li>
        </ul>

        <h2>What it changes</h2>
        <ul>
          <li><strong>Key mapping.</strong> While it runs, Caps Lock and right ⌘ are remapped to F18 and F19 at the
            system level, merged with any remaps of your own. Quitting, pausing or uninstalling puts yours back, and if
            Superkeys ever crashes, a small helper restores them straight away.</li>
          <li><strong>Desktop shortcuts.</strong> It turns on macOS's own "Switch to Desktop 1–9" shortcuts, which it uses
            to change desktops.</li>
        </ul>

        <h2>What it keeps</h2>
        <p>
          Your app keys and settings, in <code>~/.config/superkeys/config.toml</code> (a plain text file you can read
          and edit) and <code>~/Library/Preferences/space.superkeys.plist</code> on your Mac. Nothing else.
        </p>

        <h2>What it sends</h2>
        <p>
          <strong>One request a day</strong>, to <code>superkeys.space/appcast.xml</code>, to check for a new version. It
          sends nothing but the standard request details, including the app's version number: no identifiers, no system
          profile, no usage data. Updates are signed and verified before they're installed. Turn the check off in
          Settings → General → Keep Superkeys up to date.
        </p>
        <p>There are no analytics, no crash reporting services, and no accounts.</p>

        <h2>This website</h2>
        <p>
          superkeys.space has no cookies, no analytics and no trackers. It's hosted on Cloudflare, which, like any web
          host, processes the standard details of each request (such as IP address) to serve and protect the site.
        </p>

        <h2>Checking it yourself</h2>
        <p>
          Superkeys' source code will be published, so every line on this page can be checked against what the app
          actually does. Until then, macOS shows you the same facts: Superkeys appears only under Accessibility in
          Privacy &amp; Security, and its one network request is visible in any network monitor.
        </p>
      </div>"""


def main():
    (ROOT / "site/changelog.html").write_text(changelog())
    (ROOT / "site/privacy.html").write_text(page(
        "Superkeys privacy", "What Superkeys can see, what it keeps, and what it sends: nothing about you leaves your Mac.",
        "privacy", PRIVACY))


if __name__ == "__main__":
    main()
