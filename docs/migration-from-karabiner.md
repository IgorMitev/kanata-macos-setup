# Migration from Karabiner or Homebrew Kanata

This runbook moves an Apple Silicon Mac from Karabiner-Elements, Homebrew
Kanata, or this repository's installation to the repository-managed setup. It
deliberately separates preparation from destructive work.

## Safety boundary

Before uninstalling anything:

- Confirm a recovery keyboard types normally. Use the internal keyboard on a
  MacBook, or connect a wired external keyboard on a Mac without one.
- Keep this page and the repository available locally.
- Confirm that administrator authentication and multiple restarts are acceptable.
- Run `./tests/static-checks.sh` and resolve every failure.
- Run `./scripts/migration/archive-current.sh` and create the migration archive on a path that none of the uninstall or reset operations remove.

Do not manually delete a loaded DriverKit extension. Deactivate it using its vendor manager/uninstaller, then restart if requested.

## Phase 0: archive and inspect

The archive should include, when present:

- live Kanata configuration and wrapper scripts;
- Kanata and VirtualHID logs;
- Kanata/Karabiner launchd property lists;
- Karabiner configuration;
- installed binary and package versions;
- package receipts and system-extension state;
- Kanata's keyboard-device listing;
- relevant service and process status.

Inspect the resulting archive before continuing. It must be outside the repository's installed configuration directories and all paths targeted by uninstall/reset. Record its absolute path.

The archive is for recovery and comparison. Do not copy archived service files into the new installation.

The archive can contain keyboard configuration, logs, process listings, package
state, and the Mac's computer name. Treat it as sensitive local diagnostic data;
do not commit it or share it without reviewing its contents.

## Phase 1: create the blank slate

Keep the built-in or wired recovery keyboard available throughout this phase.

1. Run `./scripts/migration/purge-legacy.sh --archive "/absolute/path/to/the/inspected/archive"` and review its removal summary.
2. Confirm purge only after verifying the archive and the built-in or wired recovery keyboard.
3. Allow purge to stop and unload the existing Kanata service.
4. Allow it to remove only the Homebrew `kanata` formula; leave Homebrew and all unrelated formulae installed.
5. Allow it to deactivate the currently installed VirtualHID system extension with the vendor-provided manager.
6. Allow it to run the official Karabiner-Elements uninstaller if Karabiner-Elements is installed.
7. Allow it to remove standalone VirtualHID components with the vendor-provided uninstaller where applicable.
8. Allow it to remove only project-owned Kanata services, installed configuration, and logs.
9. Restart macOS when requested.
10. Run the repository verification/reset check and inspect any remaining components before deleting them.

A blank slate means:

- normal, unmodified keyboard input still works;
- no Kanata or Karabiner processes are running;
- no Kanata service or project-installed VirtualHID daemon is loaded;
- the pqrs VirtualHID system extension is not active;
- the Homebrew Kanata formula is absent;
- Homebrew and unrelated packages remain intact.

Package receipts or disabled extension records can remain visible after a correct vendor uninstall. Treat them as evidence to investigate, not permission to delete arbitrary system files.

## Phase 2: repository installation

1. Run `./scripts/install.sh` from this repository.
2. Authenticate administrator operations when prompted.
3. Allow the installer to download and verify the pinned Kanata and VirtualHID artifacts.
4. Stop at every printed macOS approval checkpoint.
5. Enable the pqrs.org Driver Extension in System Settings.
6. Restart if macOS requests it.
7. Grant Input Monitoring to the stable installed Kanata executable.
8. Grant Accessibility only if macOS requests it or verification reports it missing.
9. Run `./scripts/verify.sh`.

If privacy controls show an old or temporary Kanata entry, remove that stale entry and add/enable the stable installed executable named by the installer. A copied executable can require a new approval even when it has the same name.

## Phase 3: deployment acceptance

Do not tune home-row timing yet. Complete the deployment and lifecycle cases in [Acceptance tests](acceptance-tests.md), including:

- boot with the Bluetooth R-GO Keyboard disconnected;
- connect, disconnect, and reconnect the R-GO Keyboard;
- type from the cabled and Bluetooth keyboards;
- remapping continuity across lock/unlock and fast user switching;
- sleep/wake and restart;
- supervised recovery after Kanata exits.

Record failures with the time, connected devices, verification output, and recent service logs. Change one deployment variable at a time, rerun static checks, then repeat the failed case and the basic smoke test.

## Phase 4: home-row tuning

Only begin after deployment acceptance passes. Establish a baseline using the existing layout, then adjust one behavior or timing value per iteration. Each iteration must preserve deliberate shortcuts, multi-modifier chords, arrows, media keys, and both keyboards.

Use the repeatable typing sample in [Acceptance tests](acceptance-tests.md#home-row-accuracy-phase) and record accidental modifiers, lost letters, duplicate letters, and stuck modifiers. A practical acceptance target is five minutes of normal and fast typing with no configuration-induced shortcuts or stuck modifiers.

## Recovery and rollback

If keyboard output is lost:

1. Keep the MacBook's internal keyboard available, or reconnect the wired recovery keyboard.
2. Stop the Kanata service using the repository uninstaller or the exact recovery command printed by the installer.
3. Confirm normal keyboard input before attempting another driver action.
4. Do not delete the active VirtualHID extension manually.
5. If necessary, restart and leave Kanata disabled while collecting verification output.

If installation is interrupted:

1. Rerun `./scripts/verify.sh` to identify which layer is incomplete.
2. Complete the missing macOS approval or restart.
3. Rerun the idempotent installer rather than copying files manually.
4. If verification still fails, use `./scripts/uninstall.sh` to remove only repository-owned components, restart if requested, confirm normal keyboard input, and retry from the repository.

Rollback to the previous setup only from the migration archive and only after the new services are stopped. Restore the smallest needed layer first; do not load old and new Kanata or VirtualHID services together.

Retain the archive until the local acceptance plan and a clean installation on the destination Mac both pass. Removing it is a separate, explicit decision.
