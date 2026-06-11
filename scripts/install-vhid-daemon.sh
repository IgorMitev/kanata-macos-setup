#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_APP="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
MANAGER="/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
PLIST=/Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist

if [[ ! -x "$DAEMON_APP" ]]; then
  cat >&2 <<'MSG'
Karabiner VirtualHIDDevice daemon was not found.

Install the standalone Karabiner-DriverKit-VirtualHIDDevice package first:
https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v6.2.0

After installing, enable the driver in:
System Settings → General → Login Items & Extensions → Driver Extensions
MSG
  exit 1
fi

if [[ -x "$MANAGER" ]]; then
  sudo "$MANAGER" forceActivate || true
fi

sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo cp "$ROOT/launchd/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist" "$PLIST"
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
sudo launchctl bootstrap system "$PLIST"

echo "Karabiner VirtualHIDDevice daemon installed."
echo "If needed, enable the driver in System Settings → General → Login Items & Extensions → Driver Extensions."
