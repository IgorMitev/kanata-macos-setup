#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/runtime.sh
source "$SCRIPT_DIR/../lib/runtime.sh"

LEGACY_KANATA_PLIST="/Library/LaunchDaemons/homebrew.mxcl.kanata.plist"
LEGACY_VHID_PLIST="/Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist"
VHID_SUPPORT="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
VHID_DEACTIVATE="$VHID_SUPPORT/scripts/uninstall/deactivate_driver.sh"
VHID_REMOVE="$VHID_SUPPORT/scripts/uninstall/remove_files.sh"
KARABINER_UNINSTALL="/Library/Application Support/org.pqrs/Karabiner-Elements/uninstall.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/migration/purge-legacy.sh --archive ABSOLUTE_PATH

Requires a previously created and inspected archive, then removes the
repository install plus legacy Homebrew Kanata, Karabiner-Elements, and the
standalone VirtualHID package.
The VirtualHID extension is always deactivated with its vendor script before
the vendor removal script is used. A restart may be required.
USAGE
}

archive_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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

mode_description="repository-managed Kanata, Homebrew Kanata, Karabiner-Elements, and VirtualHID components after archiving"
[[ "$archive_dir" == /* ]] || { echo "--archive with an absolute path is required." >&2; exit 2; }
archive_dir="$(cd "$archive_dir" 2>/dev/null && pwd -P)" || {
  echo "Archive directory does not exist: $archive_dir" >&2
  exit 1
}
[[ -f "$archive_dir/README.txt" && -d "$archive_dir/diagnostics" ]] || {
  echo "Archive does not appear complete: $archive_dir" >&2
  echo "Run ./scripts/migration/archive-current.sh, inspect the result, then pass its path with --archive." >&2
  exit 1
}

for purge_target in \
  "$PROJECT_BASE" \
  "$PROJECT_LOG_DIR" \
  "$HOME/.config/kanata" \
  "$HOME/.config/karabiner" \
  "$HOME/Library/Logs/Karabiner" \
  "$VHID_SUPPORT" \
  "/Library/Application Support/org.pqrs/Karabiner-Elements"; do
  if [[ -e "$purge_target" ]]; then
    purge_target="$(cd "$purge_target" && pwd -P)"
  fi
  case "$archive_dir" in
    "$purge_target"|"$purge_target"/*)
      echo "Archive is inside a purge target: $archive_dir" >&2
      exit 1
      ;;
  esac
done

brew_prefix=""
brew_group=""
kanata_keg=""
if command -v brew >/dev/null 2>&1 && brew list --formula kanata >/dev/null 2>&1; then
  brew_prefix="$(brew --prefix)"
  brew_group="$(stat -f '%Sg' "$brew_prefix")"
  kanata_prefix="$(brew --prefix kanata)"
  kanata_keg="$(realpath "$kanata_prefix")"
  case "$kanata_keg" in
    "$brew_prefix"/Cellar/kanata/*) ;;
    *) echo "Refusing unexpected Homebrew Kanata path: $kanata_keg" >&2; exit 1 ;;
  esac
fi

if /usr/sbin/pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice >/dev/null 2>&1 && [[ ! -d "$VHID_SUPPORT" ]]; then
  echo "VirtualHID has a package receipt but its vendor support directory is missing." >&2
  exit 1
fi
if [[ -d "$VHID_SUPPORT" && ! -x "$VHID_DEACTIVATE" ]]; then
  echo "VirtualHID is installed but its vendor deactivation script is missing." >&2
  exit 1
fi
if { [[ -d /Applications/Karabiner-Elements.app ]] || \
     /usr/sbin/pkgutil --pkg-info org.pqrs.Karabiner-Elements >/dev/null 2>&1 || \
     [[ -d "/Library/Application Support/org.pqrs/Karabiner-Elements" ]]; } && \
   [[ ! -x "$KARABINER_UNINSTALL" ]]; then
  echo "Karabiner-Elements is installed but its vendor uninstaller is missing." >&2
  exit 1
fi
if [[ -d "$VHID_SUPPORT" && ! -x "$KARABINER_UNINSTALL" && ! -x "$VHID_REMOVE" ]]; then
  echo "VirtualHID is installed but its vendor removal script is missing." >&2
  exit 1
fi

printf 'This will remove %s.\n' "$mode_description"
printf 'Verified archive to retain: %s\n' "$archive_dir"
read -r -p 'Type PURGE to continue: ' answer
[[ "$answer" == PURGE ]] || { echo "Aborted; nothing was changed."; exit 0; }

bootout_if_present() {
  local label=$1 plist=$2
  if launchctl print "system/$label" >/dev/null 2>&1; then
    sudo launchctl bootout "system/$label" 2>/dev/null || true
  elif [[ -f "$plist" ]]; then
    sudo launchctl bootout system "$plist" 2>/dev/null || true
  fi
  if launchctl print "system/$label" >/dev/null 2>&1; then
    echo "Failed to unload legacy service: $label" >&2
    return 1
  fi
}

remove_project_install

# Stop legacy services before invoking vendor uninstallers.
bootout_if_present homebrew.mxcl.kanata "$LEGACY_KANATA_PLIST"
bootout_if_present org.pqrs.Karabiner-VirtualHIDDevice-Daemon "$LEGACY_VHID_PLIST"
bootout_if_present org.pqrs.service.daemon.Karabiner-Core-Service /nonexistent
bootout_if_present org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon /nonexistent
sudo rm -f "$LEGACY_KANATA_PLIST" "$LEGACY_VHID_PLIST"

if [[ -n "$kanata_keg" ]]; then
  # The legacy root LaunchDaemon can leave the Kanata keg and opt link owned by
  # root. Restore ownership only within the exact Homebrew Kanata target so
  # Homebrew can perform its own uninstall cleanly.
  sudo chown -R "$(id -un):$brew_group" "$kanata_keg"
  if [[ -L "$brew_prefix/opt/kanata" ]]; then
    sudo chown -h "$(id -un):$brew_group" "$brew_prefix/opt/kanata"
  fi
  brew uninstall --force kanata
fi

# This script must run as the console user because it drives the signed manager.
if [[ -x "$VHID_DEACTIVATE" ]]; then
  "$VHID_DEACTIVATE"
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
