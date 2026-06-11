#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KANATA_BIN=/opt/homebrew/opt/kanata/bin/kanata
KANATA_LIST=/opt/homebrew/bin/kanata
PRIMARY_DEVICE=${PRIMARY_DEVICE:-"Apple Internal Keyboard / Trackpad"}

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
PRIMARY_DEVICE="$PRIMARY_DEVICE"

log() {
  printf '%s %s\\n' "\$(date '+%Y-%m-%d %H:%M:%S')" "\$*" >> "\$LOG"
}

device_ready() {
  local devices
  devices="\$(\$KANATA_LIST --list 2>&1 || true)"
  if grep -Fq "\$PRIMARY_DEVICE" <<< "\$devices"; then
    log "Detected primary keyboard: \$PRIMARY_DEVICE"
    return 0
  fi
  return 1
}

log "Waiting for primary keyboard before starting Kanata: \$PRIMARY_DEVICE"

while true; do
  if device_ready; then
    log "Starting Kanata"
    exec "\$KANATA" --no-wait --cfg "\$CFG"
  fi
  sleep 1
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
