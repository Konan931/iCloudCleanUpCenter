#!/usr/bin/env bash

# iCloudCheck.sh
# Safe-first macOS storage, iCloud, and archive helper.
# Nothing destructive runs without explicit interactive confirmation.
#
# Usage:
#   ./iCloudCheck.sh
#   ./iCloudCheck.sh /Volumes/HD
#   ./iCloudCheck.sh "/Volumes/Other Disk"
#
# Design goals:
#   1. Protect iCloud data.
#   2. Free local Mac storage safely.
#   3. Archive before deleting.
#   4. Keep Family iCloud storage stable.
#   5. Log everything.

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# If the script later moves into scripts/, use the parent as project root.
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$PROJECT_DIR/archives}"
STAGING_DIR="${STAGING_DIR:-$PROJECT_DIR/staging}"
ICLOUD_DIR="${ICLOUD_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
TARGET_VOLUME="${TARGET_VOLUME:-/Volumes/Archiv}"
COMMAND="audit"
COMMAND_ARG=""
OPEN_MENU_AFTER_AUDIT=0

mkdir -p "$LOG_DIR" "$ARCHIVE_DIR" "$STAGING_DIR"

LOG_FILE="${LOG_FILE:-$LOG_DIR/iCloudCheck_$(date +%Y%m%d_%H%M%S).log}"

# Load shared helpers when available.
if [ -f "$PROJECT_DIR/scripts/lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/scripts/lib.sh"
elif [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib.sh"
fi

HR="------------------------------------------------------------"

print_usage() {
  cat <<HELP
$SCRIPT_NAME - safe-first macOS storage and iCloud cleanup helper

Usage:
  $SCRIPT_NAME [command] [options]

Commands:
  audit                         Run full audit only
  menu                          Open interactive cleanup menu
  audit-menu                    Run audit, then open cleanup menu
  status                        Show compact project status
  archive PATH                  Create archive for PATH
  stage PATH                    Move PATH into staging
  evict PATH                    Advanced iCloud local-download eviction for PATH
  open-icloud-settings          Open iCloud settings
  open-storage-settings         Open macOS storage settings
  help                          Show this help

Options:
  --target-volume PATH          Set target volume, default: /Volumes/HD
  --log-file PATH               Set explicit log file
  --log-dir PATH                Set log directory
  --icloud-dir PATH             Set iCloud Drive path
  --archive-dir PATH            Set archive directory
  --staging-dir PATH            Set staging directory
  --open-menu                   Open menu after audit
  -h, --help                    Show this help

Examples:
  $SCRIPT_NAME audit
  $SCRIPT_NAME audit --target-volume /Volumes/HD
  $SCRIPT_NAME menu
  $SCRIPT_NAME archive ~/Downloads
  $SCRIPT_NAME stage ~/Desktop/old-folder
  $SCRIPT_NAME evict "\$HOME/Library/Mobile Documents/com~apple~CloudDocs/SomeFolder"

Safety:
  Destructive actions still require confirmation.
  Terminal deletion inside iCloud Drive is refused by default.
HELP
}

die() {
  printf "Fatal: %s\n" "$*" >&2
  exit 1
}

parse_args() {
  if [ "$#" -eq 0 ]; then
    COMMAND="audit"
    return
  fi

  case "${1:-}" in
    audit|check|menu|audit-menu|status|archive|stage|evict|open-icloud-settings|open-storage-settings|help)
      COMMAND="$1"
      shift
      ;;
    -h|--help)
      COMMAND="help"
      shift
      ;;
    *)
      COMMAND="audit"
      ;;
  esac

  case "$COMMAND" in
    archive|stage|evict)
      if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
        COMMAND_ARG="$1"
        shift
      fi
      ;;
  esac

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target-volume)
        shift
        [ "$#" -gt 0 ] || die "--target-volume requires a path"
        TARGET_VOLUME="$1"
        ;;
      --log-file)
        shift
        [ "$#" -gt 0 ] || die "--log-file requires a path"
        LOG_FILE="$1"
        ;;
      --log-dir)
        shift
        [ "$#" -gt 0 ] || die "--log-dir requires a path"
        LOG_DIR="$1"
        ;;
      --icloud-dir)
        shift
        [ "$#" -gt 0 ] || die "--icloud-dir requires a path"
        ICLOUD_DIR="$1"
        ;;
      --archive-dir)
        shift
        [ "$#" -gt 0 ] || die "--archive-dir requires a path"
        ARCHIVE_DIR="$1"
        ;;
      --staging-dir)
        shift
        [ "$#" -gt 0 ] || die "--staging-dir requires a path"
        STAGING_DIR="$1"
        ;;
      --open-menu)
        OPEN_MENU_AFTER_AUDIT=1
        ;;
      -h|--help)
        COMMAND="help"
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
    shift
  done

  mkdir -p "$LOG_DIR" "$ARCHIVE_DIR" "$STAGING_DIR"
}

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
  # If in dry-run mode and the command looks destructive, skip executing it.
  if [ "${DRY_RUN:-1}" != "0" ] && is_dangerous_cmd "$*"; then
    log "DRY-RUN: skipping destructive command: $*"
    return 0
  fi

  "$@" 2>&1 | tee -a "$LOG_FILE"
}

