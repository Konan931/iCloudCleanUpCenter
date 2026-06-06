#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_TMP=$(mktemp)

# If invoked with --launchd, install launchd plists instead of crontab
if [[ "${1:-}" == "--launchd" ]]; then
  LAUNCH_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$LAUNCH_DIR"
  if compgen -G "$SCRIPT_DIR/launchd/*.plist" >/dev/null; then
    echo "Copying launchd plists to $LAUNCH_DIR"
    cp -v "$SCRIPT_DIR/launchd/"*.plist "$LAUNCH_DIR/"
    echo "Plists copied. Do you want to load them now? (y/N)"
    read -r -n1 REPLY
    echo
    if [[ "$REPLY" = "y" || "$REPLY" = "Y" ]]; then
      for p in "$LAUNCH_DIR"/com.*.plist; do
        echo "Loading $p"
        launchctl load "$p" || true
      done
      echo "LaunchAgents loaded (errors ignored)."
    else
      echo "Plists installed but not loaded. Use 'launchctl load <plist>' to load."
    fi
  else
    echo "No plists found in $SCRIPT_DIR/launchd"
  fi
  exit 0
fi

cat > "$CRON_TMP" <<EOF
# Cron entries for Linko helper scripts
# Daily report at 03:00
0 3 * * * $SCRIPT_DIR/icloud_report.sh >> $HOME/icloud-reports/cron.log 2>&1
# Weekly eviction summary (disabled by default - set ICLOUD_EVICT_ENABLE=1 to enable)
0 4 * * 0 ICLOUD_EVICT_ENABLE=0 $SCRIPT_DIR/icloud_evict.sh >> $HOME/icloud-reports/evict.log 2>&1
# Monthly cleanup summary (1st day at 05:00)
0 5 1 * * $SCRIPT_DIR/cleanup_summary.sh >> $HOME/icloud-reports/cleanup.log 2>&1
EOF

echo "The following crontab entries are ready to install:"
cat "$CRON_TMP"

echo "\nDo you want to install them to your crontab (this will append)? (y/N)"
read -r -n1 REPLY
echo
if [[ "$REPLY" = "y" || "$REPLY" = "Y" ]]; then
  # append to existing crontab
  crontab -l 2>/dev/null || true > "$CRON_TMP".existing || true
  (crontab -l 2>/dev/null || true; cat "$CRON_TMP") | crontab -
  echo "Crontab updated. Use 'crontab -l' to view."
else
  echo "Aborted - no changes made to crontab. To install later, run:"
  echo "  bash $SCRIPT_DIR/install_cron.sh"
fi

rm -f "$CRON_TMP"
