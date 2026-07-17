#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=versions.sh
source "$SCRIPT_DIR/versions.sh"
SUPERVISOR_SOURCE="$SCRIPT_DIR/supervisor.sh"

BASE_DIR="/Library/Application Support/com.igormitev.kanata"
BIN_DIR="$BASE_DIR/bin"
CONFIG_DIR="$BASE_DIR/config"
LIBEXEC_DIR="$BASE_DIR/libexec"
LOG_DIR="/Library/Logs/com.igormitev.kanata"
KANATA_BIN="$BIN_DIR/kanata"
KANATA_CONFIG="$CONFIG_DIR/kanata.kbd"
SUPERVISOR="$LIBEXEC_DIR/supervisor.sh"
KANATA_LABEL="com.igormitev.kanata"
VHID_LABEL="com.igormitev.kanata.virtualhid"
KANATA_PLIST="/Library/LaunchDaemons/$KANATA_LABEL.plist"
VHID_PLIST="/Library/LaunchDaemons/$VHID_LABEL.plist"
VHID_RECEIPT="org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
VHID_DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
VHID_MANAGER="/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

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

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "This installer supports macOS only."
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || die "This installer supports Apple Silicon (arm64) only."
[[ "$EUID" -ne 0 ]] || die "Run this installer as the logged-in user, not with sudo. It will request administrator access when needed."

for command in awk curl grep install lipo mktemp pkgutil plutil shasum unzip; do
  require_command "$command"
done

[[ -f "$REPO_ROOT/kanata.kbd" ]] || die "Missing repository config: $REPO_ROOT/kanata.kbd"
[[ -f "$REPO_ROOT/launchd/com.igormitev.kanata.plist" ]] || die "Missing Kanata launchd template."
[[ -f "$REPO_ROOT/launchd/com.igormitev.kanata.virtualhid.plist" ]] || die "Missing VirtualHID launchd template."
[[ -f "$SUPERVISOR_SOURCE" ]] || die "Missing supervisor script: $SUPERVISOR_SOURCE"
/usr/bin/plutil -lint \
  "$REPO_ROOT/launchd/com.igormitev.kanata.plist" \
  "$REPO_ROOT/launchd/com.igormitev.kanata.virtualhid.plist"

require_command sudo
SUDO=(/usr/bin/sudo)

if [[ -d /Applications/Karabiner-Elements.app ]] || \
   /usr/sbin/pkgutil --pkg-info org.pqrs.Karabiner-Elements >/dev/null 2>&1; then
  die "Karabiner-Elements is installed. Complete the documented clean-slate removal before installing."
fi

for conflicting_label in \
  org.pqrs.service.daemon.Karabiner-Core-Service \
  org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon \
  homebrew.mxcl.kanata; do
  if /bin/launchctl print "system/$conflicting_label" >/dev/null 2>&1; then
    die "Conflicting legacy service is still loaded: $conflicting_label. Complete the clean-slate removal and restart first."
  fi
done

WORK_DIR="$(/usr/bin/mktemp -d /tmp/com.igormitev.kanata.install.XXXXXX)"
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

INSTALLED_VHID_VERSION="$(/usr/sbin/pkgutil --pkg-info "$VHID_RECEIPT" 2>/dev/null | /usr/bin/awk -F': ' '$1 == "version" {print $2}' || true)"
if [[ -n "$INSTALLED_VHID_VERSION" && "$INSTALLED_VHID_VERSION" != "$VHID_VERSION" ]]; then
  die "VirtualHID $INSTALLED_VHID_VERSION is installed; expected $VHID_VERSION. Complete the clean-slate removal before installing."
fi
if [[ "$INSTALLED_VHID_VERSION" != "$VHID_VERSION" || ! -x "$VHID_DAEMON" || ! -x "$VHID_MANAGER" ]]; then
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
  "$REPO_ROOT/launchd/com.igormitev.kanata.plist" "$KANATA_PLIST"
"${SUDO[@]}" /usr/bin/install -o root -g wheel -m 0644 \
  "$REPO_ROOT/launchd/com.igormitev.kanata.virtualhid.plist" "$VHID_PLIST"

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
the stable binary under /Library/Application Support/com.igormitev.kanata/bin.
Restart macOS if the driver approval panel requests it, then run the repository
verification script.
MSG
