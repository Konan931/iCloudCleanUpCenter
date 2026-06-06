#!/usr/bin/env bash
set -euo pipefail

# Load safety helpers if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
if [ -f "$PROJECT_DIR/scripts/lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/scripts/lib.sh"
fi

LOGDIR="$HOME/icloud-reports"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$LOGDIR/cleanup-summary-$TIMESTAMP.txt"

{
  echo "Cleanup summary - $TIMESTAMP"
  echo "Host: $(hostname)"
  echo "\n== Homebrew cache (size) =="
  brew --cache 2>/dev/null | xargs -I{} du -sh {} 2>/dev/null || true

  echo "\n== Pip cache dir =="
  python3 -m pip cache dir 2>/dev/null || true

  echo "\n== NPM cache dir =="
  npm config get cache 2>/dev/null || true

  echo "\n== Xcode DerivedData size =="
  du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null || true

} > "$OUT"

echo "Summary written to $OUT"
