#!/usr/bin/env bash

# iCloudCheck.sh
# Safe-first macOS storage and iCloud local-cache audit helper.
# Nothing destructive runs without an explicit interactive confirmation.

set -u

HD_VOLUME="${1:-/Volumes/HD}"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
LOG_FILE="${LOG_FILE:-$HOME/Desktop/iCloudCheck_$(date +%Y%m%d_%H%M%S).log}"

# Load shared helpers (dry-run, safety helpers)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/scripts/lib.sh"
fi

HR="------------------------------------------------------------"

log() {
  printf "%s\n" "$*" | tee -a "$LOG_FILE"
}

section() {
  log ""
  log "$HR"
  log "$1"
  log "$HR"
}

run() {
  log ""
  log "$ $*"
  if [ "${DRY_RUN:-1}" != "0" ] && is_dangerous_cmd "$*"; then
    log "DRY-RUN: skipping destructive command: $*"
    return 0
  fi

  "$@" 2>&1 | tee -a "$LOG_FILE"
}

run_sh() {
  log ""
  log "$ $*"

  if [ "${DRY_RUN:-1}" != "0" ] && is_dangerous_cmd "$*"; then
    log "DRY-RUN: skipping destructive command: $*"
    return 0
  fi

  bash -lc "$*" 2>&1 | tee -a "$LOG_FILE"
}

exists_path() {
  [ -e "$1" ]
}

