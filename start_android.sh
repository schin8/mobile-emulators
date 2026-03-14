#!/usr/bin/env bash
set -euo pipefail

DEFAULT_AVD="Pixel_8_API_36"
DEFAULT_PROXY="http://127.0.0.1:8080"
EMU_LOG="/tmp/android-emulator.log"

usage() {
  cat <<EOF
Usage: ./startemulator.sh [options] [avd_name]

Options:
  --list              List available AVDs
  --reset             Kill and restart ADB server
  --proxy [host:port] Launch with HTTP proxy (default: $DEFAULT_PROXY)
  --log               Stream device logs (adb logcat)
  --stop              Kill the running emulator
  --help -h           Show this help message

Arguments:
  avd_name   AVD to launch (default: $DEFAULT_AVD)
EOF
}

PROXY=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list)    echo "Available AVDs:"; emulator -list-avds; exit 0 ;;
    --reset)   echo "Resetting ADB..."; adb kill-server && adb start-server && adb devices; exit 0 ;;
    --log)
      DEVICE=$(adb devices | grep emulator | awk '{print $1}')
      if [[ -n "$DEVICE" ]]; then
        echo "Streaming device logs (Ctrl+C to stop)..."
        adb -s "$DEVICE" logcat -v color
      else
        echo "No running emulator found."
      fi
      exit 0 ;;
    --stop)
      DEVICE=$(adb devices | grep emulator | awk '{print $1}')
      if [[ -n "$DEVICE" ]]; then
        echo "Killing emulator ($DEVICE)..."
        adb -s "$DEVICE" emu kill
        echo "Emulator stopped."
      else
        echo "No running emulator found."
      fi
      exit 0 ;;
    --proxy)
      if [[ -n "${2:-}" && ! "$2" == --* ]]; then
        PROXY="$2"; shift
      else
        PROXY="$DEFAULT_PROXY"
      fi
      shift ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

AVD_NAME="${POSITIONAL[0]:-$DEFAULT_AVD}"

# Validate AVD exists
if ! emulator -list-avds 2>/dev/null | grep -qx "$AVD_NAME"; then
  echo "Error: AVD '$AVD_NAME' not found. Available AVDs:"
  emulator -list-avds
  exit 1
fi

# Pick a port that isn't already in use by another emulator
EXISTING_PORTS=$(adb devices | awk '/^emulator-/{split($1,a,"-"); print a[2]}' || true)
EMU_PORT=5554
while echo "$EXISTING_PORTS" | grep -qx "$EMU_PORT"; do
  EMU_PORT=$((EMU_PORT + 2))
done
DEVICE="emulator-${EMU_PORT}"

EMU_ARGS=(-avd "$AVD_NAME" -port "$EMU_PORT")
if [[ -n "$PROXY" ]]; then
  EMU_ARGS+=(-http-proxy "$PROXY")
  echo "Starting emulator with proxy: $PROXY"
fi

echo "Launching $AVD_NAME on port $EMU_PORT (logs: $EMU_LOG)..."
emulator "${EMU_ARGS[@]}" >"$EMU_LOG" 2>&1 &
EMU_PID=$!

# Give the emulator a moment to fail fast (e.g. bad AVD, GPU issues)
sleep 3
if ! kill -0 "$EMU_PID" 2>/dev/null; then
  echo "Error: Emulator process exited early. Last 20 lines of log:"
  tail -20 "$EMU_LOG"
  exit 1
fi

echo "Waiting for $DEVICE to come online..."
adb -s "$DEVICE" wait-for-device

echo "Waiting for boot to complete..."
TIMEOUT=120
ELAPSED=0
while [[ "$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; do
  if (( ELAPSED >= TIMEOUT )); then
    echo "Error: Boot timed out after ${TIMEOUT}s. Last 20 lines of log:"
    tail -20 "$EMU_LOG"
    exit 1
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

disown "$EMU_PID"
echo "Boot complete. $AVD_NAME running as $DEVICE (PID $EMU_PID)."
