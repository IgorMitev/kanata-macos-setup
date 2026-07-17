#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "$SCRIPT_DIR/versions.sh"

BASE="/Library/Application Support/com.igormitev.kanata"
KANATA="$BASE/bin/kanata"
CFG="$BASE/config/kanata.kbd"
SUPERVISOR="$BASE/libexec/supervisor.sh"
LOG_DIR="/Library/Logs/com.igormitev.kanata"
KANATA_LABEL="com.igormitev.kanata"
VHID_LABEL="com.igormitev.kanata.virtualhid"
KANATA_PLIST="/Library/LaunchDaemons/$KANATA_LABEL.plist"
VHID_PLIST="/Library/LaunchDaemons/$VHID_LABEL.plist"
VHID_DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"

pass_count=0
warn_count=0
fail_count=0

pass() { printf 'PASS  %s\n' "$*"; pass_count=$((pass_count + 1)); }
warn() { printf 'WARN  %s\n' "$*"; warn_count=$((warn_count + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; fail_count=$((fail_count + 1)); }

usage() {
  cat <<'USAGE'
Usage: ./scripts/verify.sh [--installed|--blank-slate]

  --installed     Verify the repository-managed installation (default).
  --blank-slate   Verify that Kanata, Karabiner-Elements, and VirtualHID are absent.

Required failures produce a nonzero exit status. Warnings are informational.
USAGE
}

mode=installed
case "${1:-}" in
  ""|--installed) ;;
  --blank-slate) mode=blank-slate ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }

service_is_running() {
  local label=$1 output
  output=$(launchctl print "system/$label" 2>/dev/null) || return 1
  grep -Eq 'state = (running|waiting)' <<<"$output"
}

process_matches() {
  pgrep -if "$1" >/dev/null 2>&1
}

extension_line() {
  systemextensionsctl list 2>&1 | grep -i 'org\.pqrs\.Karabiner-DriverKit-VirtualHIDDevice' || true
}

verify_platform() {
  if [[ "$(uname -s)" == Darwin ]]; then pass "macOS detected"; else fail "This setup supports macOS only"; fi
  if [[ "$(uname -m)" == arm64 ]]; then pass "Apple Silicon detected"; else fail "This repository supports Apple Silicon only"; fi
}

verify_installed() {
  local version plist_owner plist_mode ext pkg_version

  [[ -x "$KANATA" ]] && pass "Pinned Kanata binary exists" || fail "Missing executable: $KANATA"
  if [[ -x "$KANATA" ]]; then
    version=$("$KANATA" --version 2>&1 | head -1 || true)
    if grep -Fq "$KANATA_VERSION" <<<"$version"; then
      pass "Kanata version is $KANATA_VERSION"
    else
      fail "Expected Kanata $KANATA_VERSION; found: ${version:-unknown}"
    fi
  fi

  [[ -f "$CFG" ]] && pass "Kanata configuration exists" || fail "Missing configuration: $CFG"
  if [[ -x "$KANATA" && -f "$CFG" ]]; then
    if "$KANATA" --check --cfg "$CFG" >/dev/null 2>&1; then
      pass "Kanata configuration passes validation"
    else
      fail "Kanata configuration validation failed"
    fi
  fi

  [[ -x "$SUPERVISOR" ]] && pass "Supervisor is installed" || fail "Missing supervisor: $SUPERVISOR"
  if [[ -d "$BASE" ]]; then
    if [[ "$(stat -f '%Su' "$BASE" 2>/dev/null || true)" == root ]] && [[ ! -w "$BASE" ]]; then
      pass "Installation root is root-owned and not user-writable"
    else
      fail "Installation root must be root-owned and not user-writable: $BASE"
    fi
  fi

  for plist in "$KANATA_PLIST" "$VHID_PLIST"; do
    if [[ ! -f "$plist" ]]; then
      fail "Missing LaunchDaemon: $plist"
      continue
    fi
    if plutil -lint "$plist" >/dev/null 2>&1; then pass "Valid LaunchDaemon: $plist"; else fail "Invalid LaunchDaemon: $plist"; fi
    plist_owner=$(stat -f '%Su' "$plist" 2>/dev/null || true)
    plist_mode=$(stat -f '%Lp' "$plist" 2>/dev/null || true)
    if [[ "$plist_owner" == root && "$plist_mode" == 644 ]]; then
      pass "Safe ownership and mode on $plist"
    else
      fail "Expected root:644 on $plist; found ${plist_owner:-unknown}:${plist_mode:-unknown}"
    fi
  done

  service_is_running "$VHID_LABEL" && pass "VirtualHID service is loaded" || fail "VirtualHID service is not loaded/running"
  service_is_running "$KANATA_LABEL" && pass "Kanata service is loaded" || fail "Kanata service is not loaded/running"
  process_matches '/Library/Application Support/com\.igormitev\.kanata/bin/kanata' && pass "Repository Kanata process is running" || fail "Repository Kanata process is not running"

  [[ -x "$VHID_DAEMON" ]] && pass "VirtualHID daemon exists" || fail "Missing VirtualHID daemon"
  ext=$(extension_line)
  if [[ -z "$ext" ]]; then
    fail "VirtualHID system extension is not registered"
  elif grep -Eqi '\[activated enabled\]|activated[[:space:]]+enabled' <<<"$ext"; then
    pass "VirtualHID system extension is activated and enabled"
  else
    fail "VirtualHID extension is present but not activated and enabled: $ext"
  fi

  pkg_version=$(pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice 2>/dev/null | awk '/^version:/{print $2}' || true)
  if [[ "$pkg_version" == "$VHID_VERSION" ]]; then
    pass "VirtualHID package version is $VHID_VERSION"
  elif [[ -n "$pkg_version" ]]; then
    fail "Expected VirtualHID $VHID_VERSION; found $pkg_version"
  else
    fail "VirtualHID package receipt is missing"
  fi

  if [[ -d "$LOG_DIR" ]]; then
    pass "Log directory exists"
    if /usr/bin/grep -ERq 'driver connected: true|Starting kanata proper' "$LOG_DIR" 2>/dev/null; then
      pass "Kanata logs contain a successful startup marker"
    else
      warn "No successful Kanata startup marker found in $LOG_DIR yet"
    fi
  else
    warn "Log directory does not exist yet: $LOG_DIR"
  fi

  if [[ -x "$KANATA" ]]; then
    if "$KANATA" --list >/dev/null 2>&1; then
      pass "Kanata can enumerate keyboard devices"
    else
      warn "Kanata could not enumerate devices in this shell (permissions or no connected keyboard)"
    fi
  fi

  [[ ! -d /Applications/Karabiner-Elements.app ]] && pass "Karabiner-Elements application is absent" || fail "Karabiner-Elements remains installed"
  if pkgutil --pkg-info org.pqrs.Karabiner-Elements >/dev/null 2>&1; then
    fail "Karabiner-Elements package receipt remains"
  else
    pass "Karabiner-Elements package receipt is absent"
  fi
  process_matches '[K]arabiner-Elements|[K]arabiner-Core-Service|karabiner_console_user_server' && fail "Karabiner-Elements processes are running and may conflict" || pass "No Karabiner-Elements remapping processes are running"
}

