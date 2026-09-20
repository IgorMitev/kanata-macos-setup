#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/runtime.sh
source "$SCRIPT_DIR/../lib/runtime.sh"
# shellcheck source=../lib/virtualhid-state.sh
source "$SCRIPT_DIR/../lib/virtualhid-state.sh"
# shellcheck source=../lib/legacy-inventory.sh
source "$SCRIPT_DIR/../lib/legacy-inventory.sh"

LEGACY_KANATA_PLIST="/Library/LaunchDaemons/homebrew.mxcl.kanata.plist"
LEGACY_VHID_PLIST="/Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist"
LEGACY_VHID_CLIENT_PLIST="/Library/LaunchDaemons/org.pqrs.Karabiner-DriverKit-VirtualHIDDeviceClient.plist"
VHID_SUPPORT="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
VHID_DEACTIVATE="$VHID_SUPPORT/scripts/uninstall/deactivate_driver.sh"
VHID_REMOVE="$VHID_SUPPORT/scripts/uninstall/remove_files.sh"
VHID_MANAGER_APP="/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
VHID_MANAGER="$VHID_MANAGER_APP/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
KARABINER_UNINSTALL="/Library/Application Support/org.pqrs/Karabiner-Elements/uninstall.sh"

# Karabiner-Elements files or any Karabiner-owned service plist from the
# inventory shared with install.sh and verify.sh. Legacy VirtualHID daemon
# plists are excluded here because this script or the VirtualHID vendor
# remover owns them, not the Karabiner uninstaller.
karabiner_artifacts_are_present() {
  legacy_karabiner_files_present && return 0
  [[ -n "$(legacy_service_plists_present karabiner)" ]]
}

# Dangling symlinks count as present, matching install.sh and verify.sh.
vhid_artifacts_are_present() {
  legacy_path_present "$VHID_SUPPORT" || legacy_path_present "$VHID_MANAGER_APP" || \
    legacy_path_present "$LEGACY_VHID_CLIENT_PLIST"
}

usage() {
  cat <<'USAGE'
Usage: ./scripts/migration/purge-legacy.sh --archive ABSOLUTE_PATH

Requires a previously created and inspected archive, then removes the
repository install plus legacy Homebrew Kanata, Karabiner-Elements, and the
standalone VirtualHID package.
Any registered VirtualHID extension that is not already terminated is
deactivated with its vendor script before the vendor removal script is used.
Receipt-only remnants and terminated extension records need no deactivation.
A restart may be required.
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

if ! extension_state="$(virtualhid_extension_lines /usr/bin/systemextensionsctl list)"; then
  echo "Unable to query VirtualHID system-extension state; refusing to remove driver files." >&2
  exit 1
fi
# Pending states such as "[activated waiting for user]" still hold a staged
# driver that only the vendor manager can deactivate, so treat every
# not-yet-terminated record as requiring deactivation.
extension_registered=false
if virtualhid_extension_requires_deactivation "$extension_state"; then
  extension_registered=true
fi

manager_executable=false
deactivate_executable=false
vhid_artifacts_present=false
vhid_remover_available=false
[[ -x "$VHID_MANAGER" ]] && manager_executable=true
[[ -x "$VHID_DEACTIVATE" ]] && deactivate_executable=true
vhid_artifacts_are_present && vhid_artifacts_present=true
if [[ -x "$KARABINER_UNINSTALL" || -x "$VHID_REMOVE" ]]; then
  vhid_remover_available=true
fi
vhid_cleanup_state="$(classify_virtualhid_cleanup_state \
  "$extension_registered" "$manager_executable" "$deactivate_executable" \
  "$vhid_artifacts_present" "$vhid_remover_available")"
case "$vhid_cleanup_state" in
  active-missing-manager)
    installed_vhid_version="$(virtualhid_package_version org.pqrs.Karabiner-DriverKit-VirtualHIDDevice)"
    echo "VirtualHID ${installed_vhid_version:-unknown version} extension is registered (${extension_state}), but its signed manager is missing: $VHID_MANAGER" >&2
    echo "Reinstall the same VirtualHID version to restore the manager, rerun this cleanup, and restart when deactivation requests it." >&2
    exit 1
    ;;
  active-missing-deactivator)
    echo "VirtualHID extension is registered but its vendor deactivation script is missing." >&2
    echo "Reinstall the same official VirtualHID package, then rerun this cleanup." >&2
    exit 1
    ;;
  incomplete-files)
    echo "Incomplete VirtualHID files remain, but the vendor removal script is missing." >&2
    echo "Reinstall the same official VirtualHID package to restore its removal tools, then rerun this cleanup." >&2
    exit 1
    ;;
  ready) ;;
  *) echo "Unexpected VirtualHID cleanup state: $vhid_cleanup_state" >&2; exit 1 ;;
