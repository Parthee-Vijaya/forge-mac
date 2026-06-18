#!/bin/bash
# Forge CLI installer.
#   curl -fsSL https://parthee-vijaya.github.io/forge-mac/install.sh | bash
#
# Downloads the prebuilt, standalone `forge` binary from the latest GitHub
# release and drops it on your PATH. No Xcode/Swift toolchain needed, and
# because curl doesn't quarantine downloads there's no Gatekeeper prompt.
set -euo pipefail

REPO="Parthee-Vijaya/forge-mac"
ASSET="forge-macos-arm64.tar.gz"
URL="https://github.com/$REPO/releases/latest/download/$ASSET"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "✗ Forge CLI kører kun på macOS." >&2; exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
  echo "✗ Forge CLI kræver Apple Silicon (arm64)." >&2; exit 1
fi

# First writable dir on PATH wins; otherwise default to ~/.local/bin.
DEST=""
for d in "$HOME/.local/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
  if [ -d "$d" ] && [ -w "$d" ]; then DEST="$d"; break; fi
done
DEST="${DEST:-$HOME/.local/bin}"
mkdir -p "$DEST"

echo "→ Henter forge…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP/$ASSET"
tar -xzf "$TMP/$ASSET" -C "$TMP"
chmod +x "$TMP/forge"
xattr -dr com.apple.quarantine "$TMP/forge" 2>/dev/null || true
mv -f "$TMP/forge" "$DEST/forge"

echo "✓ Installeret: $DEST/forge"
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo
     echo "  $DEST er ikke på din PATH. Tilføj den:"
     echo "    echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac
echo
echo "Kom i gang:"
echo "  forge new min-app      # nyt projekt"
echo "  forge chat             # fuldskærms-TUI · skriv / for kommandoer"
