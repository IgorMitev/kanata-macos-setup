# Installation

This is the normal workflow for a clean Apple Silicon Mac. If the Mac already
has Karabiner-Elements or Homebrew Kanata, follow
[Migration and complete removal](migration-from-karabiner.md) to create a
verified blank slate first.

Kanata and VirtualHID do not need to be installed in advance. The installer
downloads, verifies, and installs both pinned dependencies. It also repairs a
same-version VirtualHID installation whose required daemon or manager file is
missing, and ignores a harmless Karabiner-Elements receipt when no application,
support files, service, or process remains. Receipt-only VirtualHID metadata and
a terminated system-extension record without installed files do not block
installation. Rerunning the installer over a healthy repository installation is
supported and idempotent.

The installer intentionally stops for a different-version or unreceipted
VirtualHID installation that still has files or a registered extension (active
or awaiting approval), for any Karabiner-Elements application, support files,
service files, loaded services, or processes, and for legacy remapping services
such as `karabiner_grabber`. Those states require the vendor-assisted migration
cleanup because replacing a live or staged keyboard driver may require
deactivation and a restart. The installer, migration cleanup, and
`verify.sh --blank-slate` share one legacy-component inventory, so a passing
blank-slate check is accepted by the installer's legacy-state checks.

## Requirements

- Keep a reliable recovery keyboard available until verification passes. A
  MacBook's internal keyboard is sufficient; a Mac without a built-in keyboard
  needs a wired external keyboard.
- Use an administrator account for the prompted system operations.
- Keep internet access available while the pinned artifacts are downloaded.

## Validate and install

From the repository root, run both commands as the logged-in user, not with
`sudo`. The installer requests administrator authentication when a system
operation needs it.

```bash
./tests/static-checks.sh
./scripts/install.sh
```

The installer verifies the pinned Kanata and VirtualHID downloads before
installing them. It installs the stable Kanata executable at:

```text
/Library/Application Support/local.kanata-macos-setup/bin/kanata
```

## macOS approvals

Complete each approval macOS requests:

1. Enable the pqrs.org VirtualHID driver extension under System Settings →
   General → Login Items & Extensions → Driver Extensions.
2. Add and enable the stable Kanata executable under Privacy & Security →
   Input Monitoring.
3. Add and enable the same executable under Privacy & Security → Accessibility.
4. Restart macOS if the driver approval panel or installer requests it.

If macOS displays an older Kanata entry, remove it and add the stable path
above. Moving or replacing an executable can leave a stale privacy entry even
when its displayed name is unchanged.

## Verify

Run:

```bash
./scripts/verify.sh --installed
```

Verification must pass after installation, after privacy changes, and after a
restart. Then complete the [Acceptance tests](acceptance-tests.md), including a
restart with the Bluetooth keyboard off and a late Bluetooth connection.

For removal, choose between the repository-only uninstaller and the complete
blank-slate workflow described in the [README](../README.md#uninstall). Do not
manually remove VirtualHID driver files.
