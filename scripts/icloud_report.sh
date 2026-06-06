#!/usr/bin/env bash
set -euo pipefail

# Load safety helpers if available (DRY_RUN, logging helpers)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
if [ -f "$PROJECT_DIR/scripts/lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/scripts/lib.sh"
fi

LOGDIR="$HOME/icloud-reports"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$LOGDIR/report-$TIMESTAMP.txt"

echo "iCloud Report - $TIMESTAMP" > "$OUT"
echo "Host: $(hostname)" >> "$OUT"

iCLOUD_DIR="$HOME/Library/Mobile Documents"

if [[ ! -d "$iCLOUD_DIR" ]]; then
  echo "iCloud Drive directory not found: $iCLOUD_DIR" >> "$OUT"
  echo "Report written to $OUT"
  exit 0
fi

# Summary sizes
{
  echo "\n== Total iCloud usage =="
  du -sh "$iCLOUD_DIR" 2>/dev/null || true

  echo "\n== Top-level usage (sorted) =="
  du -hd 1 "$iCLOUD_DIR" 2>/dev/null | sort -h | tail -n 50 || true

  echo "\n== Largest files (>100M) =="
  find "$iCLOUD_DIR" -type f -size +100M -print0 2>/dev/null | xargs -0 ls -lh 2>/dev/null | sort -k5 -h | tail -n 100 || true

  echo "\n== Recently modified files (last 30 days) =="
  find "$iCLOUD_DIR" -type f -mtime -30 -print0 2>/dev/null | xargs -0 ls -lt 2>/dev/null | head -n 100 || true
} >> "$OUT"

# small sanity note
echo "\nReport location: $OUT"

echo "Report written to $OUT"
