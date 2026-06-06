#!/usr/bin/env bash

# Minimal safety bootstrap: source shared helpers if present and provide
# lightweight fallbacks so this script behaves safely when run standalone.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

if [ -f "$PROJECT_DIR/scripts/lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/scripts/lib.sh"
fi

# Default LOG_FILE if not defined by caller
: "${LOG_FILE:=$HOME/Desktop/iCloudOffload_$(date +%Y%m%d_%H%M%S).log}"

# Provide minimal fallbacks for helper functions (if not already defined)
if ! declare -f log >/dev/null 2>&1; then
  log() { printf "%s\n" "$*" | tee -a "$LOG_FILE"; }
fi

if ! declare -f ask_yes_no >/dev/null 2>&1; then
  ask_yes_no() {
    local prompt="$1"
    local ans
    printf "%s [y/N] " "$prompt"
    read -r ans
    case "$ans" in
      y|Y|yes|YES|Yes) return 0 ;;
      *) return 1 ;;
    esac
  }
fi

if ! declare -f is_inside_icloud >/dev/null 2>&1; then
  ICLOUD_DIR="${ICLOUD_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
  is_inside_icloud() {
    case "$1" in
      "$ICLOUD_DIR"|"$ICLOUD_DIR"/*) return 0 ;;
      *) return 1 ;;
    esac
  }
fi

if ! declare -f run >/dev/null 2>&1; then
  run() {
    log "\$ $*"
    if [ "${DRY_RUN:-1}" != "0" ] && is_dangerous_cmd "$*"; then
      log "DRY-RUN: skipping destructive command: $*"
      return 0
    fi
    "$@" 2>&1 | tee -a "$LOG_FILE"
  }
fi

offload_icloud_folder() {
  local src=""
  local name=""
  local stamp=""
  local dest=""
  local zipfile=""

  section "OFFLOAD ICLOUD FOLDER"

  src="$(ask_path "Enter iCloud folder path to offload:")"

  if [ -z "$src" ]; then
    log "No source entered."
    return
  fi

  if [ ! -e "$src" ]; then
    log "Source does not exist: $src"
    return
  fi

  if ! is_inside_icloud "$src"; then
    log "Refused: source is not inside iCloud Drive."
    log "$src"
    return
  fi

  if [ ! -d "$TARGET_VOLUME" ]; then
    log "Target volume missing: $TARGET_VOLUME"
    return
  fi

  name="$(basename "$src")"
  stamp="$(date +%Y%m%d_%H%M%S)"
  dest="$TARGET_VOLUME/iCloud_Offload_${stamp}/${name}"
  zipfile="${dest}.zip"

  mkdir -p "$(dirname "$dest")"

  log "Source: $src"
  log "Destination: $dest"
  log "Zip file: $zipfile"

  if ask_yes_no "Copy this iCloud folder to external volume now?"; then
    run rsync -aE --progress "$src/" "$dest/"
    size_of "$src"
    size_of "$dest"
  else
    log "Skipped copy."
    return
  fi

  if ask_yes_no "Create zip archive of copied folder?"; then
    run ditto -c -k --sequesterRsrc --keepParent "$dest" "$zipfile"
    run_sh "ls -lh \"$zipfile\""
    run_sh "ditto -t -k \"$zipfile\" | head"
  fi

  log ""
  log "The source is still in iCloud:"
  log "$src"
  log ""
  log "Deleting it will free iCloud storage after sync and after Recently Deleted is cleared."

  if ask_yes_no "Delete original iCloud folder now using rm -ri?"; then
    run safe_rm "$src"
  else
    log "Original iCloud folder was kept."
  fi
}

preview_path() {
  local target="$1"

  if [ -z "$target" ]; then
    echo "No path given."
    return 1
  fi

  if [ ! -e "$target" ]; then
    echo "Missing path: $target"
    return 1
  fi

  echo ""
  echo "------------------------------------------------------------"
  echo "PREVIEW: $target"
  echo "------------------------------------------------------------"

  echo ""
  echo "== Total size =="
  du -sh "$target" 2>/dev/null || true

  echo ""
  echo "== Direct children by size =="
  du -xhd 1 "$target" 2>/dev/null | sort -h | tail -n 50

  echo ""
  echo "== Big files over 500 MB =="
  find "$target" -type f -size +500M -exec ls -lh {} \; 2>/dev/null | sort -k5 -h | tail -n 50

  echo ""
  echo "== File type count =="
  find "$target" -type f 2>/dev/null \
    | awk '
      {
        n=split($0,a,".");
        if (n>1) {
          ext=tolower(a[n]);
          count[ext]++;
        } else {
          count["no_extension"]++;
        }
      }
      END {
        for (e in count) print count[e], e;
      }
    ' \
    | sort -nr \
    | head -n 40

  echo ""
  echo "== Recently modified files =="
  find "$target" -type f -mtime -30 -print 2>/dev/null | head -n 100

  echo ""
  if ask_yes_no "Open this folder in Finder?"; then
    open "$target"
  fi
}
