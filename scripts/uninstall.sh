#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/uninstall.sh

Removes only this repository's installed files and services. The standalone
VirtualHID package and extension, Karabiner-Elements, Homebrew, legacy Kanata,
and user configuration are left untouched.
USAGE
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "This repository supports Apple Silicon macOS only." >&2
  exit 1
fi

printf 'This will remove repository-managed Kanata files and services.\n'
read -r -p 'Type REMOVE to continue: ' answer
[[ "$answer" == REMOVE ]] || { echo "Aborted; nothing was changed."; exit 0; }

remove_project_install

echo "Repository-managed Kanata files and services were removed."
echo "The standalone VirtualHID package and extension were left installed."
