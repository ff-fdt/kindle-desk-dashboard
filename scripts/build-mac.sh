#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/build-renderer.sh
APP="$PWD/build/Kindle Desk Bluetooth.app"
mkdir -p "$APP/Contents/MacOS"
cp mac/Info.plist "$APP/Contents/Info.plist"
swiftc -O mac/Bluetooth.swift -framework CoreBluetooth -framework AppKit -o "$APP/Contents/MacOS/KindleDeskBluetooth"
codesign --force --sign - --identifier uk.felixf.kindledesk.bluetooth "$APP"
printf '%s\n' "$APP"
