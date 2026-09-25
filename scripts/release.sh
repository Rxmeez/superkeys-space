#!/bin/zsh
# Builds, signs and publishes a Superkeys release.
#
#   scripts/release.sh 0.2.0            publish
#   scripts/release.sh 0.2.0 --dry-run  build and sign only; publish nothing
#
# Before running: add a "## [0.2.0] - YYYY-MM-DD" section to CHANGELOG.md and
# commit everything. Keys come from the 1Password vault "Superkeys" (Touch ID)
# and never touch the repo: the certificate goes into a throwaway keychain
# deleted on exit, and the Sparkle key is piped straight into Sparkle's tools.
#
# What it does:
#   0. runs the unit tests, and stops if any fail
#   1. bumps the version and build number in scripts/generate_project.py
#   2. builds a universal Release app signed as "Superkeys"
#   3. zips it into site/download/ with release notes from CHANGELOG.md
#   4. regenerates site/appcast.xml (the Sparkle update feed), signed
#   5. commits, tags vX.Y.Z and pushes; Cloudflare Pages publishes the site
#   6. bumps the cask in Rxmeez/homebrew-tap
set -euo pipefail

VERSION=${1:?usage: scripts/release.sh <version> [--dry-run]}
DRY_RUN=${2:-}
cd "$(dirname "$0")/.."
ROOT=$PWD
VAULT="Superkeys"
BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
SITE_URL="https://superkeys.space"
ZIP="site/download/Superkeys-$VERSION.zip"
TAP="$(brew --repository)/Library/Taps/rxmeez/homebrew-tap"

say() { print -P "%F{cyan}==>%f $*"; }
die() { print -P "%F{red}error:%f $*" >&2; exit 1; }

# --- Checks ---------------------------------------------------------------------
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "version must look like 1.2.3"
NOTES_SECTION="$VERSION"
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  # A dry run may use the Unreleased notes and a dirty tree.
  grep -q "^## \[$VERSION\]" CHANGELOG.md || NOTES_SECTION="Unreleased"
