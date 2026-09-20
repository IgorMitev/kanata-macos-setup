#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=versions.sh
source "$SCRIPT_DIR/versions.sh"
# shellcheck source=lib/virtualhid-state.sh
source "$SCRIPT_DIR/lib/virtualhid-state.sh"
# shellcheck source=lib/legacy-inventory.sh
source "$SCRIPT_DIR/lib/legacy-inventory.sh"
SUPERVISOR_SOURCE="$SCRIPT_DIR/supervisor.sh"

BASE_DIR="/Library/Application Support/local.kanata-macos-setup"
BIN_DIR="$BASE_DIR/bin"
CONFIG_DIR="$BASE_DIR/config"
LIBEXEC_DIR="$BASE_DIR/libexec"
LOG_DIR="/Library/Logs/local.kanata-macos-setup"
KANATA_BIN="$BIN_DIR/kanata"
KANATA_CONFIG="$CONFIG_DIR/kanata.kbd"
SUPERVISOR="$LIBEXEC_DIR/supervisor.sh"
KANATA_LABEL="local.kanata-macos-setup"
VHID_LABEL="local.kanata-macos-setup.virtualhid"
KANATA_PLIST="/Library/LaunchDaemons/$KANATA_LABEL.plist"
VHID_PLIST="/Library/LaunchDaemons/$VHID_LABEL.plist"
VHID_RECEIPT="org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
KARABINER_RECEIPT="org.pqrs.Karabiner-Elements"
VHID_SUPPORT="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
VHID_DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
VHID_MANAGER_APP="/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
VHID_MANAGER="$VHID_MANAGER_APP/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

download() {
  local url="$1"
  local destination="$2"
  /usr/bin/curl --fail --location --retry 3 --retry-delay 2 \
    --proto '=https' --tlsv1.2 --output "$destination" "$url"
}

bootout_if_loaded() {
  local label="$1"
  local plist="$2"
  if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
    "${SUDO[@]}" /bin/launchctl bootout "system/$label"
  elif [[ -f "$plist" ]]; then
    "${SUDO[@]}" /bin/launchctl bootout system "$plist" >/dev/null 2>&1 || true
  fi
}

