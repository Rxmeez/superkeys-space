#!/bin/zsh
# One-time setup: creates the two release keys and stores them in 1Password.
#
#   1. Sparkle update key (EdDSA): signs every update so installed copies only
#      accept releases you published. Its public half goes into Info.plist.
#   2. "Superkeys" code-signing certificate (self-signed): every release is
#      signed with it, so macOS keeps the Accessibility grant across updates.
#
# Both live only in the 1Password vault "Superkeys" afterwards; local copies
# are removed. Needs the 1Password CLI (`op`), signed in, and Touch ID.
#
#   scripts/setup_signing_keys.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VAULT="Superkeys"
SPARKLE_ITEM="Sparkle update key"
CERT_ITEM="Superkeys signing certificate"
ACCOUNT="superkeys"
BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"

[[ -x "$BIN/generate_keys" ]] || { echo "Build once first so Sparkle's tools are downloaded: xcodebuild -scheme Superkeys -derivedDataPath build -resolvePackageDependencies"; exit 1; }
command -v op >/dev/null || { echo "Install the 1Password CLI: brew install 1password-cli"; exit 1; }

if op item get "$SPARKLE_ITEM" --vault "$VAULT" >/dev/null 2>&1 || op item get "$CERT_ITEM" --vault "$VAULT" >/dev/null 2>&1; then
  echo "Keys already exist in 1Password vault \"$VAULT\". Refusing to create new ones:"
  echo "replacing them would stop existing installs from accepting updates."
  exit 1
fi

op vault get "$VAULT" >/dev/null 2>&1 || op vault create "$VAULT" >/dev/null
echo "Using 1Password vault \"$VAULT\"."

TMP=$(mktemp -d)
chmod 700 "$TMP"
cleanup() {
  rm -rf "$TMP"
  security delete-generic-password -a "$ACCOUNT" -s "https://sparkle-project.org" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Sparkle update key -------------------------------------------------------
"$BIN/generate_keys" --account "$ACCOUNT" >/dev/null
PUBLIC_KEY=$("$BIN/generate_keys" --account "$ACCOUNT" -p)
"$BIN/generate_keys" --account "$ACCOUNT" -x "$TMP/ed25519"

python3 - "$TMP/ed25519" "$PUBLIC_KEY" <<'PY' | op item create --vault "$VAULT" - >/dev/null
import json, sys
private = open(sys.argv[1]).read().strip()
print(json.dumps({
    "title": "Sparkle update key",
    "category": "API_CREDENTIAL",
    "fields": [
        {"id": "credential", "type": "CONCEALED", "label": "credential", "value": private},
        {"id": "public_key", "type": "STRING", "label": "public key", "value": sys.argv[2]},
        {"id": "notesPlain", "type": "STRING", "purpose": "NOTES",
         "value": "EdDSA key that signs Superkeys updates (Sparkle). The public key is SUPublicEDKey in Info.plist. Never replace it: installed copies would stop accepting updates."},
    ],
}))
PY
echo "Stored the Sparkle update key."

# --- Code-signing certificate -------------------------------------------------
cat > "$TMP/cfg" <<'CFG'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Superkeys
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/cfg" 2>/dev/null
P12_PASSWORD=$(openssl rand -base64 24)
LEGACY=""
openssl pkcs12 -help 2>&1 | grep -q -- -legacy && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "Superkeys" \
  -out "$TMP/superkeys.p12" -passout "pass:$P12_PASSWORD"

python3 - "$TMP/superkeys.p12" "$P12_PASSWORD" <<'PY' | op item create --vault "$VAULT" - >/dev/null
import base64, json, sys
p12 = base64.b64encode(open(sys.argv[1], "rb").read()).decode()
print(json.dumps({
    "title": "Superkeys signing certificate",
    "category": "API_CREDENTIAL",
    "fields": [
        {"id": "p12_base64", "type": "CONCEALED", "label": "p12_base64", "value": p12},
        {"id": "password", "type": "CONCEALED", "label": "password", "value": sys.argv[2]},
        {"id": "notesPlain", "type": "STRING", "purpose": "NOTES",
         "value": "Self-signed code-signing identity \"Superkeys\" for releases. Keeping the same certificate keeps users' Accessibility grants across updates."},
    ],
}))
PY
echo "Stored the signing certificate."

# --- Public key into the app ---------------------------------------------------
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" Superkeys/Info.plist
echo
echo "Done. Public update key (now in Superkeys/Info.plist): $PUBLIC_KEY"
echo "Commit Info.plist; the private keys exist only in 1Password."
