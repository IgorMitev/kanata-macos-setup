#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/virtualhid-state.sh
source "$ROOT/scripts/lib/virtualhid-state.sh"
# shellcheck source=../scripts/lib/legacy-inventory.sh
source "$ROOT/scripts/lib/legacy-inventory.sh"
failures=0

pass() {
  printf 'PASS: %s\n' "$*"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

required=(
  README.md
  kanata.kbd
  scripts/install.sh
  scripts/uninstall.sh
  scripts/verify.sh
  scripts/supervisor.sh
  scripts/versions.sh
  scripts/lib/runtime.sh
  scripts/lib/virtualhid-state.sh
  scripts/lib/legacy-inventory.sh
  launchd/local.kanata-macos-setup.plist
  launchd/local.kanata-macos-setup.virtualhid.plist
  docs/installation.md
  docs/acceptance-tests.md
)

migration_required=(
  scripts/migration/archive-current.sh
  scripts/migration/purge-legacy.sh
  docs/migration-from-karabiner.md
)

for path in "${required[@]}"; do
  if [[ -f "$ROOT/$path" ]]; then
    pass "required file exists: $path"
  else
    fail "required file is missing: $path"
  fi
done

for path in "${migration_required[@]}"; do
  if [[ -f "$ROOT/$path" ]]; then
    pass "migration file exists: $path"
  else
    fail "migration file is missing: $path"
  fi
done

for script in \
  scripts/install.sh \
  scripts/uninstall.sh \
  scripts/verify.sh \
  scripts/supervisor.sh \
  scripts/lib/runtime.sh \
  scripts/migration/archive-current.sh \
  scripts/migration/purge-legacy.sh \
  tests/static-checks.sh; do
  if [[ -x "$ROOT/$script" ]]; then
    pass "script is executable: $script"
  else
    fail "script is not executable: $script"
  fi
done

while IFS= read -r -d '' script; do
  if bash -n "$script"; then
    pass "shell syntax: ${script#"$ROOT/"}"
  else
    fail "shell syntax: ${script#"$ROOT/"}"
  fi
done < <(find "$ROOT/scripts" "$ROOT/tests" -type f -name '*.sh' -print0)

if command -v plutil >/dev/null 2>&1; then
  while IFS= read -r -d '' plist; do
    if plutil -lint "$plist" >/dev/null; then
      pass "property list syntax: ${plist#"$ROOT/"}"
    else
      fail "property list syntax: ${plist#"$ROOT/"}"
    fi
  done < <(find "$ROOT/launchd" -type f \( -name '*.plist' -o -name '*.plist.template' \) -print0)
else
  fail "plutil is required to validate launchd property lists"
fi

if /usr/bin/grep -ER '/Users/|/home/' \
  "$ROOT/kanata.kbd" "$ROOT/scripts" "$ROOT/launchd" >/dev/null 2>&1; then
  fail "machine-specific home directory found in runtime files"
else
  pass "runtime files contain no machine-specific home directory"
fi

if /usr/bin/grep -ER 'brew install .*karabiner-elements|--cask karabiner-elements' \
  "$ROOT/scripts/install.sh" "$ROOT/scripts/supervisor.sh" "$ROOT/launchd" "$ROOT/kanata.kbd" >/dev/null 2>&1; then
  fail "runtime installation references Karabiner-Elements"
else
  pass "runtime installation does not require Karabiner-Elements"
fi

assert_contains() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  if /usr/bin/grep -F -- "$pattern" "$ROOT/$path" >/dev/null; then
    pass "$description"
  else
    fail "$description"
  fi
}

assert_result() {
  local expected="$1"
  local description="$2"
  shift 2
  local actual
  if actual="$("$@")" && [[ "$actual" == "$expected" ]]; then
    pass "$description"
  else
    fail "$description (expected $expected, got ${actual:-command failure})"
  fi
}

assert_contains scripts/versions.sh 'KANATA_VERSION="1.12.0"' \
  "Kanata version is pinned to 1.12.0"
assert_contains scripts/versions.sh 'VHID_VERSION="6.2.0"' \
  "VirtualHIDDevice version is pinned to 6.2.0"
assert_contains scripts/install.sh 'Apple Silicon (arm64) only' \
  "installer rejects unsupported architectures"
assert_contains scripts/install.sh '/Library/Application Support/local.kanata-macos-setup' \
  "installer uses the stable system path"
assert_contains scripts/install.sh 'Forgetting stale Karabiner-Elements package receipt' \
  "installer tolerates receipt-only Karabiner remnants"
for consumer in scripts/install.sh scripts/migration/purge-legacy.sh scripts/verify.sh; do
  assert_contains "$consumer" 'lib/legacy-inventory.sh"' \
    "$consumer uses the shared legacy component inventory"
done
assert_contains scripts/install.sh 'legacy_service_plists_present' \
  "installer rejects inactive legacy service files"
