#!/usr/bin/env bash
set -euo pipefail

BASE="/Library/Application Support/com.igormitev.kanata"
LOG_DIR="/Library/Logs/com.igormitev.kanata"
KANATA_LABEL="com.igormitev.kanata"
VHID_LABEL="com.igormitev.kanata.virtualhid"
KANATA_PLIST="/Library/LaunchDaemons/$KANATA_LABEL.plist"
VHID_PLIST="/Library/LaunchDaemons/$VHID_LABEL.plist"
LEGACY_KANATA_PLIST="/Library/LaunchDaemons/homebrew.mxcl.kanata.plist"
LEGACY_VHID_PLIST="/Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist"
VHID_SUPPORT="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
VHID_DEACTIVATE="$VHID_SUPPORT/scripts/uninstall/deactivate_driver.sh"
VHID_REMOVE="$VHID_SUPPORT/scripts/uninstall/remove_files.sh"
KARABINER_UNINSTALL="/Library/Application Support/org.pqrs/Karabiner-Elements/uninstall.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/uninstall.sh [--purge --archive ABSOLUTE_PATH]

Without --purge, removes only this repository's installed files and services.

--purge requires a previously created and inspected archive, then removes the
repository install plus legacy Homebrew Kanata, Karabiner-Elements, and the standalone VirtualHID package.
The VirtualHID extension is always deactivated with its vendor script before
the vendor removal script is used. A restart may be required.
USAGE
}

purge=0
archive_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) purge=1 ;;
    --archive)
      [[ $# -ge 2 ]] || { echo "--archive requires a path" >&2; exit 2; }
      archive_dir=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "This repository supports Apple Silicon macOS only." >&2
  exit 1
fi

mode_description="repository-managed Kanata files and services"
if (( purge )); then
  mode_description="ALL Kanata, Karabiner-Elements, and VirtualHID components after archiving"
  [[ "$archive_dir" == /* ]] || { echo "--purge requires --archive with an absolute path." >&2; exit 2; }
  [[ -f "$archive_dir/README.txt" && -d "$archive_dir/diagnostics" ]] || {
    echo "Archive does not appear complete: $archive_dir" >&2
    echo "Run ./scripts/archive-current.sh, inspect the result, then pass its path with --archive." >&2
    exit 1
  }
elif [[ -n "$archive_dir" ]]; then
  echo "--archive is valid only with --purge." >&2
  exit 2
fi

printf 'This will remove %s.\n' "$mode_description"
if (( purge )); then
  printf 'Verified archive to retain: %s\n' "$archive_dir"
  read -r -p 'Type PURGE to continue: ' answer
  [[ "$answer" == PURGE ]] || { echo "Aborted; nothing was changed."; exit 0; }
else
  read -r -p 'Type REMOVE to continue: ' answer
  [[ "$answer" == REMOVE ]] || { echo "Aborted; nothing was changed."; exit 0; }
fi

bootout_if_present() {
  local label=$1 plist=$2
  if launchctl print "system/$label" >/dev/null 2>&1; then
    sudo launchctl bootout "system/$label" 2>/dev/null || true
  elif [[ -f "$plist" ]]; then
    sudo launchctl bootout system "$plist" 2>/dev/null || true
  fi
}

remove_repo_install() {
  bootout_if_present "$KANATA_LABEL" "$KANATA_PLIST"
  bootout_if_present "$VHID_LABEL" "$VHID_PLIST"
  sudo rm -f "$KANATA_PLIST" "$VHID_PLIST"
  sudo rm -rf "$BASE" "$LOG_DIR"
}

remove_repo_install

if (( ! purge )); then
  echo "Repository-managed Kanata files and services were removed."
  echo "Karabiner-Elements, VirtualHID, legacy Kanata, and user configuration were left untouched."
  exit 0
fi

# Stop legacy services before invoking vendor uninstallers.
bootout_if_present homebrew.mxcl.kanata "$LEGACY_KANATA_PLIST"
bootout_if_present org.pqrs.Karabiner-VirtualHIDDevice-Daemon "$LEGACY_VHID_PLIST"
bootout_if_present org.pqrs.service.daemon.Karabiner-Core-Service /nonexistent
bootout_if_present org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon /nonexistent
sudo rm -f "$LEGACY_KANATA_PLIST" "$LEGACY_VHID_PLIST"

if command -v brew >/dev/null 2>&1 && brew list --formula kanata >/dev/null 2>&1; then
  # The legacy root LaunchDaemon can leave the Kanata keg and opt link owned by
  # root. Restore ownership only within the exact Homebrew Kanata target so
  # Homebrew can perform its own uninstall cleanly.
  brew_prefix="$(brew --prefix)"
  brew_group="$(stat -f '%Sg' "$brew_prefix")"
  kanata_prefix="$(brew --prefix kanata)"
  kanata_keg="$(realpath "$kanata_prefix")"
  case "$kanata_keg" in
    "$brew_prefix"/Cellar/kanata/*) ;;
    *) echo "Refusing unexpected Homebrew Kanata path: $kanata_keg" >&2; exit 1 ;;
  esac
  sudo chown -R "$(id -un):$brew_group" "$kanata_keg"
  if [[ -L "$brew_prefix/opt/kanata" ]]; then
    sudo chown -h "$(id -un):$brew_group" "$brew_prefix/opt/kanata"
  fi
  brew uninstall --force kanata
fi

# This script must run as the console user because it drives the signed manager.
if [[ -x "$VHID_DEACTIVATE" ]]; then
  "$VHID_DEACTIVATE"
elif [[ -d "$VHID_SUPPORT" ]]; then
  echo "VirtualHID is installed but its vendor deactivation script is missing." >&2
  echo "Refusing to remove a potentially live DriverKit extension." >&2
  exit 1
fi

# Karabiner's vendor uninstaller also invokes VirtualHID's vendor removal script.
if [[ -x "$KARABINER_UNINSTALL" ]]; then
  sudo "$KARABINER_UNINSTALL"
elif [[ -x "$VHID_REMOVE" ]]; then
  sudo "$VHID_REMOVE"
fi

# Older Karabiner uninstallers do not stop every menu/session helper after
# deleting their executables. Stop those exact remnants before verification.
for process_name in \
  Karabiner-Menu \
  Karabiner-NotificationWindow \
  karabiner_session_monitor; do
  sudo killall "$process_name" >/dev/null 2>&1 || true
done

# Remove only archived user copies and receipts after vendor uninstallers finish.
rm -rf "$HOME/.config/kanata" "$HOME/.config/karabiner"
sudo rm -f /opt/homebrew/var/log/kanata.log /opt/homebrew/var/log/kanata-wrapper.log /var/log/karabiner-vhid-daemon.log
sudo pkgutil --forget org.pqrs.Karabiner-Elements >/dev/null 2>&1 || true
sudo pkgutil --forget org.pqrs.Karabiner-DriverKit-VirtualHIDDevice >/dev/null 2>&1 || true

echo "Clean-slate removal completed. Archive retained at: $archive_dir"
echo "Restart macOS, then run: ./scripts/verify.sh --blank-slate"
