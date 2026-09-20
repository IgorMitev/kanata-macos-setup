#!/usr/bin/env bash

# Print the version recorded in a package receipt, or nothing when the receipt
# is absent. Never fails, so callers can use it under set -e/pipefail.
virtualhid_package_version() {
  /usr/sbin/pkgutil --pkg-info "$1" 2>/dev/null |
    /usr/bin/awk -F': ' '$1 == "version" {print $2}' || true
}

# Run the given system-extension query and print only the VirtualHID lines.
# Fails (non-zero) when the query itself fails so callers can refuse to guess.
virtualhid_extension_lines() {
  local output
  output="$("$@" 2>&1)" || {
    printf '%s\n' "$output" >&2
    return 1
  }
  /usr/bin/grep -i 'org\.pqrs\.Karabiner-DriverKit-VirtualHIDDevice' <<<"$output" || true
}

# True when a listed record is fully activated and enabled (driver is live).
virtualhid_extension_is_active() {
  /usr/bin/grep -Eqi '\[activated enabled\]|activated[[:space:]]+enabled' <<<"$1"
}

# True when a record is listed that has not yet been terminated, including
# pending states such as "[activated waiting for user]". Such records still
# need the vendor manager to deactivate them before its files are removed.
virtualhid_extension_requires_deactivation() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! /usr/bin/grep -Eqi '\[terminated' <<<"$line"; then
      return 0
    fi
  done <<<"$1"
  return 1
}

# extension_registered: a not-yet-terminated extension record is listed (active
# or pending approval). It counts as an installed component so that a pending
# extension of an unknown or different version is routed to migration.
classify_virtualhid_install_state() {
  local installed_version=$1
  local expected_version=$2
  local support_present=$3
  local manager_present=$4
  local daemon_executable=$5
  local manager_executable=$6
  local extension_registered=$7
  local components_present=false

  if [[ "$support_present" == true || "$manager_present" == true || "$extension_registered" == true ]]; then
    components_present=true
  fi

  if [[ -n "$installed_version" && "$installed_version" != "$expected_version" && "$components_present" == true ]]; then
    printf '%s\n' different-version
  elif [[ -z "$installed_version" && "$components_present" == true ]]; then
    printf '%s\n' unreceipted-components
  elif [[ "$installed_version" == "$expected_version" && "$daemon_executable" == true && "$manager_executable" == true ]]; then
    printf '%s\n' ready
  else
    printf '%s\n' install
  fi
}

# extension_registered: a not-yet-terminated extension record is listed and
# must be deactivated by the vendor manager before removing files.
classify_virtualhid_cleanup_state() {
  local extension_registered=$1
  local manager_executable=$2
  local deactivate_executable=$3
  local artifacts_present=$4
  local remover_available=$5

  if [[ "$extension_registered" == true && "$manager_executable" != true ]]; then
    printf '%s\n' active-missing-manager
  elif [[ "$extension_registered" == true && "$deactivate_executable" != true ]]; then
    printf '%s\n' active-missing-deactivator
  elif [[ "$artifacts_present" == true && "$remover_available" != true ]]; then
    printf '%s\n' incomplete-files
  else
    printf '%s\n' ready
  fi
}
