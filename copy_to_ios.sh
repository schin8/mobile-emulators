#!/usr/bin/env bash
set -euo pipefail

SIM_BASE="$HOME/Library/Developer/CoreSimulator/Devices"

usage() {
  cat <<EOF
Usage: ./copy_to_ios.sh [options] <source_directory>

Copies all files from <source_directory> into the "On My iPhone"
folder of a booted iOS simulator (visible in the Files app).

Options:
  --path     Print the "On My iPhone" path and exit (no copy)
  --help -h  Show this help message

Examples:
  ./copy_to_ios.sh ~/Downloads/tmp
EOF
}

PATH_ONLY=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --path) PATH_ONLY=true; shift ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

if ! $PATH_ONLY; then
  SOURCE_DIR="${POSITIONAL[0]:-}"
  if [[ -z "$SOURCE_DIR" ]]; then
    echo "Error: No source directory specified."
    usage
    exit 1
  fi

  if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: '$SOURCE_DIR' is not a directory."
    exit 1
  fi
fi

# Find booted devices and extract UDIDs
BOOTED_LINES=()
BOOTED_UDIDS=()
while IFS= read -r line; do
  if [[ -n "$line" ]]; then
    BOOTED_LINES+=("$line")
    # Extract UDID from between parentheses, e.g. (XXXXXXXX-XXXX-...)
    UDID=$(echo "$line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
    BOOTED_UDIDS+=("$UDID")
  fi
done < <(xcrun simctl list devices booted | grep -E '\(Booted\)' || true)

if [[ ${#BOOTED_LINES[@]} -eq 0 ]]; then
  echo "Error: No booted iOS simulators found."
  echo "Start a simulator first with: ./start_ios.sh"
  exit 1
fi

if [[ ${#BOOTED_LINES[@]} -gt 1 ]]; then
  echo "Error: Multiple booted simulators found. Only 1 booted device can be used."
  echo ""
  echo "Booted devices:"
  for dev in "${BOOTED_LINES[@]}"; do
    echo "  $dev"
  done
  echo ""
  echo "Shut down extra simulators with: xcrun simctl shutdown <device>"
  exit 1
fi

UDID="${BOOTED_UDIDS[0]}"
echo "Found booted device: ${BOOTED_LINES[0]}"
echo "UDID: $UDID"

# Find the "On My iPhone" directory (FileProvider.LocalStorage app group)
APP_GROUP_BASE="$SIM_BASE/$UDID/data/Containers/Shared/AppGroup"
if [[ ! -d "$APP_GROUP_BASE" ]]; then
  echo "Error: AppGroup directory not found at $APP_GROUP_BASE"
  exit 1
fi

LOCAL_STORAGE_DIR=""
for group_dir in "$APP_GROUP_BASE"/*/; do
  plist="$group_dir/.com.apple.mobile_container_manager.metadata.plist"
  if [[ -f "$plist" ]]; then
    app_id=$(/usr/libexec/PlistBuddy -c "Print :MCMMetadataIdentifier" "$plist" 2>/dev/null || true)
    if [[ "$app_id" == "group.com.apple.FileProvider.LocalStorage" ]]; then
      LOCAL_STORAGE_DIR="$group_dir/File Provider Storage"
      break
    fi
  fi
done

if [[ -z "$LOCAL_STORAGE_DIR" ]]; then
  echo "Error: Could not find 'On My iPhone' (FileProvider.LocalStorage) directory."
  exit 1
fi

DEST_DIR="$LOCAL_STORAGE_DIR"

if $PATH_ONLY; then
  echo "$DEST_DIR"
  exit 0
fi

mkdir -p "$DEST_DIR"

# Copy files
FILE_COUNT=0
for f in "$SOURCE_DIR"/*; do
  [[ -e "$f" ]] || continue
  cp -R "$f" "$DEST_DIR/"
  echo "  Copied: $(basename "$f")"
  FILE_COUNT=$((FILE_COUNT + 1))
done

if [[ $FILE_COUNT -eq 0 ]]; then
  echo "No files found in '$SOURCE_DIR'."
  exit 0
fi

echo ""
echo "Copied $FILE_COUNT file(s) to 'On My iPhone': $DEST_DIR"