verify_blank_slate() {
  local ext found=0
  local -a paths=(
    "$BASE"
    "$KANATA_PLIST"
    "$VHID_PLIST"
    "/Library/LaunchDaemons/homebrew.mxcl.kanata.plist"
    "/Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist"
    "/Applications/Karabiner-Elements.app"
    "/Applications/Karabiner-EventViewer.app"
    "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
    "/Library/Application Support/org.pqrs/Karabiner-Elements"
    "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    "$HOME/.config/kanata"
    "$HOME/.config/karabiner"
  )

  for path in "${paths[@]}"; do
    if [[ -e "$path" ]]; then fail "Still present: $path"; found=1; fi
  done
  [[ $found -eq 0 ]] && pass "No known Kanata/Karabiner installation files remain"

  for label in \
    "$KANATA_LABEL" \
    "$VHID_LABEL" \
    homebrew.mxcl.kanata \
    org.pqrs.Karabiner-VirtualHIDDevice-Daemon \
    org.pqrs.service.daemon.Karabiner-Core-Service \
    org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon; do
    if launchctl print "system/$label" >/dev/null 2>&1; then fail "Service remains loaded: $label"; else pass "Service absent: $label"; fi
  done

  process_matches '[k]anata|[K]arabiner-(Elements|Core-Service|VirtualHIDDevice)|karabiner_console_user_server' \
    && fail "Kanata or Karabiner processes are still running" \
    || pass "No Kanata or Karabiner processes are running"

  if command -v brew >/dev/null 2>&1 && brew list --formula kanata >/dev/null 2>&1; then
    fail "Homebrew Kanata formula remains installed"
  else
    pass "Homebrew Kanata formula is absent"
  fi

  if pkgutil --pkg-info org.pqrs.Karabiner-Elements >/dev/null 2>&1; then fail "Karabiner-Elements package receipt remains"; else pass "Karabiner-Elements receipt is absent"; fi
  if pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice >/dev/null 2>&1; then fail "VirtualHID package receipt remains"; else pass "VirtualHID receipt is absent"; fi

  ext=$(extension_line)
  if [[ -z "$ext" ]]; then
    pass "VirtualHID system extension is absent"
  elif grep -Eqi '\[activated enabled\]|activated[[:space:]]+enabled' <<<"$ext"; then
    fail "VirtualHID system extension remains active: $ext"
  else
    warn "VirtualHID extension is deactivated but still listed; restart macOS and verify again: $ext"
  fi
}

verify_platform
if [[ "$mode" == installed ]]; then verify_installed; else verify_blank_slate; fi

printf '\nSummary: %d PASS, %d WARN, %d FAIL\n' "$pass_count" "$warn_count" "$fail_count"
(( fail_count == 0 ))
