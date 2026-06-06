#!/usr/bin/env bash
set -euo pipefail

# Writes a single-line brief status to $HOME/.cache/dwp_status.txt
OUTFILE="$HOME/.cache/dwp_status.txt"
mkdir -p "$(dirname "$OUTFILE")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SH="$SCRIPT_DIR/status.sh"

if [ -x "$STATUS_SH" ]; then
  # Run brief status, strip ANSI colors
  "$STATUS_SH" --brief 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' > "$OUTFILE" || true
else
  echo "iCloud status unavailable" > "$OUTFILE"
fi

exit 0