process_matches() {
  /usr/bin/pgrep -if "$1" >/dev/null 2>&1
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "This installer supports macOS only."
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || die "This installer supports Apple Silicon (arm64) only."
[[ "$EUID" -ne 0 ]] || die "Run this installer as the logged-in user, not with sudo. It will request administrator access when needed."

for command in awk curl grep install lipo mktemp pkgutil plutil shasum unzip; do
  require_command "$command"
done

[[ -f "$REPO_ROOT/kanata.kbd" ]] || die "Missing repository config: $REPO_ROOT/kanata.kbd"
[[ -f "$REPO_ROOT/launchd/local.kanata-macos-setup.plist" ]] || die "Missing Kanata launchd template."
[[ -f "$REPO_ROOT/launchd/local.kanata-macos-setup.virtualhid.plist" ]] || die "Missing VirtualHID launchd template."
[[ -f "$SUPERVISOR_SOURCE" ]] || die "Missing supervisor script: $SUPERVISOR_SOURCE"
/usr/bin/plutil -lint \
  "$REPO_ROOT/launchd/local.kanata-macos-setup.plist" \
  "$REPO_ROOT/launchd/local.kanata-macos-setup.virtualhid.plist"

require_command sudo
SUDO=(/usr/bin/sudo)

# The inventory in lib/legacy-inventory.sh is shared with purge-legacy.sh and
# verify.sh so all three agree on what counts as a legacy remapping component.
karabiner_conflicts=()
for legacy_app in "${LEGACY_KARABINER_APPS[@]}"; do
  legacy_path_present "$legacy_app" && karabiner_conflicts+=("application $legacy_app")
done
legacy_path_present "$LEGACY_KARABINER_SUPPORT" && karabiner_conflicts+=("support files")
while IFS= read -r service_file; do
  [[ -n "$service_file" ]] && karabiner_conflicts+=("service file $service_file")
done < <(legacy_service_plists_present)
while IFS= read -r loaded_service; do
  [[ -n "$loaded_service" ]] && karabiner_conflicts+=("loaded service $loaded_service")
done < <(legacy_services_loaded)
# The shared standalone Karabiner-VirtualHIDDevice-Daemon is not in the process
# inventory: this repository's own LaunchDaemon runs it, so matching it would
# make a rerun of this idempotent installer fail on a healthy system.
process_matches "$(legacy_process_regex)" && karabiner_conflicts+=("running processes")
if (( ${#karabiner_conflicts[@]} )); then
  die "Karabiner-Elements conflicts remain (${karabiner_conflicts[*]}). Complete the documented migration cleanup before installing."
fi

# A package receipt without any inventoried application, support files,
# service files, loaded services, or processes is harmless metadata left by an
# otherwise complete vendor removal.
# Do not make a clean installation fail on that state; forget it after sudo is
# authenticated below.
stale_karabiner_receipt=false
if /usr/sbin/pkgutil --pkg-info "$KARABINER_RECEIPT" >/dev/null 2>&1; then
  stale_karabiner_receipt=true
fi

if /bin/launchctl print system/homebrew.mxcl.kanata >/dev/null 2>&1; then
  die "Conflicting legacy service is still loaded: homebrew.mxcl.kanata. Complete the clean-slate removal and restart first."
fi

INSTALLED_VHID_VERSION="$(virtualhid_package_version "$VHID_RECEIPT")"
if ! VHID_EXTENSION="$(virtualhid_extension_lines /usr/bin/systemextensionsctl list)"; then
  die "Unable to query VirtualHID system-extension state; refusing to classify the installed driver."
fi
# Any registered, not-yet-terminated record counts as an installed component,
# including "[activated waiting for user]". A pending extension of an unknown or
# different version must go through the migration cleanup rather than being
# silently replaced; the same predicate drives purge and blank-slate verification.
VHID_EXTENSION_REGISTERED=false
if virtualhid_extension_requires_deactivation "$VHID_EXTENSION"; then
  VHID_EXTENSION_REGISTERED=true
fi
VHID_SUPPORT_PRESENT=false
VHID_MANAGER_PRESENT=false
VHID_DAEMON_EXECUTABLE=false
VHID_MANAGER_EXECUTABLE=false
legacy_path_present "$VHID_SUPPORT" && VHID_SUPPORT_PRESENT=true
legacy_path_present "$VHID_MANAGER_APP" && VHID_MANAGER_PRESENT=true
[[ -x "$VHID_DAEMON" ]] && VHID_DAEMON_EXECUTABLE=true
[[ -x "$VHID_MANAGER" ]] && VHID_MANAGER_EXECUTABLE=true
VHID_INSTALL_STATE="$(classify_virtualhid_install_state \
  "$INSTALLED_VHID_VERSION" "$VHID_VERSION" \
  "$VHID_SUPPORT_PRESENT" "$VHID_MANAGER_PRESENT" \
  "$VHID_DAEMON_EXECUTABLE" "$VHID_MANAGER_EXECUTABLE" \
  "$VHID_EXTENSION_REGISTERED")"
case "$VHID_INSTALL_STATE" in
  different-version)
    die "VirtualHID $INSTALLED_VHID_VERSION components are installed (extension: ${VHID_EXTENSION:-none}); this repository requires $VHID_VERSION. Run the documented migration cleanup before installing."
    ;;
  unreceipted-components)
    die "VirtualHID components remain without a package receipt (extension: ${VHID_EXTENSION:-none}). Run the documented migration cleanup before installing."
    ;;
  ready|install) ;;
  *) die "Unexpected VirtualHID installation state: $VHID_INSTALL_STATE" ;;
esac

WORK_DIR="$(/usr/bin/mktemp -d /tmp/local.kanata-macos-setup.install.XXXXXX)"
trap '/bin/rm -rf "$WORK_DIR"' EXIT

KANATA_ARCHIVE="$WORK_DIR/$KANATA_ARCHIVE_NAME"
VHID_PACKAGE="$WORK_DIR/$VHID_PACKAGE_NAME"
KANATA_EXTRACTED="$WORK_DIR/kanata"

log "Downloading Kanata $KANATA_VERSION for Apple Silicon..."
download "$KANATA_URL" "$KANATA_ARCHIVE"
[[ "$(sha256 "$KANATA_ARCHIVE")" == "$KANATA_SHA256" ]] || die "Kanata archive checksum mismatch."

/usr/bin/unzip -q "$KANATA_ARCHIVE" "$KANATA_BINARY_NAME" -d "$WORK_DIR"
/bin/mv "$WORK_DIR/$KANATA_BINARY_NAME" "$KANATA_EXTRACTED"
/bin/chmod 0755 "$KANATA_EXTRACTED"
[[ "$(/usr/bin/lipo -archs "$KANATA_EXTRACTED")" == "arm64" ]] || die "Kanata binary is not arm64-only."
"$KANATA_EXTRACTED" --version | /usr/bin/grep -F "$KANATA_VERSION" >/dev/null || die "Downloaded Kanata version is not $KANATA_VERSION."
"$KANATA_EXTRACTED" --check --cfg "$REPO_ROOT/kanata.kbd"

