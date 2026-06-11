# Kanata macOS setup

Personal macOS Kanata setup for home-row mods, Caps Lock → Backspace, Magic Keyboard-style function keys, and home-row arrow chords.

This repo installs Kanata as a root LaunchDaemon and uses the Karabiner VirtualHIDDevice driver on macOS. It does **not** require active Karabiner-Elements remaps.

## What this config does

- Home-row mods:
  - `A` hold → left shift
  - `S` hold → left control
  - `D` hold → left option
  - `F` hold → left command
  - `J` hold → right command
  - `K` hold → right option
  - `L` hold → right control
  - `;` hold → right shift
- `Caps Lock` → Backspace
- `D+F+J/K/I/L` → left/down/up/right arrows
- `Command+Option+J/K/I/L` → left/down/up/right arrows
- `F1`–`F12` → Apple media/function behavior

## Requirements

- macOS
- Homebrew
- `sudo` access
- Kanata privacy permissions:
  - System Settings → Privacy & Security → Input Monitoring
  - System Settings → Privacy & Security → Accessibility
- Karabiner VirtualHIDDevice driver enabled:
  - System Settings → General → Login Items & Extensions → Driver Extensions

## Install

Clone the repo, then run:

```bash
./scripts/install-vhid-daemon.sh
./scripts/install.sh
./scripts/verify.sh
```

`install-vhid-daemon.sh` expects the standalone Karabiner VirtualHIDDevice package to already be installed. If it is missing, the script prints the download URL.

The Kanata installer defaults to the internal MacBook keyboard:

```text
Apple Internal Keyboard / Trackpad
```

Override it if needed:

```bash
PRIMARY_DEVICE="Exact Keyboard Name" ./scripts/install.sh
```

Find keyboard names with:

```bash
/opt/homebrew/bin/kanata --list
```

## macOS permissions

After installing, add/enable Kanata in both:

```text
System Settings → Privacy & Security → Input Monitoring
System Settings → Privacy & Security → Accessibility
```

Add both paths if macOS distinguishes them:

```text
/opt/homebrew/opt/kanata/bin/kanata
/opt/homebrew/Cellar/kanata/<version>/bin/kanata
```

## Karabiner-Elements note

Kanata on macOS needs the Karabiner VirtualHIDDevice **driver**, but active Karabiner-Elements remaps can conflict with Kanata and cause duplicated letters.

Recommended setup:

```text
Karabiner VirtualHIDDevice driver enabled
Karabiner-Elements remaps disabled/not running
Kanata LaunchDaemon running
```

## Verify

```bash
./scripts/verify.sh
```

Expected Kanata log lines include:

```text
driver activated: true
driver connected: true
Starting kanata proper
```

## Uninstall Kanata setup

```bash
./scripts/uninstall.sh
```

This removes the Kanata LaunchDaemon and local Kanata config. It intentionally leaves the Karabiner VirtualHIDDevice driver installed.
