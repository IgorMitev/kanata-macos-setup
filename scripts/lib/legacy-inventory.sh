#!/usr/bin/env bash

# Single inventory of legacy Karabiner-Elements and VirtualHID remapping
# components. install.sh, purge-legacy.sh, and verify.sh must all use these
# lists so that a state verify accepts is never a state install rejects, and so
# that purge stops and removes everything the other two check for.

# Karabiner-Elements LaunchDaemons (system domain), owned by the Karabiner
# vendor uninstaller. Covers current 14/15 labels and the pre-14
# org.pqrs.karabiner labels that upstream src/scripts/uninstall_core.sh removes.
LEGACY_KARABINER_DAEMON_LABELS=(
  org.pqrs.service.daemon.Karabiner-Core-Service
  org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon
  org.pqrs.service.daemon.karabiner_grabber
  org.pqrs.karabiner.karabiner_grabber
  org.pqrs.karabiner.karabiner_kextd
  org.pqrs.karabiner.karabiner_observer
)

# Legacy standalone VirtualHID LaunchDaemons, owned by purge-legacy.sh (the
# pre-package daemon plist) or by the VirtualHID vendor removal script (the
# old client daemon).
LEGACY_VHID_DAEMON_LABELS=(
  org.pqrs.Karabiner-VirtualHIDDevice-Daemon
  org.pqrs.Karabiner-DriverKit-VirtualHIDDeviceClient
)

LEGACY_DAEMON_LABELS=(
  "${LEGACY_KARABINER_DAEMON_LABELS[@]}"
  "${LEGACY_VHID_DAEMON_LABELS[@]}"
)

# LaunchAgents (per-user gui domain), current and pre-14 labels from upstream
# uninstall_core.sh.
LEGACY_AGENT_LABELS=(
  org.pqrs.service.agent.Karabiner-Core-Service
  org.pqrs.service.agent.Karabiner-Core-Service-rev2
  org.pqrs.service.agent.Karabiner-Console-User-Server
  org.pqrs.service.agent.karabiner_console_user_server
  org.pqrs.service.agent.Karabiner-Menu
  org.pqrs.service.agent.Karabiner-NotificationWindow
  org.pqrs.service.agent.Karabiner-MultitouchExtension
  org.pqrs.service.agent.karabiner_grabber
  org.pqrs.service.agent.karabiner_session_monitor
  org.pqrs.karabiner.karabiner_console_user_server
  org.pqrs.karabiner.karabiner_session_monitor
  org.pqrs.karabiner.NotificationWindow
  org.pqrs.karabiner.agent.karabiner_grabber
  org.pqrs.karabiner.agent.karabiner_observer
)

# Executable basenames of legacy remapping processes, matching the killall
# list in upstream uninstall.sh plus pre-14 helpers. The shared standalone
# Karabiner-VirtualHIDDevice-Daemon and kanata are intentionally not listed:
# this repository runs both, so callers add them only where appropriate.
LEGACY_PROCESS_NAMES=(
  Karabiner-Elements
  Karabiner-EventViewer
  Karabiner-Core-Service
  Karabiner-Console-User-Server
  Karabiner-Menu
  Karabiner-MultitouchExtension
  Karabiner-NotificationWindow
  Karabiner-DriverKit-VirtualHIDDeviceClient
  karabiner_grabber
  karabiner_kextd
  karabiner_observer
  karabiner_session_monitor
  karabiner_console_user_server
)

LEGACY_KARABINER_APPS=(
  /Applications/Karabiner-Elements.app
  /Applications/Karabiner-EventViewer.app
)
LEGACY_KARABINER_SUPPORT="/Library/Application Support/org.pqrs/Karabiner-Elements"

# Print the plist paths derived from the label inventories. With "karabiner"
# as the first argument, only Karabiner-Elements-owned plists are printed.
legacy_service_plists() {
  local scope=${1:-all} label
  local -a daemon_labels
  if [[ "$scope" == karabiner ]]; then
    daemon_labels=("${LEGACY_KARABINER_DAEMON_LABELS[@]}")
  else
    daemon_labels=("${LEGACY_DAEMON_LABELS[@]}")
  fi
  for label in "${daemon_labels[@]}"; do
    printf '%s\n' "/Library/LaunchDaemons/$label.plist"
  done
  for label in "${LEGACY_AGENT_LABELS[@]}"; do
    printf '%s\n' "/Library/LaunchAgents/$label.plist"
  done
}

# Build an anchored pgrep -f regex from process basenames. Extra names may be
# appended by callers (for example the VirtualHID daemon during blank-slate
# verification).
legacy_process_regex() {
  local names="" name
  for name in "${LEGACY_PROCESS_NAMES[@]}" "$@"; do
    names="${names:+$names|}$name"
  done
  printf '^/.*\\/(%s)([[:space:]]|$)' "$names"
}

legacy_daemon_is_loaded() {
  /bin/launchctl print "system/$1" >/dev/null 2>&1
}

legacy_agent_is_loaded() {
  /bin/launchctl print "gui/$(/usr/bin/id -u)/$1" >/dev/null 2>&1
}

# Print one line per present legacy service plist (regular file or symlink).
# Accepts the same optional scope as legacy_service_plists.
legacy_service_plists_present() {
  local plist
  while IFS= read -r plist; do
    legacy_path_present "$plist" && printf '%s\n' "$plist"
  done < <(legacy_service_plists "${1:-all}")
  return 0
}

# Print one line per loaded legacy daemon or agent label.
legacy_services_loaded() {
  local label
  for label in "${LEGACY_DAEMON_LABELS[@]}"; do
    legacy_daemon_is_loaded "$label" && printf 'system/%s\n' "$label"
  done
  for label in "${LEGACY_AGENT_LABELS[@]}"; do
    legacy_agent_is_loaded "$label" && printf 'gui/%s\n' "$label"
  done
  return 0
}

# True when the path exists in any form, including a dangling symlink. Used by
# install, purge, and verify alike so that a broken symlink is never ignored by
# one script and rejected by another.
legacy_path_present() {
  [[ -e "$1" || -L "$1" ]]
}

# True when any Karabiner-Elements application bundle or support tree exists.
legacy_karabiner_files_present() {
  local app
  for app in "${LEGACY_KARABINER_APPS[@]}"; do
    legacy_path_present "$app" && return 0
  done
  legacy_path_present "$LEGACY_KARABINER_SUPPORT"
}
