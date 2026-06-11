#!/usr/bin/env bash
set -euo pipefail

read -r -p "Remove Kanata LaunchDaemon and local config? [y/N] " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 0 ;;
esac

sudo launchctl bootout system /Library/LaunchDaemons/homebrew.mxcl.kanata.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/homebrew.mxcl.kanata.plist
rm -f "$HOME/.config/kanata/start-kanata-when-ready.sh" "$HOME/.config/kanata/kanata.kbd"

echo "Kanata LaunchDaemon and local config removed."
echo "The Karabiner VirtualHIDDevice daemon/driver was left installed because other tools may use it."