size_of() {
  local path="$1"

  if exists_path "$path"; then
    run_sh "du -sh \"${path}\" 2>/dev/null || true"
  else
    log "Missing: $path"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local answer

  printf "%s [y/N] " "$prompt"
  read -r answer

  case "$answer" in
    y|Y|yes|YES|Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

need_sudo_hint() {
  log ""
  log "Some checks may ask for sudo. That is normal for system caches, snapshots, and volume metadata."
}

check_basic_storage() {
  section "BASIC STORAGE"

  run df -h
  run diskutil list

  if exists_path "$HD_VOLUME"; then
    run diskutil info "$HD_VOLUME"
  else
    log "HD volume not found at: $HD_VOLUME"
    log "Pass a different mount point as first argument, for example:"
    log "  ./iCloudCheck.sh /Volumes/YourDisk"
  fi
}

check_top_level_usage() {
  section "TOP-LEVEL USAGE"

  run_sh "sudo du -xhd 1 / 2>/dev/null | sort -h"
  run_sh "sudo du -xhd 1 /Users 2>/dev/null | sort -h"
  run_sh "du -xhd 1 \"$HOME\" 2>/dev/null | sort -h"

  if exists_path "$HD_VOLUME"; then
    run_sh "sudo du -xhd 1 \"${HD_VOLUME}\" 2>/dev/null | sort -h"
  fi
}

check_icloud_local() {
  section "ICLOUD LOCAL STATE"

  log "iCloud Drive local path:"
  log "$ICLOUD_DIR"

  if exists_path "$ICLOUD_DIR"; then
    size_of "$ICLOUD_DIR"

    log ""
    log "Largest top-level iCloud Drive folders/files:"
    run_sh "du -xhd 1 \"$ICLOUD_DIR\" 2>/dev/null | sort -h | tail -n 30"

    log ""
    log "Large files in iCloud Drive local cache, 1 GB and above:"
    run_sh "find \"$ICLOUD_DIR\" -type f -size +1G -print 2>/dev/null | sed 's#^#  #' | head -n 100"
  else
    log "iCloud Drive folder not found locally."
    log "This can be normal if iCloud Drive is disabled or has not initialized."
  fi

  log ""
  log "Important: this script does not delete iCloud Drive files."
  log "Use Finder -> right click -> Remove Download if you want to keep files in iCloud but free local space."
}

check_common_space_hogs() {
  section "COMMON SPACE HOGS"

  size_of "$HOME/Downloads"
  size_of "$HOME/Desktop"
  size_of "$HOME/Documents"
  size_of "$HOME/Movies"
  size_of "$HOME/Music"
  size_of "$HOME/Pictures"
  size_of "$HOME/Library/Application Support"
  size_of "$HOME/Library/Containers"
  size_of "$HOME/Library/Group Containers"
  size_of "$HOME/Library/Messages"
  size_of "$HOME/Library/Mail"
}

check_caches_and_trash() {
  section "CACHES AND TRASH"

  size_of "$HOME/Library/Caches"
  size_of "/Library/Caches"
  size_of "$HOME/.Trash"

  if exists_path "$HD_VOLUME/.Trashes"; then
    size_of "$HD_VOLUME/.Trashes"
  else
    log "No .Trashes folder found on $HD_VOLUME"
  fi

  if exists_path "$HD_VOLUME/.Spotlight-V100"; then
    size_of "$HD_VOLUME/.Spotlight-V100"
  else
    log "No .Spotlight-V100 folder found on $HD_VOLUME"
  fi

  if exists_path "$HD_VOLUME/.fseventsd"; then
    size_of "$HD_VOLUME/.fseventsd"
  else
    log "No .fseventsd folder found on $HD_VOLUME"
  fi
}

check_spotlight() {
  section "SPOTLIGHT"

  run mdutil -as

  if exists_path "$HD_VOLUME"; then
    run mdutil -s "$HD_VOLUME"
  fi

  log ""
  log "Spotlight processes:"
  run_sh "ps aux | grep -Ei 'mds|mdworker|mds_stores' | grep -v grep || true"
}

check_snapshots() {
  section "TIME MACHINE / APFS SNAPSHOTS"

  run_sh "tmutil listlocalsnapshots / 2>/dev/null || true"

  if exists_path "$HD_VOLUME"; then
    run_sh "tmutil listlocalsnapshots \"${HD_VOLUME}\" 2>/dev/null || true"
    run_sh "diskutil apfs listSnapshots \"${HD_VOLUME}\" 2>/dev/null || true"
  fi

  run_sh "diskutil apfs listSnapshots / 2>/dev/null || true"
}

check_large_files() {
  section "LARGE LOCAL FILES"

  log "Large files in HOME, 2 GB and above:"
  run_sh "find \"$HOME\" -xdev -type f -size +2G -print 2>/dev/null | sed 's#^#  #' | head -n 200"

  if exists_path "$HD_VOLUME"; then
    log ""
    log "Large files on $HD_VOLUME, 2 GB and above:"
    run_sh "sudo find \"$HD_VOLUME\" -xdev -type f -size +2G -print 2>/dev/null | sed 's#^#  #' | head -n 200"
  fi
}

disable_spotlight_on_hd() {
  section "OPTIONAL: DISABLE SPOTLIGHT ON HD"

  if ! exists_path "$HD_VOLUME"; then
    log "Cannot disable Spotlight. Volume not found: $HD_VOLUME"
    return
  fi

  if ask_yes_no "Disable Spotlight indexing on $HD_VOLUME?"; then
    run sudo mdutil -i off "$HD_VOLUME"
    run sudo mdutil -d "$HD_VOLUME"
  else
    log "Skipped Spotlight disable."
  fi
}

thin_snapshots() {
  section "OPTIONAL: THIN LOCAL SNAPSHOTS"

  if ask_yes_no "Try to free about 50 GB from local Time Machine snapshots on /?"; then
    run sudo tmutil thinlocalsnapshots / 50000000000 4
  else
    log "Skipped snapshot thinning for /."
  fi

  if exists_path "$HD_VOLUME"; then
    if ask_yes_no "Try to free about 50 GB from local Time Machine snapshots on $HD_VOLUME?"; then
      run sudo tmutil thinlocalsnapshots "$HD_VOLUME" 50000000000 4
    else
      log "Skipped snapshot thinning for $HD_VOLUME."
    fi
  fi
}

clean_user_caches() {
  section "OPTIONAL: CLEAN USER CACHES"

  size_of "$HOME/Library/Caches"

  log ""
  log "This deletes the contents of:"
  log "$HOME/Library/Caches"
  log "Apps may recreate these files. Close heavy apps first if possible."

  if ask_yes_no "Delete user cache contents?"; then
    run_sh "find \"$HOME/Library/Caches\" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
    size_of "$HOME/Library/Caches"
  else
    log "Skipped user cache cleanup."
  fi
}

clean_system_caches() {
  section "OPTIONAL: CLEAN SYSTEM CACHES"

  size_of "/Library/Caches"

  log ""
  log "This deletes the contents of:"
  log "/Library/Caches"
  log "This is usually safe, but apps/services may recreate data and ask for permissions again."

  if ask_yes_no "Delete system cache contents?"; then
    run_sh "sudo find /Library/Caches -mindepth 1 -maxdepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
    size_of "/Library/Caches"
  else
    log "Skipped system cache cleanup."
  fi
}

clean_trash() {
  section "OPTIONAL: EMPTY TRASH"

  size_of "$HOME/.Trash"

  if ask_yes_no "Empty your local user Trash?"; then
    run_sh "find \"$HOME/.Trash\" -mindepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
    size_of "$HOME/.Trash"
  else
    log "Skipped local Trash cleanup."
  fi

  if exists_path "$HD_VOLUME/.Trashes"; then
    size_of "$HD_VOLUME/.Trashes"

    if ask_yes_no "Empty Trash on $HD_VOLUME?"; then
      run_sh "sudo find \"${HD_VOLUME}/.Trashes\" -mindepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
      size_of "$HD_VOLUME/.Trashes"
    else
      log "Skipped HD Trash cleanup."
    fi
  fi
}

clean_spotlight_index_on_hd() {
  section "OPTIONAL: DELETE SPOTLIGHT INDEX ON HD"

  if ! exists_path "$HD_VOLUME/.Spotlight-V100"; then
    log "No Spotlight index folder found on $HD_VOLUME"
    return
  fi

  size_of "$HD_VOLUME/.Spotlight-V100"

  log ""
  log "This removes the existing Spotlight index folder on $HD_VOLUME."
  log "Recommended only after Spotlight was disabled for this volume."

  if ask_yes_no "Delete $HD_VOLUME/.Spotlight-V100?"; then
    run sudo mdutil -i off "$HD_VOLUME"
    run sudo mdutil -d "$HD_VOLUME"
    run_sh "sudo find \"${HD_VOLUME}/.Spotlight-V100\" -mindepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
  else
    log "Skipped Spotlight index deletion."
  fi
}

interactive_cleanup_menu() {
  section "INTERACTIVE CLEANUP MENU"

  log "The audit is done."
  log "Now choose optional cleanup actions."
  log "Every cleanup step asks again before doing anything."

  if ask_yes_no "Open cleanup menu?"; then
    clean_user_caches
    clean_system_caches
    clean_trash
    disable_spotlight_on_hd
    clean_spotlight_index_on_hd
    thin_snapshots
  else
    log "No cleanup actions selected."
  fi
}

main() {
  log "iCloudCheck started: $(date)"
  log "Log file: $LOG_FILE"
  log "HD volume target: $HD_VOLUME"
  need_sudo_hint

  check_basic_storage
  check_top_level_usage
  check_icloud_local
  check_common_space_hogs
  check_caches_and_trash
  check_spotlight
  check_snapshots
  check_large_files
  interactive_cleanup_menu

  section "DONE"
  log "Finished: $(date)"
  log "Log file saved at:"
  log "$LOG_FILE"
}

main "$@"
