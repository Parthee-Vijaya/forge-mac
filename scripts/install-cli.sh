#!/usr/bin/env bash
# Installs the `storm` CLI: builds the optimized binary and symlinks it onto your PATH.
# Re-run any time to pick up the latest build. Uninstall: rm "$(command -v storm)".
set -euo pipefail

cd "$(dirname "$0")/../StormbreakerKit"
echo "→ Bygger storm (release)…"
swift build -c release --product storm
BIN="$(pwd)/.build/release/storm"

# Pick the first writable directory already on PATH (no sudo needed).
DEST=""
for d in /opt/homebrew/bin "$HOME/.local/bin" /usr/local/bin; do
  if [ -d "$d" ] && [ -w "$d" ]; then DEST="$d/storm"; break; fi
done
if [ -z "$DEST" ]; then
  echo "✗ Ingen skrivbar PATH-mappe fundet. Tilføj fx ~/.local/bin til din PATH og prøv igen." >&2
  exit 1
fi

ln -sf "$BIN" "$DEST"
echo "✓ Installeret: $DEST → $BIN"
echo
echo "Kom i gang:"
echo "  storm chat                 # fuldskærms-TUI i ./storm-app"
echo "  storm new min-app          # nyt projekt"
echo "  storm chat --project min-app"
