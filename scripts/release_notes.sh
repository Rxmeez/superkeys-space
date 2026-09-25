#!/bin/zsh
# Prints one version's section of CHANGELOG.md as Markdown, for GitHub releases.
#   scripts/release_notes.sh 0.2.7
set -euo pipefail
cd "$(dirname "$0")/.."
awk -v v="${1:?usage: scripts/release_notes.sh <version>}" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  on && (/^## \[/ || /^\[/) { exit }
  on { print }
' CHANGELOG.md | sed '/./,$!d'
