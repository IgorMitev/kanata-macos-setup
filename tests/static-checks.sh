#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

assert_contains scripts/versions.sh 'KANATA_VERSION="1.12.0"' \
  "Kanata version is pinned to 1.12.0"
assert_contains scripts/versions.sh 'VHID_VERSION="6.2.0"' \
  "VirtualHIDDevice version is pinned to 6.2.0"
assert_contains scripts/install.sh 'Apple Silicon (arm64) only' \
  "installer rejects unsupported architectures"
assert_contains scripts/install.sh '/Library/Application Support/local.kanata-macos-setup' \
  "installer uses the stable system path"
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
