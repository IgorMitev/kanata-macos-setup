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

## Install workflow

Clone the repository and validate it before installing:

```bash
./tests/static-checks.sh
```

Then follow [Installation](docs/installation.md):

1. Run the installer.
2. Complete the macOS approval checkpoints.
3. Run repository verification.
4. Execute the [acceptance test plan](docs/acceptance-tests.md).

If the Mac already has Karabiner-Elements or Homebrew Kanata, use
[Migration from Karabiner or Homebrew Kanata](docs/migration-from-karabiner.md)
before following the normal installation workflow.

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

Use the repository uninstaller rather than deleting driver files by hand:

```bash
./scripts/uninstall.sh
```

The normal uninstaller removes only repository-managed services, runtime files,
and logs. It leaves the standalone VirtualHID package and extension installed.
Legacy cleanup and rollback are documented separately in
[Migration from Karabiner or Homebrew Kanata](docs/migration-from-karabiner.md).

## Development validation

The static checks are read-only. They validate shell syntax, launchd property lists, required repository files, and documentation references without loading services, installing packages, or changing System Settings:

```bash
./tests/static-checks.sh
```

Successful static checks do not prove that macOS permissions or the DriverKit extension are active; `./scripts/verify.sh` and the manual acceptance tests cover those runtime conditions.
