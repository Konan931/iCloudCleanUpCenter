#!/usr/bin/env bash
set -u

# Central safety helpers for iCloudCleanUpCenter scripts
# Default to dry-run (non-destructive) unless DRY_RUN=0 is set in environment
DRY_RUN="${DRY_RUN:-1}"

# Log helper: use existing LOG_FILE if present, else echo
log_safe() {
  if [ -n "${LOG_FILE:-}" ]; then
    printf "%s\n" "$*" | tee -a "$LOG_FILE"
  else
    printf "%s\n" "$*"
  fi
}

# Detect obviously destructive commands in a command string
is_dangerous_cmd() {
  local cmd="$*"
  case "$cmd" in
    *"rm -rf"*|*"sudo rm -rf"*|*"rm -r "*|*"rm -ri"*|*"-exec rm -rf"*|*"-exec rm -r"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Export helpers so child bash -lc shells can access them when functions are exported.
export DRY_RUN
export -f is_dangerous_cmd >/dev/null 2>&1 || true
export -f log_safe >/dev/null 2>&1 || true

# safe_rm: non-interactive-safe removal helper for scripts
# - In DRY_RUN != 0 it only logs what would be removed.
# - If STAGING_DIR is set, move files there instead of immediate deletion.
safe_rm() {
  # Support glob arguments passed through bash -lc; expand with eval
  if [ "$#" -eq 0 ]; then
    log_safe "safe_rm: no args"
    return 1
  fi

  if [ "${DRY_RUN:-1}" != "0" ]; then
    for p in "$@"; do
      log_safe "DRY-RUN: would remove: $p"
    done
    return 0
  fi

  # If a staging dir is available, try moving instead of deleting
  if [ -n "${STAGING_DIR:-}" ]; then
    mkdir -p "$STAGING_DIR" || true
    for p in "$@"; do
      if [ -e "$p" ]; then
        mv -- "$p" "$STAGING_DIR/" 2>/dev/null && log_safe "Moved $p -> $STAGING_DIR/" || {
          log_safe "Failed to move $p; falling back to rm"
          rm -rf -- "$p" 2>/dev/null || log_safe "Failed to remove $p"
        }
      else
        log_safe "safe_rm: path not found: $p"
      fi
    done
  else
    for p in "$@"; do
      rm -rf -- "$p" 2>/dev/null && log_safe "Removed: $p" || log_safe "Failed to remove: $p"
    done
  fi
}

export -f safe_rm >/dev/null 2>&1 || true

printf "lib.sh loaded (DRY_RUN=%s)\n" "$DRY_RUN" 2>/dev/null || true
