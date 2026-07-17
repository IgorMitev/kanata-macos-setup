# Installation

This is the normal workflow for a clean Apple Silicon Mac. If the Mac already
has Karabiner-Elements or Homebrew Kanata, follow
[Migration from Karabiner or Homebrew Kanata](migration-from-karabiner.md)
first.

## Requirements

- Keep a reliable keyboard connected by cable until verification passes.
- Use an administrator account for the prompted system operations.
- Keep internet access available while the pinned artifacts are downloaded.

## Validate and install

From the repository root:

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