log "Downloading standalone VirtualHIDDevice $VHID_VERSION..."
download "$VHID_URL" "$VHID_PACKAGE"
[[ "$(sha256 "$VHID_PACKAGE")" == "$VHID_SHA256" ]] || die "VirtualHID package checksum mismatch."

PACKAGE_SIGNATURE="$(/usr/sbin/pkgutil --check-signature "$VHID_PACKAGE")" || die "VirtualHID package signature verification failed."
/usr/bin/grep -F "Developer ID Installer: Fumihiko Takayama ($VHID_TEAM_ID)" <<<"$PACKAGE_SIGNATURE" >/dev/null || die "VirtualHID package signer is not the expected developer."
/usr/bin/grep -F "Notarization: trusted by the Apple notary service" <<<"$PACKAGE_SIGNATURE" >/dev/null || die "VirtualHID package is not notarized."

log "Administrator access is required to install the verified artifacts and services."
if (( ${#SUDO[@]} )); then
  "${SUDO[@]}" -v
fi

if [[ "$stale_karabiner_receipt" == true ]]; then
  log "Forgetting stale Karabiner-Elements package receipt..."
  "${SUDO[@]}" /usr/sbin/pkgutil --forget "$KARABINER_RECEIPT" >/dev/null
fi
if [[ "$VHID_INSTALL_STATE" == install ]]; then
  log "Installing standalone VirtualHIDDevice $VHID_VERSION..."
  "${SUDO[@]}" /usr/sbin/installer -pkg "$VHID_PACKAGE" -target /
else
  log "Standalone VirtualHIDDevice $VHID_VERSION is already installed."
fi

[[ -x "$VHID_DAEMON" ]] || die "VirtualHID daemon is missing after package installation."
[[ -x "$VHID_MANAGER" ]] || die "VirtualHID manager is missing after package installation."

log "Requesting VirtualHID system-extension activation..."
"$VHID_MANAGER" forceActivate || true

"${SUDO[@]}" /usr/bin/install -d -o root -g wheel -m 0755 \
  "$BASE_DIR" "$BIN_DIR" "$CONFIG_DIR" "$LIBEXEC_DIR" "$LOG_DIR"
"${SUDO[@]}" /usr/bin/install -o root -g wheel -m 0755 "$KANATA_EXTRACTED" "$KANATA_BIN"
"${SUDO[@]}" /usr/bin/install -o root -g wheel -m 0644 "$REPO_ROOT/kanata.kbd" "$KANATA_CONFIG"
"${SUDO[@]}" /usr/bin/install -o root -g wheel -m 0755 "$SUPERVISOR_SOURCE" "$SUPERVISOR"
"${SUDO[@]}" /usr/bin/install -o root -g wheel -m 0644 \
  "$REPO_ROOT/launchd/local.kanata-macos-setup.plist" "$KANATA_PLIST"
"${SUDO[@]}" /usr/bin/install -o root -g wheel -m 0644 \
  "$REPO_ROOT/launchd/local.kanata-macos-setup.virtualhid.plist" "$VHID_PLIST"

/usr/bin/plutil -lint "$KANATA_PLIST" "$VHID_PLIST"
"${SUDO[@]}" "$KANATA_BIN" --check --cfg "$KANATA_CONFIG"

bootout_if_loaded "$KANATA_LABEL" "$KANATA_PLIST"
bootout_if_loaded "$VHID_LABEL" "$VHID_PLIST"

log "Starting the standalone VirtualHID daemon..."
"${SUDO[@]}" /bin/launchctl bootstrap system "$VHID_PLIST"
"${SUDO[@]}" /bin/launchctl kickstart -k "system/$VHID_LABEL"

log "Registering Kanata for the macOS input permission prompt..."
"$KANATA_BIN" --macos-request-permissions || true

log "Starting Kanata..."
"${SUDO[@]}" /bin/launchctl bootstrap system "$KANATA_PLIST"
"${SUDO[@]}" /bin/launchctl kickstart -k "system/$KANATA_LABEL"

cat <<'MSG'

Installation completed.

macOS may require you to approve the pqrs.org driver extension in:
  System Settings > General > Login Items & Extensions > Driver Extensions

If macOS shows an Input Monitoring or Accessibility prompt for Kanata, approve
the stable binary under /Library/Application Support/local.kanata-macos-setup/bin.
Restart macOS if the driver approval panel requests it, then run the repository
verification script.
MSG
