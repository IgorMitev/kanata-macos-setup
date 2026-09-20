#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "$SCRIPT_DIR/versions.sh"
# shellcheck source=lib/virtualhid-state.sh
source "$SCRIPT_DIR/lib/virtualhid-state.sh"
# shellcheck source=lib/legacy-inventory.sh
source "$SCRIPT_DIR/lib/legacy-inventory.sh"

BASE="/Library/Application Support/local.kanata-macos-setup"
KANATA="$BASE/bin/kanata"
CFG="$BASE/config/kanata.kbd"
SUPERVISOR="$BASE/libexec/supervisor.sh"
LOG_DIR="/Library/Logs/local.kanata-macos-setup"
KANATA_LABEL="local.kanata-macos-setup"
VHID_LABEL="local.kanata-macos-setup.virtualhid"
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

# Sets `ext` to the VirtualHID extension lines. Returns non-zero (and records a
# failure) when the system-extension query itself fails, so a broken query is
# never mistaken for an absent extension.
query_extension() {
  ext=""
  if ! ext=$(virtualhid_extension_lines systemextensionsctl list 2>/dev/null); then
    fail "Unable to query system-extension state with systemextensionsctl"
    return 1
  fi
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
  process_matches '^/Library/Application Support/local\.kanata-macos-setup/bin/kanata([[:space:]]|$)' && pass "Repository Kanata process is running" || fail "Repository Kanata process is not running"

  [[ -x "$VHID_DAEMON" ]] && pass "VirtualHID daemon exists" || fail "Missing VirtualHID daemon"
  if query_extension; then
    if [[ -z "$ext" ]]; then
      fail "VirtualHID system extension is not registered"
    elif virtualhid_extension_is_active "$ext"; then
      pass "VirtualHID system extension is activated and enabled"
    else
      fail "VirtualHID extension is present but not activated and enabled: $ext"
    fi
  fi

  pkg_version=$(virtualhid_package_version org.pqrs.Karabiner-DriverKit-VirtualHIDDevice)
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

  legacy_karabiner_files_present && fail "Karabiner-Elements application or support files remain" || pass "Karabiner-Elements application and support files are absent"
  if pkgutil --pkg-info org.pqrs.Karabiner-Elements >/dev/null 2>&1; then
    fail "Karabiner-Elements package receipt remains"
  else
    pass "Karabiner-Elements package receipt is absent"
  fi
  process_matches "$(legacy_process_regex)" && fail "Karabiner-Elements processes are running and may conflict" || pass "No Karabiner-Elements remapping processes are running"
  if [[ -n "$(legacy_services_loaded)" ]]; then
    fail "Legacy Karabiner services are loaded: $(legacy_services_loaded | tr '\n' ' ')"
  else
    pass "No legacy Karabiner services are loaded"
  fi
}

verify_blank_slate() {
  local ext found=0
  local -a paths=(
    "$BASE"
    "$KANATA_PLIST"
    "$VHID_PLIST"
    "/Library/LaunchDaemons/homebrew.mxcl.kanata.plist"
    "/Applications/Karabiner-Elements.app"
    "/Applications/Karabiner-EventViewer.app"
    "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
    "/Library/Application Support/org.pqrs/Karabiner-Elements"
    "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    "$HOME/.config/kanata"
    "$HOME/.config/karabiner"
  )

  for path in "${paths[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then fail "Still present: $path"; found=1; fi
  done
  # Same service-plist inventory that install.sh rejects, so a passing blank
  # slate is always an installable state.
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    fail "Still present: $path"; found=1
  done < <(legacy_service_plists_present)
  [[ $found -eq 0 ]] && pass "No known Kanata/Karabiner installation or service files remain"

  for label in "$KANATA_LABEL" "$VHID_LABEL" homebrew.mxcl.kanata "${LEGACY_DAEMON_LABELS[@]}"; do
    if legacy_daemon_is_loaded "$label"; then fail "Service remains loaded: system/$label"; else pass "Service absent: system/$label"; fi
  done
  for label in "${LEGACY_AGENT_LABELS[@]}"; do
    if legacy_agent_is_loaded "$label"; then fail "Agent remains loaded: gui/$label"; else pass "Agent absent: gui/$label"; fi
  done

  process_matches "$(legacy_process_regex kanata Karabiner-VirtualHIDDevice-Daemon)" \
    && fail "Kanata or Karabiner processes are still running" \
    || pass "No Kanata or Karabiner processes are running"

  if command -v brew >/dev/null 2>&1 && brew list --formula kanata >/dev/null 2>&1; then
    fail "Homebrew Kanata formula remains installed"
  else
    pass "Homebrew Kanata formula is absent"
  fi

  # Receipts are metadata; a vendor uninstall can leave them behind and the
  # installer tolerates them. The purge script forgets them on success.
  if pkgutil --pkg-info org.pqrs.Karabiner-Elements >/dev/null 2>&1; then warn "Karabiner-Elements package receipt remains (harmless without files; the installer forgets it)"; else pass "Karabiner-Elements receipt is absent"; fi
  if pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice >/dev/null 2>&1; then warn "VirtualHID package receipt remains (harmless without files)"; else pass "VirtualHID receipt is absent"; fi

  if query_extension; then
    if [[ -z "$ext" ]]; then
      pass "VirtualHID system extension is absent"
    elif virtualhid_extension_is_active "$ext"; then
      fail "VirtualHID system extension remains active: $ext"
    elif virtualhid_extension_requires_deactivation "$ext"; then
      fail "VirtualHID extension is still registered and was not deactivated: $ext"
    else
      warn "VirtualHID extension is terminated but still listed; restart macOS and verify again: $ext"
    fi
  fi
}

verify_platform
if [[ "$mode" == installed ]]; then verify_installed; else verify_blank_slate; fi

printf '\nSummary: %d PASS, %d WARN, %d FAIL\n' "$pass_count" "$warn_count" "$fail_count"
(( fail_count == 0 ))
