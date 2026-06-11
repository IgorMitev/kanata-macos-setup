#!/usr/bin/env bash
set -euo pipefail

KANATA=/opt/homebrew/bin/kanata
CFG="$HOME/.config/kanata/kanata.kbd"

echo "== Kanata binary =="
command -v kanata || true
[[ -x /opt/homebrew/opt/kanata/bin/kanata ]] && realpath /opt/homebrew/opt/kanata/bin/kanata || true

echo

echo "== Config check =="
$KANATA --check --cfg "$CFG"

echo

echo "== Keyboard devices =="
$KANATA --list

echo

echo "== VirtualHID system extension =="
systemextensionsctl list 2>&1 | grep -i 'Karabiner-DriverKit-VirtualHIDDevice' || true

echo

echo "== LaunchDaemons =="
launchctl print system/org.pqrs.Karabiner-VirtualHIDDevice-Daemon 2>&1 | grep -E 'state =|pid =|last exit code|program =' || true
launchctl print system/homebrew.mxcl.kanata 2>&1 | grep -E 'state =|pid =|last exit code|program =' || true

echo

echo "== Processes =="
ps aux | grep -E '[k]anata|[K]arabiner-VirtualHIDDevice-Daemon' || true

echo

echo "== Recent Kanata wrapper log =="
tail -30 /opt/homebrew/var/log/kanata-wrapper.log 2>&1 || true

echo

echo "== Recent Kanata log =="
tail -80 /opt/homebrew/var/log/kanata.log 2>&1 || true