assert_contains scripts/install.sh 'legacy_services_loaded' \
  "installer rejects loaded legacy daemons and agents"
assert_contains scripts/verify.sh 'legacy_service_plists_present' \
  "blank-slate verification rejects the same service files as the installer"
assert_contains scripts/verify.sh 'LEGACY_AGENT_LABELS' \
  "blank-slate verification checks legacy user agents"
assert_contains scripts/migration/purge-legacy.sh 'bootout_agent_if_present "$legacy_label"' \
  "migration stops inventoried legacy user agents"

assert_inventory_contains() {
  local array_name="$1" needle="$2" item
  eval "set -- \"\${${array_name}[@]}\""
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      pass "$array_name lists $needle"
      return 0
    fi
  done
  fail "$array_name is missing $needle"
}
assert_inventory_contains LEGACY_DAEMON_LABELS org.pqrs.service.daemon.karabiner_grabber
assert_inventory_contains LEGACY_DAEMON_LABELS org.pqrs.service.daemon.Karabiner-Core-Service
assert_inventory_contains LEGACY_DAEMON_LABELS org.pqrs.Karabiner-VirtualHIDDevice-Daemon
assert_inventory_contains LEGACY_DAEMON_LABELS org.pqrs.Karabiner-DriverKit-VirtualHIDDeviceClient
assert_inventory_contains LEGACY_AGENT_LABELS org.pqrs.service.agent.karabiner_grabber
assert_inventory_contains LEGACY_AGENT_LABELS org.pqrs.service.agent.karabiner_console_user_server
assert_inventory_contains LEGACY_AGENT_LABELS org.pqrs.service.agent.Karabiner-Core-Service-rev2
# Pre-14 entries taken from upstream Karabiner-Elements src/scripts/uninstall_core.sh.
assert_inventory_contains LEGACY_DAEMON_LABELS org.pqrs.karabiner.karabiner_kextd
assert_inventory_contains LEGACY_AGENT_LABELS org.pqrs.karabiner.karabiner_session_monitor
assert_inventory_contains LEGACY_AGENT_LABELS org.pqrs.karabiner.NotificationWindow
if printf '%s\n' "${LEGACY_DAEMON_LABELS[@]}" | /usr/bin/grep -qx org.pqrs.karabiner.karabiner_session_monitor; then
  fail "org.pqrs.karabiner.karabiner_session_monitor is a LaunchAgent, not a LaunchDaemon"
else
  pass "pre-14 session monitor is classified as a LaunchAgent"
fi
assert_inventory_contains LEGACY_PROCESS_NAMES karabiner_grabber
assert_inventory_contains LEGACY_PROCESS_NAMES karabiner_observer
assert_inventory_contains LEGACY_PROCESS_NAMES karabiner_kextd
assert_inventory_contains LEGACY_PROCESS_NAMES Karabiner-Console-User-Server
assert_inventory_contains LEGACY_PROCESS_NAMES Karabiner-MultitouchExtension
assert_inventory_contains LEGACY_PROCESS_NAMES Karabiner-EventViewer
assert_inventory_contains LEGACY_PROCESS_NAMES Karabiner-DriverKit-VirtualHIDDeviceClient

symlink_fixture="$(/usr/bin/mktemp -d /tmp/kanata-static-checks.XXXXXX)"
/bin/ln -s "$symlink_fixture/missing-target" "$symlink_fixture/dangling"
if legacy_path_present "$symlink_fixture/dangling"; then
  pass "dangling symlinks count as present legacy paths"
else
  fail "dangling symlinks must count as present legacy paths"
fi
if legacy_path_present "$symlink_fixture/absent"; then
  fail "absent paths must not count as present legacy paths"
else
  pass "absent paths are not treated as present legacy paths"
fi
/bin/rm -rf "$symlink_fixture"
for consumer in scripts/install.sh scripts/migration/purge-legacy.sh; do
  if /usr/bin/grep -E '\[\[ -d "\$(legacy_app|LEGACY_KARABINER_SUPPORT|VHID_SUPPORT)"' "$ROOT/$consumer" >/dev/null; then
    fail "$consumer tests legacy paths with -d and would ignore dangling symlinks"
  else
    pass "$consumer does not test legacy paths with -d"
  fi
done
for shared in kanata Karabiner-VirtualHIDDevice-Daemon; do
  if printf '%s\n' "${LEGACY_PROCESS_NAMES[@]}" | /usr/bin/grep -qx "$shared"; then
    fail "LEGACY_PROCESS_NAMES must not list the shared process $shared"
  else
    pass "LEGACY_PROCESS_NAMES excludes the shared process $shared"
  fi
done

legacy_regex="$(legacy_process_regex)"
if printf '%s\n' '/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_grabber' | /usr/bin/grep -Eq "$legacy_regex"; then
  pass "legacy process regex matches karabiner_grabber"
