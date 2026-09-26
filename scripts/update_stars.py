#!/usr/bin/env python3
"""Writes the repo's star count into the site's Star button, once it's worth
showing. Run daily by .github/workflows/stars.yml, so visitors' browsers never
ask GitHub for it (the site loads nothing from third parties).

  scripts/update_stars.py 52   → "Star | 52"
  scripts/update_stars.py 12   → "Star" (below the threshold, no number)
"""
import pathlib
import re
import sys

THRESHOLD = 50
PAGE = pathlib.Path(__file__).resolve().parent.parent / "site/index.html"


def label(stars: int) -> str:
    if stars < THRESHOLD:
        return ""
    text = f"{stars / 1000:.1f}k".replace(".0k", "k") if stars >= 1000 else str(stars)
    return f'<span class="count" aria-label="{stars} stars">{text}</span>'


def main() -> None:
    stars = int(sys.argv[1])
    page = PAGE.read_text()
    updated, n = re.subn(r"<!--stars-->.*?<!--/stars-->", f"<!--stars-->{label(stars)}<!--/stars-->", page, flags=re.S)
    if n != 1:
        sys.exit("star marker not found in site/index.html")
    if updated != page:
        PAGE.write_text(updated)
        print(f"star count now {stars}")


if __name__ == "__main__":
    main()