run_sh() {
  log ""
  log "$ $*"

  # If in dry-run mode, skip obviously destructive commands.
  if [ "${DRY_RUN:-1}" != "0" ] && is_dangerous_cmd "$*"; then
    log "DRY-RUN: skipping destructive command: $*"
    return 0
  fi

  bash -lc "$*" 2>&1 | tee -a "$LOG_FILE"
}

ask_yes_no() {
  local prompt="$1"
  local answer=""

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

ask_path() {
  local prompt="$1"
  local answer=""

  printf "%s " "$prompt"
  read -r answer
  printf "%s" "$answer"
}

exists_path() {
  [ -e "$1" ]
}

is_inside_icloud() {
  local target="$1"

  case "$target" in
    "$ICLOUD_DIR"|"$ICLOUD_DIR"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

size_of() {
  local path="$1"

  if exists_path "$path"; then
    run_sh "du -sh \"${path}\" 2>/dev/null || true"
  else
    log "Missing: $path"
  fi
}

warn_icloud_delete() {
  local target="$1"

  if is_inside_icloud "$target"; then
    log "REFUSED: This path is inside iCloud Drive:"
    log "$target"
    log ""
    log "Deleting this path may delete it from iCloud and synced devices."
    log "Use Finder -> right click -> Remove Download to free local space safely."
    return 0
  fi

  return 1
}

open_macos_storage_settings() {
  section "OPEN MAC STORAGE SETTINGS"

  log "Opening macOS Storage settings."
  log "Manual path: System Settings -> General -> Storage"
  open "x-apple.systempreferences:com.apple.settings.Storage" 2>/dev/null || open -a "System Settings"
}

open_icloud_settings() {
  section "OPEN ICLOUD SETTINGS"

  log "Opening Apple Account / iCloud settings."
  log "Manual path: System Settings -> Apple Account -> iCloud"
  open "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings" 2>/dev/null || open -a "System Settings"
}

print_safety_banner() {
  section "SAFETY MODEL"

  log "This script is audit-first."
  log "It will not delete files without asking."
  log "It will refuse Terminal deletion inside iCloud Drive."
  log "For iCloud Drive local cleanup, prefer Finder -> Remove Download."
  log "Target volume: $TARGET_VOLUME"
  log "Log file: $LOG_FILE"
}

audit_basic_storage() {
  section "BASIC STORAGE AUDIT"

  run df -h
  run diskutil list

  if exists_path "$TARGET_VOLUME"; then
    run diskutil info "$TARGET_VOLUME"
  else
    log "Target volume not found: $TARGET_VOLUME"
    log "Available volumes:"
    run ls -lah /Volumes
  fi
}

audit_top_level_usage() {
  section "TOP-LEVEL LOCAL USAGE"

  run_sh "sudo du -xhd 1 / 2>/dev/null | sort -h"
  run_sh "sudo du -xhd 1 /Users 2>/dev/null | sort -h"
  run_sh "du -xhd 1 \"$HOME\" 2>/dev/null | sort -h"

  if exists_path "$TARGET_VOLUME"; then
    run_sh "sudo du -xhd 1 \"${TARGET_VOLUME}\" 2>/dev/null | sort -h"
  fi
}

audit_icloud_local_pressure() {
  section "ICLOUD DRIVE LOCAL PRESSURE"

  log "iCloud Drive local path:"
  log "$ICLOUD_DIR"

  if ! exists_path "$ICLOUD_DIR"; then
    log "iCloud Drive local folder not found."
    log "This may mean iCloud Drive is disabled or not initialized."
    return
  fi

  size_of "$ICLOUD_DIR"

  log ""
  log "Largest top-level iCloud Drive items:"
  run_sh "du -xhd 1 \"$ICLOUD_DIR\" 2>/dev/null | sort -h | tail -n 50"

  log ""
  log "Large files inside iCloud Drive local folder, 500 MB and above:"
  run_sh "find \"$ICLOUD_DIR\" -type f -size +500M -print 2>/dev/null | sed 's#^#  #' | head -n 300"

  log ""
  log "Reminder:"
  log "To free local Mac space without deleting iCloud data:"
  log "Finder -> iCloud Drive -> right click item -> Remove Download"
}

audit_common_hogs() {
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

  if [ -d "$HOME/Library/Developer" ]; then
    size_of "$HOME/Library/Developer"
    size_of "$HOME/Library/Developer/Xcode/DerivedData"
    size_of "$HOME/Library/Developer/CoreSimulator"
  fi

  if command -v brew >/dev/null 2>&1; then
    log ""
    log "Homebrew cache:"
    run_sh "brew --cache 2>/dev/null | xargs du -sh 2>/dev/null || true"
  fi
}

audit_caches_trash_spotlight() {
  section "CACHES, TRASH, SPOTLIGHT"

  size_of "$HOME/Library/Caches"
  size_of "/Library/Caches"
  size_of "$HOME/.Trash"

  if exists_path "$TARGET_VOLUME/.Trashes"; then
    size_of "$TARGET_VOLUME/.Trashes"
  fi

  if exists_path "$TARGET_VOLUME/.Spotlight-V100"; then
    size_of "$TARGET_VOLUME/.Spotlight-V100"
  fi

  if exists_path "$TARGET_VOLUME/.fseventsd"; then
    size_of "$TARGET_VOLUME/.fseventsd"
  fi

  log ""
  log "Spotlight status:"
  run mdutil -as
}

audit_snapshots() {
  section "TIME MACHINE / APFS SNAPSHOTS"

  run_sh "tmutil listlocalsnapshots / 2>/dev/null || true"
  run_sh "diskutil apfs listSnapshots / 2>/dev/null || true"

  if exists_path "$TARGET_VOLUME"; then
    run_sh "tmutil listlocalsnapshots \"${TARGET_VOLUME}\" 2>/dev/null || true"
    run_sh "diskutil apfs listSnapshots \"${TARGET_VOLUME}\" 2>/dev/null || true"
  fi
}

audit_large_files() {
  section "LARGE LOCAL FILES"

  log "Large files in HOME, 2 GB and above:"
  run_sh "find \"$HOME\" -xdev -type f -size +2G -print 2>/dev/null | sed 's#^#  #' | head -n 300"

  if exists_path "$TARGET_VOLUME"; then
    log ""
    log "Large files on target volume, 2 GB and above:"
    run_sh "sudo find \"$TARGET_VOLUME\" -xdev -type f -size +2G -print 2>/dev/null | sed 's#^#  #' | head -n 300"
  fi
}

archive_path() {
  local target="$1"
  local base=""
  local stamp=""
  local archive_file=""

  if ! exists_path "$target"; then
    log "Missing path: $target"
    return 1
  fi

  base="$(basename "$target")"
  stamp="$(date +%Y%m%d_%H%M%S)"
  archive_file="$ARCHIVE_DIR/${base}_${stamp}.zip"

  section "ARCHIVE PATH"
  log "Target: $target"
  log "Archive: $archive_file"

  if ask_yes_no "Create zip archive now?"; then
    run ditto -c -k --sequesterRsrc --keepParent "$target" "$archive_file"
    run_sh "ls -lh \"$archive_file\""
  else
    log "Skipped archive creation."
  fi
}

archive_custom_path() {
  local target=""

  section "ARCHIVE CUSTOM PATH"

  target="$(ask_path "Enter path to archive:")"

  if [ -z "$target" ]; then
    log "No path entered."
    return
  fi

  archive_path "$target"
}

archive_common_dirs() {
  section "ARCHIVE COMMON DIRECTORIES"

  if ask_yes_no "Archive Downloads?"; then
    archive_path "$HOME/Downloads"
  fi

  if ask_yes_no "Archive Desktop?"; then
    archive_path "$HOME/Desktop"
  fi

  if ask_yes_no "Archive Documents?"; then
    archive_path "$HOME/Documents"
  fi

  if ask_yes_no "Archive Pictures?"; then
    archive_path "$HOME/Pictures"
  fi

  if exists_path "$TARGET_VOLUME"; then
    if ask_yes_no "Archive whole target volume root? This may be huge."; then
      archive_path "$TARGET_VOLUME"
    fi
  fi
}

move_to_staging() {
  local target="$1"
  local base=""
  local stamp=""
  local destination=""

  if ! exists_path "$target"; then
    log "Missing path: $target"
    return 1
  fi

  if warn_icloud_delete "$target"; then
    log "Staging inside iCloud is skipped for safety."
    return 1
  fi

  base="$(basename "$target")"
  stamp="$(date +%Y%m%d_%H%M%S)"
  destination="$STAGING_DIR/${base}_${stamp}"

  section "MOVE TO STAGING"
  log "Target: $target"
  log "Destination: $destination"

  if ask_yes_no "Move this path to staging?"; then
    run mv "$target" "$destination"
    log "Moved to staging. Nothing was deleted."
  else
    log "Skipped staging move."
  fi
}

stage_custom_path() {
  local target=""

  section "STAGE CUSTOM PATH"

  target="$(ask_path "Enter path to move into staging:")"

  if [ -z "$target" ]; then
    log "No path entered."
    return
  fi

  move_to_staging "$target"
}

clean_user_caches() {
  section "OPTIONAL CLEANUP: USER CACHES"

  size_of "$HOME/Library/Caches"

  log "This removes contents of user cache folders."
  log "Apps may recreate these files."

  if ask_yes_no "Delete user cache contents?"; then
    run_sh "find \"$HOME/Library/Caches\" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
    size_of "$HOME/Library/Caches"
  else
    log "Skipped user cache cleanup."
  fi
}

clean_system_caches() {
  section "OPTIONAL CLEANUP: SYSTEM CACHES"

  size_of "/Library/Caches"

  log "This removes contents of /Library/Caches."
  log "Close heavy apps first if possible."

  if ask_yes_no "Delete system cache contents?"; then
    run_sh "sudo find /Library/Caches -mindepth 1 -maxdepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
    size_of "/Library/Caches"
  else
    log "Skipped system cache cleanup."
  fi
}

clean_trash() {
  section "OPTIONAL CLEANUP: TRASH"

  size_of "$HOME/.Trash"

  if ask_yes_no "Empty local user Trash?"; then
    run_sh "find \"$HOME/.Trash\" -mindepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
    size_of "$HOME/.Trash"
  else
    log "Skipped local Trash cleanup."
  fi

  if exists_path "$TARGET_VOLUME/.Trashes"; then
    size_of "$TARGET_VOLUME/.Trashes"

    if ask_yes_no "Empty Trash on target volume?"; then
      run_sh "sudo find \"${TARGET_VOLUME}/.Trashes\" -mindepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
      size_of "$TARGET_VOLUME/.Trashes"
    else
      log "Skipped target volume Trash cleanup."
    fi
  fi
}

clean_developer_caches() {
  section "OPTIONAL CLEANUP: DEVELOPER CACHES"

  if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    size_of "$HOME/Library/Developer/Xcode/DerivedData"
    if ask_yes_no "Delete Xcode DerivedData?"; then
      run_sh "find \"$HOME/Library/Developer/Xcode/DerivedData\" -mindepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
      size_of "$HOME/Library/Developer/Xcode/DerivedData"
    fi
  fi

  if [ -d "$HOME/Library/Developer/CoreSimulator" ]; then
    size_of "$HOME/Library/Developer/CoreSimulator"
    if ask_yes_no "Delete unavailable iOS simulator runtimes/devices via xcrun simctl delete unavailable?"; then
      if command -v xcrun >/dev/null 2>&1; then
        run xcrun simctl delete unavailable
      else
        log "xcrun not found."
      fi
    fi
  fi

  if command -v brew >/dev/null 2>&1; then
    log ""
    log "Homebrew cleanup can remove old downloads and outdated versions."
    if ask_yes_no "Run brew cleanup -s?"; then
      run brew cleanup -s
    fi
  fi
}

thin_local_snapshots() {
  section "OPTIONAL CLEANUP: THIN LOCAL SNAPSHOTS"

  if ask_yes_no "Try to free about 50 GB from local snapshots on /?"; then
    run sudo tmutil thinlocalsnapshots / 50000000000 4
  else
    log "Skipped snapshot thinning for /."
  fi

  if exists_path "$TARGET_VOLUME"; then
    if ask_yes_no "Try to free about 50 GB from local snapshots on target volume?"; then
      run sudo tmutil thinlocalsnapshots "$TARGET_VOLUME" 50000000000 4
    else
      log "Skipped snapshot thinning for target volume."
    fi
  fi
}

disable_spotlight_target() {
  section "OPTIONAL CLEANUP: DISABLE SPOTLIGHT ON TARGET VOLUME"

  if ! exists_path "$TARGET_VOLUME"; then
    log "Target volume not found: $TARGET_VOLUME"
    return
  fi

  if ask_yes_no "Disable Spotlight indexing on target volume?"; then
    run sudo mdutil -i off "$TARGET_VOLUME"
    run sudo mdutil -d "$TARGET_VOLUME"
  else
    log "Skipped Spotlight disable."
  fi
}

delete_spotlight_index_target() {
  section "OPTIONAL CLEANUP: DELETE SPOTLIGHT INDEX ON TARGET VOLUME"

  if ! exists_path "$TARGET_VOLUME/.Spotlight-V100"; then
    log "No .Spotlight-V100 found on target volume."
    return
  fi

  size_of "$TARGET_VOLUME/.Spotlight-V100"

  log "This removes the Spotlight index folder on the target volume."
  log "Recommended only after Spotlight indexing was disabled."

  if ask_yes_no "Delete target volume Spotlight index?"; then
    run sudo mdutil -i off "$TARGET_VOLUME"
    run sudo mdutil -d "$TARGET_VOLUME"
    run_sh "sudo find \"${TARGET_VOLUME}/.Spotlight-V100\" -mindepth 1 -print0 2>/dev/null | xargs -0 -I{} safe_rm \"{}\" || true"
  else
    log "Skipped Spotlight index deletion."
  fi
}

evict_icloud_downloads_advanced() {
  section "ADVANCED: EVICT ICLOUD LOCAL DOWNLOADS"

  log "This tries to remove local iCloud Drive downloads while keeping files in iCloud."
  log "Officially safest method remains Finder -> right click -> Remove Download."
  log "This advanced method uses brctl or fileproviderctl when available."
  log "It is skipped unless you explicitly confirm."

  if ! exists_path "$ICLOUD_DIR"; then
    log "iCloud Drive folder not found:"
    log "$ICLOUD_DIR"
    return
  fi

  if ! ask_yes_no "Continue to advanced iCloud local-download eviction?"; then
    log "Skipped advanced iCloud eviction."
    return
  fi

local target="${1:-}"

if [ -z "$target" ]; then
  target="$(ask_path "Enter iCloud path to evict local downloads from:")"
fi

  if ! exists_path "$target"; then
    log "Path not found: $target"
    return
  fi

  if ! is_inside_icloud "$target"; then
    log "Refused: target is not inside iCloud Drive:"
    log "$target"
    return
  fi

  log "Target: $target"

  if command -v brctl >/dev/null 2>&1; then
    if ask_yes_no "Use brctl evict on files under this iCloud path?"; then
      run_sh "find \"$target\" -type f -exec brctl evict {} \\; 2>/dev/null || true"
    fi
  elif command -v fileproviderctl >/dev/null 2>&1; then
    if ask_yes_no "Use fileproviderctl evict on this iCloud path?"; then
      run fileproviderctl evict "$target"
    fi
  else
    log "Neither brctl nor fileproviderctl was found."
    log "Use Finder -> right click -> Remove Download."
  fi
}

show_status() {
  section "STATUS"

  log "Project directory: $PROJECT_DIR"
  log "Script directory:  $SCRIPT_DIR"
  log "Log directory:     $LOG_DIR"
  log "Archive directory: $ARCHIVE_DIR"
  log "Staging directory: $STAGING_DIR"
  log "iCloud directory:  $ICLOUD_DIR"
  log "Target volume:     $TARGET_VOLUME"
  log "Log file:          $LOG_FILE"

  log ""
  log "Paths:"
  if exists_path "$ICLOUD_DIR"; then
    log "  iCloud Drive: found"
  else
    log "  iCloud Drive: missing"
  fi

  if exists_path "$TARGET_VOLUME"; then
    log "  Target volume: found"
  else
    log "  Target volume: missing"
  fi

  log ""
  log "Tools:"
  for tool in diskutil du find mdutil tmutil ditto open brctl fileproviderctl brew xcrun; do
    if command -v "$tool" >/dev/null 2>&1; then
      log "  $tool: found"
    else
      log "  $tool: missing"
    fi
  done

  log ""
  log "Recent logs:"
  find "$LOG_DIR" -type f -name '*.log' -maxdepth 1 2>/dev/null | sort | tail -n 10 | while read -r item; do
    log "  $item"
  done
}

cleanup_menu() {
  while true; do
    section "CLEANUP MENU"

    cat <<MENU | tee -a "$LOG_FILE"
Choose one action:

  1) Open iCloud settings
  2) Open Mac storage settings
  3) Archive common folders
  4) Archive custom path
  5) Move custom path to staging
  6) Clean user caches
  7) Clean system caches
  8) Empty Trash
  9) Clean developer caches
 10) Thin local snapshots
 11) Disable Spotlight on target volume
 12) Delete Spotlight index on target volume
 13) Advanced: evict local iCloud downloads
 14) Re-run audit summary
  0) Exit

