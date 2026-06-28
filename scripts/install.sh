#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KANATA_BIN=/opt/homebrew/opt/kanata/bin/kanata
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-60}

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
CFG="$HOME/.config/kanata/kanata.kbd"
LOG=/opt/homebrew/var/log/kanata-wrapper.log
HEALTH_CHECK_INTERVAL=$HEALTH_CHECK_INTERVAL

log() {
  printf '%s %s\\n' "\$(date '+%Y-%m-%d %H:%M:%S')" "\$*" >> "\$LOG"
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

log "Monitoring Kanata process every \${HEALTH_CHECK_INTERVAL}s"
restart_kanata

while true; do
  sleep "\$HEALTH_CHECK_INTERVAL"

  if ! kill -0 "\${KANATA_PID:-}" 2>/dev/null; then
    log "Kanata is not running; restarting"
    restart_kanata
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
