#!/bin/sh
set -eu

PROJECT_NAME="iCloudCleanUpCenter"
REPORT_DIR="${HOME}/icloud-reports"
MODE="${1:-full}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  CYAN="$(printf '\033[36m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  CYAN=""
  RESET=""
fi

cron_raw="$(crontab -l 2>/dev/null || true)"
cron_active="$(printf "%s\n" "$cron_raw" | awk 'NF && $1 !~ /^#/')"

job_count="$(printf "%s\n" "$cron_active" | grep -c "iCloudCleanUpCenter/scripts" || true)"
block_count="$(printf "%s\n" "$cron_raw" | grep -c "# Cron entries for Linko helper scripts" || true)"

if printf "%s\n" "$cron_active" | grep -Eq '(^|[[:space:]])ICLOUD_EVICT_ENABLE=1([[:space:]]|$)'; then
  evict_state="ON"
  evict_color="$RED"
elif printf "%s\n" "$cron_active" | grep -Eq '(^|[[:space:]])ICLOUD_EVICT_ENABLE=0([[:space:]]|$)'; then
  evict_state="off"
  evict_color="$GREEN"
else
  evict_state="missing"
  evict_color="$YELLOW"
fi

if command -v brctl >/dev/null 2>&1; then
  brctl_state="ok"
  brctl_color="$GREEN"
else
  brctl_state="missing"
  brctl_color="$YELLOW"
fi

latest_report="$(ls -t "${REPORT_DIR}"/report-*.txt 2>/dev/null | head -n 1 || true)"

if [ -n "$latest_report" ]; then
  latest_report_name="$(basename "$latest_report")"
else
  latest_report_name="none"
fi

if [ "$MODE" = "--brief" ]; then
  printf "%s%s%s %scron%s jobs=%s %sevict=%s%s %sbrctl=%s%s %sreport=%s%s\n" \
    "$BOLD" "iCloud" "$RESET" \
    "$CYAN" "$RESET" "$job_count" \
    "$evict_color" "$evict_state" "$RESET" \
    "$brctl_color" "$brctl_state" "$RESET" \
    "$DIM" "$latest_report_name" "$RESET"

  if [ "$block_count" -gt 1 ]; then
    printf "%s%s%s duplicate cron blocks detected\n" "$YELLOW" "warning:" "$RESET"
  fi

  if [ "$evict_state" = "ON" ]; then
    printf "%s%s%s automated eviction is enabled\n" "$RED" "warning:" "$RESET"
  fi

  exit 0
fi

printf "%s[%s]%s\n" "$BOLD" "$PROJECT_NAME" "$RESET"
printf "  %sscheduler%s  cron\n" "$CYAN" "$RESET"
printf "  %scron jobs%s  %s\n" "$CYAN" "$RESET" "$job_count"
printf "  %sblocks%s     %s\n" "$CYAN" "$RESET" "$block_count"
printf "  %seviction%s   %s%s%s\n" "$CYAN" "$RESET" "$evict_color" "$evict_state" "$RESET"
printf "  %sbrctl%s      %s%s%s\n" "$CYAN" "$RESET" "$brctl_color" "$brctl_state" "$RESET"
printf "  %sreport%s     %s\n" "$CYAN" "$RESET" "$latest_report_name"

if [ "$block_count" -gt 1 ]; then
  printf "  %s%s%s duplicate cron blocks detected\n" "$YELLOW" "warning:" "$RESET"
fi

if [ "$evict_state" = "ON" ]; then
  printf "  %s%s%s automated eviction is enabled\n" "$RED" "warning:" "$RESET"
fi
