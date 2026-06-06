#!/usr/bin/env bash
set -euo pipefail

# Load safety helpers if available (DRY_RUN, logging helpers)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
if [ -f "$PROJECT_DIR/scripts/lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/scripts/lib.sh"
fi

# Non-interactive iCloud eviction script. Disabled by default via
# environment variable ICLOUD_EVICT_ENABLE=0 in crontab. To enable,
# set ICLOUD_EVICT_ENABLE=1 in the environment/cron line.

ICLOUD_DIR="$HOME/Library/Mobile Documents"
DAYS="${1:-180}"
LOGDIR="$HOME/icloud-reports"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$LOGDIR/evict-$TIMESTAMP.log"

# Respect explicit opt-in via env var. Default is disabled.
if [[ "${ICLOUD_EVICT_ENABLE:-0}" != "1" ]]; then
  echo "ICLOUD_EVICT_ENABLE is not 1; eviction disabled. Set ICLOUD_EVICT_ENABLE=1 to enable." | tee "$OUT"
  exit 0
fi

if [[ ! -d "$ICLOUD_DIR" ]]; then
  echo "iCloud Drive directory not found: $ICLOUD_DIR" | tee "$OUT"
  exit 1
fi

if ! command -v brctl >/dev/null 2>&1; then
  echo "brctl not available; cannot evict local copies. Exiting." | tee "$OUT"
  exit 1
fi

echo "Eviction run - files older than $DAYS days" | tee -a "$OUT"
find "$ICLOUD_DIR" -type f -mtime +$DAYS -print0 2>/dev/null | while IFS= read -r -d $'\0' f; do
  echo "Evicting: $f" | tee -a "$OUT"
  # best-effort: evict and log errors
  if ! brctl evict "$f" 2>>"$OUT"; then
    echo "Failed to evict $f" | tee -a "$OUT"
  fi
done

echo "Eviction completed" | tee -a "$OUT"
