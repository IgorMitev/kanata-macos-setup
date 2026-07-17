#!/usr/bin/env bash

# Reproducible upstream inputs. Updating a version requires updating its digest.
KANATA_VERSION="1.12.0"
KANATA_ARCHIVE_NAME="macos-binaries-arm64.zip"
KANATA_BINARY_NAME="kanata_macos_arm64"
KANATA_URL="https://github.com/jtroo/kanata/releases/download/v${KANATA_VERSION}/${KANATA_ARCHIVE_NAME}"
KANATA_SHA256="839769d189911b5881e11550eaa2039705213fb725865d088f5a2e3a6c10de32"

VHID_VERSION="6.2.0"
VHID_PACKAGE_NAME="Karabiner-DriverKit-VirtualHIDDevice-${VHID_VERSION}.pkg"
VHID_URL="https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v${VHID_VERSION}/${VHID_PACKAGE_NAME}"
VHID_SHA256="9e8c46239f0748161241e42444857901224e5c82f5b58a1731df4c70bf0736a8"
VHID_TEAM_ID="G43BCU2T37"
