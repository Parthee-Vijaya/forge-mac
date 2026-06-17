#!/usr/bin/env bash
# Installs the `forge` CLI: builds the optimized binary and symlinks it onto your PATH.
# Re-run any time to pick up the latest build. Uninstall: rm "$(command -v forge)".
set -euo pipefail

cd "$(dirname "$0")/../ForgeKit"
echo "→ Bygger forge (release)…"
swift build -c release --product forge
BIN="$(pwd)/.build/release/forge"

# Pick the first writable directory already on PATH (no sudo needed).
DEST=""
for d in /opt/homebrew/bin "$HOME/.local/bin" /usr/local/bin; do
  if [ -d "$d" ] && [ -w "$d" ]; then DEST="$d/forge"; break; fi
done
if [ -z "$DEST" ]; then
  echo "✗ Ingen skrivbar PATH-mappe fundet. Tilføj fx ~/.local/bin til din PATH og prøv igen." >&2
  exit 1
fi

ln -sf "$BIN" "$DEST"
echo "✓ Installeret: $DEST → $BIN"
echo
echo "Kom i gang:"
echo "  forge chat                 # fuldskærms-TUI i ./forge-app"
echo "  forge new min-app          # nyt projekt"
echo "  forge chat --project min-app"