MENU

    printf "Selection: "
    local choice=""
    read -r choice

    case "$choice" in
      1) open_icloud_settings ;;
      2) open_macos_storage_settings ;;
      3) archive_common_dirs ;;
      4) archive_custom_path ;;
      5) stage_custom_path ;;
      6) clean_user_caches ;;
      7) clean_system_caches ;;
      8) clean_trash ;;
      9) clean_developer_caches ;;
      10) thin_local_snapshots ;;
      11) disable_spotlight_target ;;
      12) delete_spotlight_index_target ;;
      13) evict_icloud_downloads_advanced ;;
      14)
        audit_basic_storage
        audit_icloud_local_pressure
        audit_caches_trash_spotlight
        audit_snapshots
        ;;
      0)
        log "Leaving cleanup menu."
        break
        ;;
      *)
        log "Unknown selection: $choice"
        ;;
    esac
  done
}

run_full_audit() {
  print_safety_banner
  audit_basic_storage
  audit_top_level_usage
  audit_icloud_local_pressure
  audit_common_hogs
  audit_caches_trash_spotlight
  audit_snapshots
  audit_large_files
}

main() {
  parse_args "$@"

  case "$COMMAND" in
    help)
      print_usage
      ;;

    audit|check)
      run_full_audit

      section "NEXT STEP"
      log "Audit complete."
      log "Use '$SCRIPT_NAME menu' to open cleanup actions."
      log "Use '$SCRIPT_NAME audit-menu' to run audit and then open the menu."
      log "For iCloud family stability, manually check:"
      log "  System Settings -> Apple Account -> iCloud -> Account Storage"
      log "Focus areas:"
      log "  1. Old iPhone/iPad backups"
      log "  2. Photos"
      log "  3. iCloud Drive"
      log "  4. Messages"
      log "  5. Mail"
      log ""
      log "For local iCloud Drive cleanup, prefer Finder -> Remove Download."
      log "Log file:"
      log "$LOG_FILE"

      if [ "$OPEN_MENU_AFTER_AUDIT" = "1" ]; then
        cleanup_menu
      fi
      ;;

    audit-menu)
      run_full_audit
      cleanup_menu
      ;;

    menu)
      print_safety_banner
      cleanup_menu
      ;;

    status)
      show_status
      ;;

    archive)
      [ -n "$COMMAND_ARG" ] || die "archive requires a path"
      archive_path "$COMMAND_ARG"
      ;;

    stage)
      [ -n "$COMMAND_ARG" ] || die "stage requires a path"
      move_to_staging "$COMMAND_ARG"
      ;;

    evict)
      [ -n "$COMMAND_ARG" ] || die "evict requires an iCloud path"
      evict_icloud_downloads_advanced "$COMMAND_ARG"
      ;;

    open-icloud-settings)
      open_icloud_settings
      ;;

    open-storage-settings)
      open_macos_storage_settings
      ;;

    *)
      die "unknown command: $COMMAND"
      ;;
  esac

  section "DONE"
  log "Finished: $(date)"
  log "Log file:"
  log "$LOG_FILE"
}

main "$@"
