#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KANATA_BIN=/opt/homebrew/opt/kanata/bin/kanata
KANATA_LIST=/opt/homebrew/bin/kanata
PRIMARY_DEVICE=${PRIMARY_DEVICE:-"Apple Internal Keyboard / Trackpad"}
MISSING_POLL_INTERVAL=${MISSING_POLL_INTERVAL:-10}
CONNECTED_POLL_INTERVAL=${CONNECTED_POLL_INTERVAL:-60}

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This installer is for macOS only." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

brew list kanata >/dev/null 2>&1 || brew install kanata

mkdir -p "$HOME/.config/kanata" /opt/homebrew/var/log
cp "$ROOT/kanata.kbd" "$HOME/.config/kanata/kanata.kbd"

cat > "$HOME/.config/kanata/start-kanata-when-ready.sh" <<SH
#!/bin/bash
set -euo pipefail

KANATA=$KANATA_BIN
KANATA_LIST=$KANATA_LIST
CFG="$HOME/.config/kanata/kanata.kbd"
LOG=/opt/homebrew/var/log/kanata-wrapper.log
MISSING_POLL_INTERVAL=$MISSING_POLL_INTERVAL
CONNECTED_POLL_INTERVAL=$CONNECTED_POLL_INTERVAL

log() {
  printf '%s %s\\n' "\$(date '+%Y-%m-%d %H:%M:%S')" "\$*" >> "\$LOG"
}

configured_keyboards() {
  awk '
    /macos-dev-names-include[[:space:]]*\(/ { in_block=1; next }
    in_block && /\)/ { exit }
    in_block {
      if (match(\$0, /"[^"]+"/)) {
        print substr(\$0, RSTART + 1, RLENGTH - 2)
      }
    }
  ' "\$CFG"
}

keyboard_list() {
  "\$KANATA_LIST" --list 2>&1 || true
}

all_configured_keyboards_connected() {
  local devices missing=0 name
  devices="\$(keyboard_list)"

  while IFS= read -r name; do
    [[ -z "\$name" ]] && continue
    if ! grep -Fq "\$name" <<< "\$devices"; then
      log "Configured keyboard is not connected: \$name"
      missing=1
    fi
  done < <(configured_keyboards)

  [[ "\$missing" -eq 0 ]]
}

restart_kanata() {
  if [[ -n "\${KANATA_PID:-}" ]] && kill -0 "\$KANATA_PID" 2>/dev/null; then
    log "Stopping Kanata pid=\$KANATA_PID"
    kill "\$KANATA_PID" 2>/dev/null || true
    wait "\$KANATA_PID" 2>/dev/null || true
  fi

  log "Starting Kanata"
  "\$KANATA" --no-wait --cfg "\$CFG" &
  KANATA_PID=\$!
  log "Started Kanata pid=\$KANATA_PID"
}

trap '[[ -n "\${KANATA_PID:-}" ]] && kill "\$KANATA_PID" 2>/dev/null || true' EXIT INT TERM

last_devices=""
log "Monitoring configured keyboards before starting Kanata"

while true; do
  current_devices="\$(keyboard_list)"

  if [[ "\$current_devices" != "\$last_devices" ]]; then
    log "Keyboard device list changed"
    last_devices="\$current_devices"
    if all_configured_keyboards_connected; then
      restart_kanata
    else
      log "Waiting for configured keyboards before starting Kanata"
    fi
  elif all_configured_keyboards_connected && ! kill -0 "\${KANATA_PID:-}" 2>/dev/null; then
    log "Kanata is not running while configured keyboards are connected"
    restart_kanata
  fi

  if all_configured_keyboards_connected; then
    sleep "\$CONNECTED_POLL_INTERVAL"
  else
    sleep "\$MISSING_POLL_INTERVAL"
  fi
done
SH
chmod +x "$HOME/.config/kanata/start-kanata-when-ready.sh"

$KANATA_BIN --check --cfg "$HOME/.config/kanata/kanata.kbd"

sed "s#__HOME__#$HOME#g" "$ROOT/launchd/homebrew.mxcl.kanata.plist.template" > /tmp/homebrew.mxcl.kanata.plist
plutil -lint /tmp/homebrew.mxcl.kanata.plist

sudo launchctl bootout system /Library/LaunchDaemons/homebrew.mxcl.kanata.plist 2>/dev/null || true
sudo cp /tmp/homebrew.mxcl.kanata.plist /Library/LaunchDaemons/homebrew.mxcl.kanata.plist
sudo chown root:admin /Library/LaunchDaemons/homebrew.mxcl.kanata.plist
sudo chmod 644 /Library/LaunchDaemons/homebrew.mxcl.kanata.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/homebrew.mxcl.kanata.plist

echo "Kanata installed. Run ./scripts/verify.sh to check status."
echo "If keys duplicate, disable Karabiner-Elements remaps; Kanata only needs the virtual HID driver."
