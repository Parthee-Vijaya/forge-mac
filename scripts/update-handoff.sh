#!/bin/sh
# Regenererer commit-loggen + "Sidst opdateret" i HANDOFF.md og stager den.
# Kaldes af .git/hooks/pre-commit, så HANDOFF.md følger med hvert commit.
# Idempotent og fejlsikker: aborterer aldrig et commit (exit 0).

set -e
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
DOC="$ROOT/HANDOFF.md"
[ -f "$DOC" ] || exit 0

# Seneste 20 commits (historik t.o.m. forrige commit — det nye commit findes
# endnu ikke under pre-commit, så det dukker op i HANDOFF ved næste commit).
HO_LOG="$(git log -20 --pretty=format:'- `%h` %ad — %s' --date=short 2>/dev/null || true)"
[ -n "$HO_LOG" ] || HO_LOG="(ingen commits endnu)"
HO_DATE="$(date +%Y-%m-%d)"
export HO_LOG HO_DATE

TMP="$(mktemp)"
awk '
  /<!-- COMMITLOG:START -->/ { print; print ENVIRON["HO_LOG"]; skip=1; next }
  /<!-- COMMITLOG:END -->/   { skip=0; print; next }
  skip                       { next }
  /^- \*\*Sidst opdateret:\*\*/ { print "- **Sidst opdateret:** " ENVIRON["HO_DATE"]; next }
  { print }
' "$DOC" > "$TMP" && mv "$TMP" "$DOC"

git add "$DOC" 2>/dev/null || true
exit 0