else
  fail "legacy process regex should match karabiner_grabber"
fi
if printf '%s\n' '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon' | /usr/bin/grep -Eq "$legacy_regex"; then
  fail "legacy process regex must not match the shared VirtualHID daemon"
else
  pass "legacy process regex ignores the shared VirtualHID daemon"
fi
if printf '%s\n' '/Library/Application Support/local.kanata-macos-setup/bin/kanata --cfg x' | /usr/bin/grep -Eq "$(legacy_process_regex kanata)"; then
  pass "legacy process regex accepts extra names for blank-slate checks"
else
  fail "legacy process regex should accept extra names"
fi
if [[ "$(legacy_service_plists karabiner)" == *"org.pqrs.Karabiner-DriverKit-VirtualHIDDeviceClient"* ]]; then
  fail "Karabiner-scoped plist list must not include VirtualHID-owned plists"
else
  pass "Karabiner-scoped plist list excludes VirtualHID-owned plists"
fi
if [[ "$(legacy_service_plists)" == *"/Library/LaunchDaemons/org.pqrs.Karabiner-DriverKit-VirtualHIDDeviceClient.plist"* && \
      "$(legacy_service_plists)" == *"/Library/LaunchAgents/org.pqrs.service.agent.karabiner_grabber.plist"* ]]; then
  pass "full plist list derives daemon and agent paths"
else
  fail "full plist list should derive daemon and agent paths"
fi

assert_result install "clean machine installs VirtualHID" \
  classify_virtualhid_install_state "" 6.2.0 false false false false false
assert_result ready "complete pinned VirtualHID is reused" \
  classify_virtualhid_install_state 6.2.0 6.2.0 true true true true true
assert_result install "incomplete pinned VirtualHID is repaired" \
  classify_virtualhid_install_state 6.2.0 6.2.0 true true false true true
assert_result different-version "different installed VirtualHID requires migration" \
  classify_virtualhid_install_state 6.14.0 6.2.0 true true true true false
assert_result install "different-version receipt alone does not block installation" \
  classify_virtualhid_install_state 6.14.0 6.2.0 false false false false false
assert_result install "pinned receipt alone is repaired" \
  classify_virtualhid_install_state 6.2.0 6.2.0 false false false false false
assert_result unreceipted-components "registered (active or pending) unreceipted extension requires migration" \
  classify_virtualhid_install_state "" 6.2.0 false false false false true
assert_result different-version "registered extension of a different receipted version requires migration" \
  classify_virtualhid_install_state 6.14.0 6.2.0 false false false false true
assert_result ready "complete pinned VirtualHID with a pending or active extension is reused" \
  classify_virtualhid_install_state 6.2.0 6.2.0 true true true true true
assert_result ready "complete pinned VirtualHID with a terminated extension record is reused" \
  classify_virtualhid_install_state 6.2.0 6.2.0 true true true true false
assert_contains scripts/install.sh 'virtualhid_extension_requires_deactivation "$VHID_EXTENSION"' \
  "installer classifies pending extensions as registered components"

assert_result ready "receipt-only VirtualHID cleanup is harmless" \
  classify_virtualhid_cleanup_state false false false false false
assert_result ready "registered VirtualHID with complete vendor tools can be purged" \
  classify_virtualhid_cleanup_state true true true true true
assert_result active-missing-manager "registered VirtualHID requires its manager" \
  classify_virtualhid_cleanup_state true false true true true
assert_result active-missing-manager "registered VirtualHID without any files still requires its manager" \
  classify_virtualhid_cleanup_state true false false false false
assert_result active-missing-deactivator "registered VirtualHID requires its deactivation script" \
  classify_virtualhid_cleanup_state true true false true true
assert_result incomplete-files "incomplete inactive VirtualHID requires restored vendor tools" \
  classify_virtualhid_cleanup_state false false false true false
assert_result ready "inactive VirtualHID with vendor removal tools can be purged" \
  classify_virtualhid_cleanup_state false false false true true

assert_extension() {
  local predicate="$1" expected="$2" description="$3" fixture="$4"
  if "$predicate" "$fixture"; then
    [[ "$expected" == true ]] && pass "$description" || fail "$description"
  else
    [[ "$expected" == false ]] && pass "$description" || fail "$description"
  fi
}

ext_active=$'*\t*\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0)\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice\t[activated enabled]'
ext_waiting=$'*\t\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (6.2.0/6.2.0)\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice\t[activated waiting for user]'
ext_terminated=$'\t\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0)\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice\t[terminated waiting to uninstall on reboot]'
ext_terminated_then_active="$ext_terminated"$'\n'"$ext_active"

assert_extension virtualhid_extension_is_active true \
  "active VirtualHID extension output is recognized" "$ext_active"
