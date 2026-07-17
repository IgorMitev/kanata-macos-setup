#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/archive-current.sh [--output ABSOLUTE_PATH]

Copies current Kanata/Karabiner configuration, relevant service definitions,
logs, package state, extension state, and process diagnostics. This script does
not stop services or remove anything.
USAGE
}

output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 2; }
      output=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$(uname -s)" != Darwin ]]; then
  echo "This archive helper supports macOS only." >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  output="$HOME/Documents/Kanata Setup Archives/$(date '+%Y%m%d-%H%M%S')"
fi
[[ "$output" == /* ]] || { echo "Archive output must be an absolute path." >&2; exit 2; }
case "$output" in
  /|/Applications|/Library|/System|/Users|"$HOME")
    echo "Refusing unsafe archive output path: $output" >&2
    exit 2
    ;;
esac
[[ ! -e "$output" ]] || { echo "Archive output already exists: $output" >&2; exit 1; }

mkdir -p "$output/files" "$output/diagnostics"

copy_if_present() {
  local source=$1 relative=${1#/} destination="$output/files/${1#/}"
  [[ -e "$source" ]] || return 0
  mkdir -p "$(dirname "$destination")"
  if [[ -r "$source" ]]; then
    ditto "$source" "$destination"
  else
    sudo ditto "$source" "$destination"
  fi
  printf '%s\n' "$source" >> "$output/diagnostics/copied-paths.txt"
}

run_capture() {
  local name=$1
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"$output/diagnostics/$name.txt" 2>&1 || true
}

paths=(
  "$HOME/.config/kanata"
  "$HOME/.config/karabiner"
  "$HOME/Library/Logs/Karabiner"
  "$HOME/Library/Preferences/org.pqrs.Karabiner-Elements.Settings.plist"
  "$HOME/Library/Preferences/org.pqrs.Karabiner-Menu.plist"
  "$HOME/Library/Preferences/org.pqrs.Karabiner-Updater.plist"
  "$HOME/Library/Preferences/org.pqrs.Karabiner-EventViewer.plist"
  "/Library/Application Support/com.igormitev.kanata"
  "/Library/Logs/com.igormitev.kanata"
  "/Library/LaunchDaemons/com.igormitev.kanata.plist"
  "/Library/LaunchDaemons/com.igormitev.kanata.virtualhid.plist"
  "/Library/LaunchDaemons/homebrew.mxcl.kanata.plist"
  "/Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist"
  "/opt/homebrew/var/log/kanata.log"
  "/opt/homebrew/var/log/kanata-wrapper.log"
  "/var/log/karabiner-vhid-daemon.log"
)
for path in "${paths[@]}"; do copy_if_present "$path"; done

run_capture date date -u '+%Y-%m-%dT%H:%M:%SZ'
run_capture macos sw_vers
run_capture hardware uname -a
run_capture system_extensions systemextensionsctl list
run_capture processes ps aux
run_capture package_receipts pkgutil --pkgs
run_capture karabiner_elements_package pkgutil --pkg-info org.pqrs.Karabiner-Elements
run_capture virtualhid_package pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice
run_capture kanata_service launchctl print system/com.igormitev.kanata
run_capture kanata_legacy_service launchctl print system/homebrew.mxcl.kanata
run_capture virtualhid_service launchctl print system/com.igormitev.kanata.virtualhid
run_capture virtualhid_legacy_service launchctl print system/org.pqrs.Karabiner-VirtualHIDDevice-Daemon
run_capture karabiner_core_service launchctl print system/org.pqrs.service.daemon.Karabiner-Core-Service
run_capture karabiner_vhid_vendor_service launchctl print system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon
if command -v brew >/dev/null 2>&1; then
  run_capture brew_kanata brew list --versions kanata
fi

kanata_candidate=""
for candidate in \
  "/Library/Application Support/com.igormitev.kanata/bin/kanata" \
  /opt/homebrew/opt/kanata/bin/kanata \
  /opt/homebrew/bin/kanata; do
  if [[ -x "$candidate" ]]; then kanata_candidate=$candidate; break; fi
done
if [[ -n "$kanata_candidate" ]]; then
  run_capture kanata_version "$kanata_candidate" --version
  run_capture kanata_devices "$kanata_candidate" --list
fi

if command -v shasum >/dev/null 2>&1; then
  find "$output/files" -type f -print0 | sort -z | xargs -0 shasum -a 256 > "$output/diagnostics/SHA256SUMS" || true
fi

# Root-only source files may retain root ownership after sudo ditto. Make the
# completed archive readable by the user who deliberately created it.
if find "$output" ! -user "$(id -un)" -print -quit | grep -q .; then
  sudo chown -R "$(id -u):$(id -g)" "$output"
fi

cat > "$output/README.txt" <<EOF
Kanata/Karabiner pre-removal archive
Created: $(date '+%Y-%m-%d %H:%M:%S %Z')
Host: $(scutil --get ComputerName 2>/dev/null || hostname)

This archive is retained for rollback and diagnosis. Do not delete it until the
replacement installation and lifecycle tests have passed and deletion is
explicitly approved.
EOF

echo "Archive created: $output"
