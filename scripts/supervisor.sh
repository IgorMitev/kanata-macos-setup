#!/bin/bash
set -euo pipefail

KANATA="/Library/Application Support/local.kanata-macos-setup/bin/kanata"
CONFIG="/Library/Application Support/local.kanata-macos-setup/config/kanata.kbd"
POLL_INTERVAL="${KANATA_DEVICE_POLL_INTERVAL:-2}"
RESTART_DELAY="${KANATA_RESTART_DELAY:-2}"
KANATA_PID=""

log() {
  printf '%s supervisor: %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*"
}

physical_devices() {
  "$KANATA" --list 2>/dev/null | /usr/bin/awk '
    $1 ~ /^0x[[:xdigit:]]+$/ && !($2 == 5824 && $3 == 10203) && $0 !~ /Karabiner.*VirtualHIDKeyboard/ {
      print
    }
  ' | /usr/bin/sort
}

stop_kanata() {
  if [[ -n "$KANATA_PID" ]] && /bin/kill -0 "$KANATA_PID" 2>/dev/null; then
    log "stopping Kanata pid=$KANATA_PID"
    /bin/kill -TERM "$KANATA_PID" 2>/dev/null || true
    wait "$KANATA_PID" 2>/dev/null || true
  fi
  KANATA_PID=""
}

start_kanata() {
  log "starting Kanata"
  "$KANATA" --no-wait --cfg "$CONFIG" &
  KANATA_PID=$!
  log "started Kanata pid=$KANATA_PID"
}

shutdown() {
  stop_kanata
  exit 0
}

trap shutdown INT TERM
trap stop_kanata EXIT

[[ -x "$KANATA" ]] || { log "Kanata binary is missing"; exit 1; }
[[ -r "$CONFIG" ]] || { log "Kanata config is missing"; exit 1; }
[[ "$POLL_INTERVAL" =~ ^[1-9][0-9]*$ ]] || { log "invalid KANATA_DEVICE_POLL_INTERVAL"; exit 1; }
[[ "$RESTART_DELAY" =~ ^[1-9][0-9]*$ ]] || { log "invalid KANATA_RESTART_DELAY"; exit 1; }

LAST_DEVICES="$(physical_devices || true)"
start_kanata

while /bin/sleep "$POLL_INTERVAL"; do
  if ! /bin/kill -0 "$KANATA_PID" 2>/dev/null; then
    wait "$KANATA_PID" 2>/dev/null || STATUS=$?
    log "Kanata exited (status=${STATUS:-0}); retrying in ${RESTART_DELAY}s"
    KANATA_PID=""
    /bin/sleep "$RESTART_DELAY"
    LAST_DEVICES="$(physical_devices || true)"
    unset STATUS
    start_kanata
    continue
  fi

  CURRENT_DEVICES="$(physical_devices || true)"
  if [[ "$CURRENT_DEVICES" != "$LAST_DEVICES" ]]; then
    log "physical keyboard set changed; restarting Kanata"
    stop_kanata
    LAST_DEVICES="$CURRENT_DEVICES"
    start_kanata
  fi
done