assert_extension virtualhid_extension_is_active false \
  "extension awaiting user approval is not treated as active" "$ext_waiting"
assert_extension virtualhid_extension_is_active false \
  "terminated extension record is not treated as active" "$ext_terminated"
assert_extension virtualhid_extension_is_active false \
  "empty extension output is not treated as active" ""
assert_extension virtualhid_extension_is_active true \
  "active record after a terminated record is recognized" "$ext_terminated_then_active"

assert_extension virtualhid_extension_requires_deactivation true \
  "active extension requires deactivation" "$ext_active"
assert_extension virtualhid_extension_requires_deactivation true \
  "extension awaiting user approval still requires deactivation" "$ext_waiting"
assert_extension virtualhid_extension_requires_deactivation false \
  "terminated extension record needs no deactivation" "$ext_terminated"
assert_extension virtualhid_extension_requires_deactivation false \
  "empty extension output needs no deactivation" ""
assert_extension virtualhid_extension_requires_deactivation true \
  "active record after a terminated record requires deactivation" "$ext_terminated_then_active"

if virtualhid_extension_lines /usr/bin/false >/dev/null 2>&1; then
  fail "VirtualHID extension query failure is treated as absence"
else
  pass "VirtualHID extension query failure fails closed"
fi
if no_match="$(virtualhid_extension_lines /bin/echo '0 extension(s)')" && [[ -z "$no_match" ]]; then
  pass "VirtualHID extension query with no matching record succeeds with empty output"
else
  fail "VirtualHID extension query with no matching record should succeed with empty output"
fi
if extension_lines="$(virtualhid_extension_lines /usr/bin/printf '%s\n' 'header' "$ext_terminated" "$ext_active")" && \
   [[ "$extension_lines" == "$ext_terminated_then_active" ]]; then
  pass "VirtualHID extension query keeps every matching record"
else
  fail "VirtualHID extension query should keep every matching record"
fi
if [[ "$(virtualhid_package_version org.example.no-such-receipt.$$)" == "" ]]; then
  pass "missing package receipt yields an empty version"
else
  fail "missing package receipt should yield an empty version"
fi

assert_contains scripts/migration/purge-legacy.sh 'if [[ "$extension_registered" == true ]]; then' \
  "migration deactivates every registered, non-terminated VirtualHID extension"
if /usr/bin/grep -E 'process_matches .*Karabiner-VirtualHIDDevice-Daemon' "$ROOT/scripts/install.sh" >/dev/null; then
  fail "installer treats the shared VirtualHID daemon as a Karabiner conflict (breaks reruns)"
else
  pass "installer does not treat its own VirtualHID daemon as a conflict"
fi
assert_contains scripts/verify.sh 'source "$SCRIPT_DIR/lib/virtualhid-state.sh"' \
  "verifier uses the shared fail-closed extension query"
assert_contains scripts/uninstall.sh 'source "$SCRIPT_DIR/lib/runtime.sh"' \
  "normal uninstaller uses shared runtime removal logic"
assert_contains scripts/migration/purge-legacy.sh 'source "$SCRIPT_DIR/../lib/runtime.sh"' \
  "legacy purge uses shared runtime removal logic"
if /usr/bin/grep -F -- '--release-grab-on-lock' "$ROOT/scripts/supervisor.sh" >/dev/null 2>&1; then
  fail "supervisor unexpectedly releases keyboard capture on lock"
else
  pass "supervisor preserves standard remapping on the lock screen"
fi
assert_contains kanata.kbd 'macos-continue-if-no-devs-found yes' \
  "config remains available when no physical keyboard is present"
assert_contains launchd/local.kanata-macos-setup.plist '<string>local.kanata-macos-setup</string>' \
  "Kanata launchd label is project-specific"
assert_contains launchd/local.kanata-macos-setup.virtualhid.plist '<string>local.kanata-macos-setup.virtualhid</string>' \
  "VirtualHID launchd label is project-specific"

personal_namespace='igor''mitev'
if /usr/bin/grep -ER "$personal_namespace|com\.$personal_namespace" \
  "$ROOT/README.md" "$ROOT/docs" "$ROOT/scripts" "$ROOT/launchd" "$ROOT/tests" "$ROOT/kanata.kbd" >/dev/null 2>&1; then
  fail "personal namespace remains in current repository files"
else
  pass "current repository files use a neutral namespace"
fi

for link in docs/installation.md docs/migration-from-karabiner.md docs/acceptance-tests.md; do
  if /usr/bin/grep -F "]($link)" "$ROOT/README.md" >/dev/null; then
    pass "README links to $link"
  else
    fail "README does not link to $link"
  fi
done

if (( failures > 0 )); then
  printf '\n%d static check(s) failed. No system changes were made.\n' "$failures" >&2
  exit 1
fi

printf '\nAll static checks passed. No system changes were made.\n'
