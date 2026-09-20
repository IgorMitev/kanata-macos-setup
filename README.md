# Kanata macOS setup

Reproducible, Apple Silicon-only setup for running Kanata on macOS with the standalone Karabiner VirtualHIDDevice driver. **Karabiner-Elements is not installed or required.**

The keyboard layout provides home-row modifiers, Caps Lock → Backspace, Apple-style media keys, and arrow chords. The deployment is designed to start when no Bluetooth keyboard is connected and to pick up keyboards that connect later.

## Architecture

```text
physical keyboard(s)
        ↓
      Kanata
        ↓
standalone Karabiner VirtualHIDDevice
        ↓
      macOS
```

- Kanata is pinned to version 1.12.0 for Apple Silicon.
- Karabiner VirtualHIDDevice is pinned to version 6.2.0 and installed independently.
- `local.kanata-macos-setup.virtualhid` keeps the VirtualHID daemon available.
- `local.kanata-macos-setup` supervises Kanata and handles keyboard connection changes.
- Kanata accepts arbitrary physical keyboards and ignores its virtual output device.
- Kanata keeps the configured remapping active at the login/lock screen and during user switching.

Repository-managed runtime files live under `/Library/Application Support/local.kanata-macos-setup`, and logs live under `/Library/Logs/local.kanata-macos-setup`. The stable executable approved in macOS is `/Library/Application Support/local.kanata-macos-setup/bin/kanata`.

The repository intentionally does not depend on Homebrew for Kanata. The Homebrew package manager and unrelated formulae are left alone.

Kanata and VirtualHID may both be absent on a clean Mac; the installer fetches
and verifies them. Receipt-only remnants do not block installation. Any
remaining Karabiner-Elements application, support files, service files, or
processes, or a different VirtualHID version with installed files or a
registered extension (active or awaiting approval), are migration states
handled by the documented vendor-assisted cleanup. Rerunning the installer on a
healthy installation is supported.

## Keyboard behavior

- `A` / `S` / `D` / `F` held → left Shift / Control / Option / Command
- `J` / `K` / `L` / `;` held → right Command / Option / Control / Shift
- `Caps Lock` → Backspace
- `D+F+J/K/I/L` → left/down/up/right arrows
- `Command+Option+J/K/I/L` → left/down/up/right arrows
- `F1`–`F12` → Apple media/function behavior

Home-row timing is deliberately treated as a second phase. First prove that installation, permissions, startup, and keyboard hot-plugging are reliable; then tune typing behavior using repeatable tests.

## Requirements

- An Apple Silicon Mac
- macOS administrator access
- Internet access during installation
- A built-in keyboard, or a wired keyboard on a Mac without one, during driver removal or installation
- Permission to restart macOS when requested

Keep a built-in or wired keyboard available until verification passes. A
MacBook's internal keyboard is a suitable recovery keyboard; a desktop Mac such
as a Mac mini needs a wired external keyboard. If the standalone driver is
inactive, Kanata cannot emit replacement keystrokes.

## Install workflow

Clone the repository, open a shell at its root, and run all repository scripts as
the logged-in user, **not** with `sudo`. The scripts request administrator
authentication for the individual system operations that need it.

Validate the repository before installing:

```bash
./tests/static-checks.sh
```

Then follow [Installation](docs/installation.md):

1. Run `./scripts/install.sh` as the logged-in user.
2. Complete the macOS approval checkpoints and restart if requested.
3. Run `./scripts/verify.sh --installed`; rerun it after approval changes and restarts.
4. Execute the [acceptance test plan](docs/acceptance-tests.md).

If the Mac already has Karabiner-Elements or Homebrew Kanata, use
[Migration and complete removal](docs/migration-from-karabiner.md) to create a
verified blank slate before following the normal installation workflow.

## macOS approval checkpoints

macOS security approvals cannot be bypassed by the installer. Expect to pause for one or more of these actions:

1. **Driver extension:** System Settings → General → Login Items & Extensions → Driver Extensions. Enable the pqrs.org/Karabiner VirtualHIDDevice extension.
2. **Privacy:** System Settings → Privacy & Security → Input Monitoring. Enable the installed Kanata executable.
3. **Accessibility:** System Settings → Privacy & Security → Accessibility. Enable Kanata if macOS requests it.
4. **Restart:** restart when macOS or the installer requests it, then resume verification.

Approve the stable installed Kanata path, not a temporary download or a versioned Homebrew Cellar path.

## Install and verify

```bash
./scripts/install.sh
./scripts/verify.sh --installed
```

Run verification again after every restart and after changing privacy permissions. Do not proceed to home-row tuning until verification passes and both the cabled Magic Keyboard and Bluetooth R-GO Keyboard pass the lifecycle tests.

## Uninstall

Run uninstall scripts as the logged-in user, not with `sudo`.

### Remove only the repository installation

```bash
./scripts/uninstall.sh
```

This stops and removes only repository-managed Kanata and VirtualHID services,
runtime files, and logs. It deliberately leaves the standalone VirtualHID
package and system extension installed, along with Homebrew, Karabiner-Elements,
legacy Kanata, and user configuration.

### Remove Kanata, Karabiner-Elements, and standalone VirtualHID

A complete removal is the destructive blank-slate workflow in
[Migration and complete removal](docs/migration-from-karabiner.md):

1. Keep a built-in or wired recovery keyboard available.
2. Run the static checks.
3. Create and inspect an archive with `./scripts/migration/archive-current.sh`.
4. Run `./scripts/migration/purge-legacy.sh --archive "/absolute/path/to/the/inspected/archive"`.
5. Restart when requested.
6. Run `./scripts/verify.sh --blank-slate`.

Do not manually delete a loaded VirtualHID extension or its driver files.

## Development validation

The static checks are read-only. They validate shell syntax, launchd property lists, required repository files, and documentation references without loading services, installing packages, or changing System Settings:

```bash
./tests/static-checks.sh
```

Successful static checks do not prove that macOS permissions or the DriverKit extension are active; `./scripts/verify.sh --installed` and the manual acceptance tests cover those runtime conditions.
