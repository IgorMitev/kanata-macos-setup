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
- `com.igormitev.kanata.virtualhid` keeps the VirtualHID daemon available.
- `com.igormitev.kanata` supervises Kanata and handles keyboard connection changes.
- Kanata accepts arbitrary physical keyboards and ignores its virtual output device.
- Kanata keeps the configured remapping active at the login/lock screen and during user switching.

Repository-managed runtime files live under `/Library/Application Support/com.igormitev.kanata`, and logs live under `/Library/Logs/com.igormitev.kanata`. The stable executable approved in macOS is `/Library/Application Support/com.igormitev.kanata/bin/kanata`.

The repository intentionally does not depend on Homebrew for Kanata. An existing Homebrew installation is left alone.

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
- A keyboard connected by cable during driver removal or installation
- Permission to restart macOS when requested

Keep a wired keyboard available until verification passes. If the standalone driver is inactive, Kanata cannot emit replacement keystrokes.

## Recommended workflow

Do not begin with removal. First clone the repository and review or validate it while the current keyboard setup still works:

```bash
./tests/static-checks.sh
```

Then follow the guided sequence in [Clean-slate installation](docs/clean-slate-install.md):

1. Archive the current Kanata/Karabiner state outside all removal paths.
2. Remove the current Kanata installation and Karabiner-Elements dependencies.
3. Restart and verify that the Mac is at a blank slate.
4. Install the pinned standalone VirtualHID driver and Kanata through this repository.
5. Complete the macOS approval checkpoints.
6. Run repository verification.
7. Execute the [acceptance test plan](docs/acceptance-tests.md).

The removal steps are intentionally interactive and should only be run after the archive has been inspected.

Create the archive with:

```bash
./scripts/archive-current.sh
```

Inspect the printed archive path and retain it for the purge command. Purge will
refuse to run without a completed archive.

## macOS approval checkpoints

macOS security approvals cannot be bypassed by the installer. Expect to pause for one or more of these actions:

1. **Driver extension:** System Settings → General → Login Items & Extensions → Driver Extensions. Enable the pqrs.org/Karabiner VirtualHIDDevice extension.
2. **Privacy:** System Settings → Privacy & Security → Input Monitoring. Enable the installed Kanata executable.
3. **Accessibility:** System Settings → Privacy & Security → Accessibility. Enable Kanata if macOS requests it.
4. **Restart:** restart when macOS or the installer requests it, then resume verification.

Approve the stable installed Kanata path, not a temporary download or a versioned Homebrew Cellar path.

## Install and verify

After the clean-slate steps in the runbook:

```bash
./scripts/install.sh
./scripts/verify.sh
```

Run verification again after every restart and after changing privacy permissions. Do not proceed to home-row tuning until verification passes and both the cabled Magic Keyboard and Bluetooth R-GO Keyboard pass the lifecycle tests.

## Uninstall and reset

Use the repository uninstaller rather than deleting driver files by hand:

```bash
./scripts/uninstall.sh
```

This default mode removes only components installed and owned by this repository. For the one-time clean-slate migration, first create and inspect the archive, then use the explicit purge mode:

```bash
./scripts/uninstall.sh --purge --archive "/absolute/path/to/the/inspected/archive"
```

Purge additionally removes legacy Homebrew Kanata, Karabiner-Elements, and standalone VirtualHID components after confirmation. It does not remove Homebrew itself or unrelated packages. The VirtualHID system extension must be deactivated before its files are removed. Follow any restart instruction before judging the reset complete. See [Recovery and rollback](docs/clean-slate-install.md#recovery-and-rollback) if keyboard output is lost or installation is interrupted.

Never remove the pre-migration archive automatically. Delete it only after this setup passes acceptance testing and has also been reproduced successfully on the destination Mac.

## Development validation

The static checks are read-only. They validate shell syntax, launchd property lists, required repository files, and documentation references without loading services, installing packages, or changing System Settings:

```bash
./tests/static-checks.sh
```

Successful static checks do not prove that macOS permissions or the DriverKit extension are active; `./scripts/verify.sh` and the manual acceptance tests cover those runtime conditions.
