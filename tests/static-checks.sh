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
  scripts/archive-current.sh
  scripts/uninstall.sh
  scripts/verify.sh
  scripts/supervisor.sh
  scripts/versions.sh
  launchd/com.igormitev.kanata.plist
  launchd/com.igormitev.kanata.virtualhid.plist
  docs/clean-slate-install.md
  docs/acceptance-tests.md
)

for path in "${required[@]}"; do
  if [[ -f "$ROOT/$path" ]]; then
    pass "required file exists: $path"
  else
    fail "required file is missing: $path"
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
assert_contains scripts/install.sh '/Library/Application Support/com.igormitev.kanata' \
  "installer uses the stable system path"
if /usr/bin/grep -F -- '--release-grab-on-lock' "$ROOT/scripts/supervisor.sh" >/dev/null 2>&1; then
  fail "supervisor unexpectedly releases keyboard capture on lock"
else
  pass "supervisor preserves standard remapping on the lock screen"
fi
assert_contains kanata.kbd 'macos-continue-if-no-devs-found yes' \
  "config remains available when no physical keyboard is present"
assert_contains launchd/com.igormitev.kanata.plist '<string>com.igormitev.kanata</string>' \
  "Kanata launchd label is project-specific"
assert_contains launchd/com.igormitev.kanata.virtualhid.plist '<string>com.igormitev.kanata.virtualhid</string>' \
  "VirtualHID launchd label is project-specific"

for link in docs/clean-slate-install.md docs/acceptance-tests.md; do
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