else
  [[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first"
  [[ "$(git branch --show-current)" == main ]] || die "release from main"
  git rev-parse "v$VERSION" >/dev/null 2>&1 && die "v$VERSION is already tagged"
  grep -q "^## \[$VERSION\]" CHANGELOG.md || die "add a '## [$VERSION] - $(date +%F)' section to CHANGELOG.md"
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Superkeys/Info.plist)" != SPARKLE_PUBLIC_KEY_NOT_SET ]] \
  || die "run scripts/setup_signing_keys.sh first"
[[ -x "$BIN/sign_update" ]] || xcodebuild -scheme Superkeys -derivedDataPath build -resolvePackageDependencies >/dev/null
command -v op >/dev/null || die "install the 1Password CLI: brew install 1password-cli"

# --- Tests ------------------------------------------------------------------------
say "Running the tests"
TEST_LOG=$(xcodebuild -scheme Superkeys -configuration Debug -derivedDataPath build test 2>&1 || true)
[[ "$TEST_LOG" == *"** TEST SUCCEEDED **"* ]] || { print -r -- "$TEST_LOG" | grep -E "error:|failed" | head -20; die "tests failed"; }

# --- Signing certificate into a throwaway keychain ------------------------------
say "Reading the signing certificate from 1Password"
KEYCHAIN="$(mktemp -d)/release.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -base64 24)
ORIGINAL_KEYCHAINS=("${(@f)$(security list-keychains -d user | sed 's/^ *"//; s/"$//')}")
cleanup() {
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" 2>/dev/null || true
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$(dirname "$KEYCHAIN")"
}
trap cleanup EXIT
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
P12="$(dirname "$KEYCHAIN")/superkeys.p12"
op read "op://$VAULT/Superkeys signing certificate/p12_base64" | base64 -d > "$P12"
security import "$P12" -k "$KEYCHAIN" -P "$(op read "op://$VAULT/Superkeys signing certificate/password")" \
  -T /usr/bin/codesign >/dev/null
rm -f "$P12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"

# --- Version --------------------------------------------------------------------
BUILD=$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' scripts/generate_project.py | head -1) + 1 ))
say "Superkeys $VERSION (build $BUILD)"
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $VERSION;/; s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD;/" \
  scripts/generate_project.py
python3 scripts/generate_project.py

# --- Build ------------------------------------------------------------------------
say "Building a universal Release app"
xcodebuild -scheme Superkeys -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="Superkeys" OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN --timestamp=none" \
  clean build | grep -E "error:|BUILD" || true
APP="build/Build/Products/Release/Superkeys.app"
[[ "$(defaults read "$ROOT/$APP/Contents/Info" CFBundleShortVersionString)" == "$VERSION" ]] || die "build failed"
codesign --verify --deep --strict "$APP" || die "signature check failed"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
[[ "$SIGNATURE" == *"Authority=Superkeys"* ]] || die "not signed as Superkeys"

# --- Package + release notes ---------------------------------------------------
say "Packaging $ZIP"
mkdir -p site/download
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
python3 - "$NOTES_SECTION" > "site/download/Superkeys-$VERSION.html" <<'PY'
import html, re, sys
version = sys.argv[1]
text = open("CHANGELOG.md").read()
section = re.search(rf"^## \[{re.escape(version)}\].*?\n(.*?)(?=^## \[|^\[)", text, re.S | re.M).group(1)
def inline(s):
    s = html.escape(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", s)
out, in_list = [], False
for line in section.strip().splitlines():
    if line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append(f"<li>{inline(line[2:])}</li>")
        continue
    if in_list: out.append("</ul>"); in_list = False
    if line.startswith("### "): out.append(f"<h3>{inline(line[4:])}</h3>")
    elif line.strip(): out.append(f"<p>{inline(line)}</p>")
if in_list: out.append("</ul>")
print("\n".join(out))
PY

python3 scripts/build_pages.py   # site/changelog.html gains this release

say "Signing the update feed"
op read "op://$VAULT/Sparkle update key/credential" | "$BIN/generate_appcast" --ed-key-file - \
  --download-url-prefix "$SITE_URL/download/" --embed-release-notes --maximum-deltas 0 --maximum-versions 0 \
  -o site/appcast.xml site/download
grep -q "<sparkle:shortVersionString>$VERSION<" site/appcast.xml || die "appcast is missing $VERSION"
# generate_appcast moves downloads it no longer lists into old_updates/;
# every release stays downloadable, so put them back.
if [[ -d site/download/old_updates ]]; then
  mv site/download/old_updates/* site/download/ 2>/dev/null || true
  rmdir site/download/old_updates
fi
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  say "Dry run: built and signed $ZIP ($SHA). Nothing published; reverting version files."
  git checkout -- scripts/generate_project.py Superkeys.xcodeproj site/changelog.html site/privacy.html
  git ls-files --error-unmatch site/appcast.xml >/dev/null 2>&1 && git checkout -- site/appcast.xml || rm -f site/appcast.xml
  rm -f "$ZIP" "site/download/Superkeys-$VERSION.html"
  exit 0
fi

# --- Publish ------------------------------------------------------------------------
say "Committing and tagging v$VERSION"
git add scripts/generate_project.py Superkeys.xcodeproj "$ZIP" "site/download/Superkeys-$VERSION.html" site/appcast.xml site/changelog.html site/privacy.html
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "Superkeys $VERSION"
git push -q && git push -q origin "v$VERSION"

say "Waiting for superkeys.space to serve the new build"
for _ in {1..40}; do
  [[ "$(curl -s -m 30 "$SITE_URL/download/Superkeys-$VERSION.zip" | shasum -a 256 | cut -d' ' -f1)" == "$SHA" ]] && break
  sleep 5
done
[[ "$(curl -s -m 30 "$SITE_URL/download/Superkeys-$VERSION.zip" | shasum -a 256 | cut -d' ' -f1)" == "$SHA" ]] \
  || die "download not live yet; the cask was not bumped. Re-run the cask step when it is."

say "Bumping the Homebrew cask"
git -C "$TAP" pull -q
sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/superkeys.rb"
# The app updates itself through Sparkle, so brew shouldn't try to.
grep -q "auto_updates true" "$TAP/Casks/superkeys.rb" || sed -i '' 's/^  depends_on macos/  auto_updates true\
  depends_on macos/' "$TAP/Casks/superkeys.rb"
git -C "$TAP" commit -qam "superkeys $VERSION"
git -C "$TAP" push -q

say "Released Superkeys $VERSION. Installed copies will offer it within a day."
