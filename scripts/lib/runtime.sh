#!/usr/bin/env bash

PROJECT_BASE="/Library/Application Support/local.kanata-macos-setup"
PROJECT_LOG_DIR="/Library/Logs/local.kanata-macos-setup"
PROJECT_KANATA_LABEL="local.kanata-macos-setup"
PROJECT_VHID_LABEL="local.kanata-macos-setup.virtualhid"
PROJECT_KANATA_PLIST="/Library/LaunchDaemons/$PROJECT_KANATA_LABEL.plist"
PROJECT_VHID_PLIST="/Library/LaunchDaemons/$PROJECT_VHID_LABEL.plist"

project_bootout_if_present() {
  local label=$1 plist=$2
  local attempt
  if launchctl print "system/$label" >/dev/null 2>&1; then
    sudo launchctl bootout "system/$label" 2>/dev/null || true
  elif [[ -f "$plist" ]]; then
    sudo launchctl bootout system "$plist" 2>/dev/null || true
  fi
  # launchctl can return before a KeepAlive service disappears from its domain.
  # Allow the asynchronous bootout to complete before reporting failure.
  for ((attempt = 0; attempt < 100; attempt++)); do
    if ! launchctl print "system/$label" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  echo "Failed to unload service: $label" >&2
  return 1
}

remove_project_install() {
  project_bootout_if_present "$PROJECT_KANATA_LABEL" "$PROJECT_KANATA_PLIST"
  project_bootout_if_present "$PROJECT_VHID_LABEL" "$PROJECT_VHID_PLIST"
  sudo rm -f "$PROJECT_KANATA_PLIST" "$PROJECT_VHID_PLIST"
  sudo rm -rf "$PROJECT_BASE" "$PROJECT_LOG_DIR"
}