esac
if karabiner_artifacts_are_present && [[ ! -x "$KARABINER_UNINSTALL" ]]; then
  echo "Incomplete Karabiner-Elements files remain, but its vendor uninstaller is missing." >&2
  echo "Reinstall the same official Karabiner-Elements version to restore its uninstaller, then rerun this cleanup." >&2
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

# User agents run in the console user's gui domain and need no sudo.
bootout_agent_if_present() {
  local label=$1 domain
  domain="gui/$(id -u)"
  if launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$domain/$label" 2>/dev/null || true
  fi
  if launchctl print "$domain/$label" >/dev/null 2>&1; then
    echo "Failed to unload legacy agent: $label" >&2
    return 1
  fi
}

remove_project_install

# Stop every inventoried legacy service before invoking vendor uninstallers.
bootout_if_present homebrew.mxcl.kanata "$LEGACY_KANATA_PLIST"
for legacy_label in "${LEGACY_DAEMON_LABELS[@]}"; do
  bootout_if_present "$legacy_label" "/Library/LaunchDaemons/$legacy_label.plist"
done
for legacy_label in "${LEGACY_AGENT_LABELS[@]}"; do
  bootout_agent_if_present "$legacy_label"
done
# Only the pre-package legacy plists are removed directly; vendor uninstallers
# own the rest and the post-checks below confirm they are gone.
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
# Deactivate before the vendor removal script deletes the manager. Terminated
# extension records and receipt-only remnants do not require a manager.
if [[ "$extension_registered" == true ]]; then
  "$VHID_DEACTIVATE"
fi

# Karabiner's vendor uninstaller also invokes VirtualHID's vendor removal script.
if [[ -x "$KARABINER_UNINSTALL" ]]; then
  sudo "$KARABINER_UNINSTALL"
elif [[ -x "$VHID_REMOVE" ]]; then
  sudo "$VHID_REMOVE"
fi
if vhid_artifacts_are_present; then
  echo "VirtualHID vendor cleanup completed without removing all installed files." >&2
  echo "Package receipts were left intact; inspect the remaining files before retrying." >&2
  exit 1
fi
if karabiner_artifacts_are_present; then
  echo "Karabiner-Elements vendor cleanup completed without removing all installed files." >&2
  echo "Package receipts were left intact; inspect the remaining files before retrying." >&2
  exit 1
fi

# Older Karabiner uninstallers do not stop every menu/session helper after
# deleting their executables. Stop the exact inventoried remnants before
# verification (killall matches process names, not paths).
for process_name in "${LEGACY_PROCESS_NAMES[@]}"; do
  sudo killall "$process_name" >/dev/null 2>&1 || true
done

# Remove only archived user copies and receipts after vendor uninstallers finish.
rm -rf "$HOME/.config/kanata" "$HOME/.config/karabiner"
sudo rm -f /opt/homebrew/var/log/kanata.log /opt/homebrew/var/log/kanata-wrapper.log /var/log/karabiner-vhid-daemon.log
sudo pkgutil --forget org.pqrs.Karabiner-Elements >/dev/null 2>&1 || true
sudo pkgutil --forget org.pqrs.Karabiner-DriverKit-VirtualHIDDevice >/dev/null 2>&1 || true

echo "Clean-slate removal completed. Archive retained at: $archive_dir"
echo "Restart macOS, then run: ./scripts/verify.sh --blank-slate"
